import AppKit
import ChopCore
import WebKit

// Xcode 16.4의 알림 콜백에는 최신 SDK와 달리 MainActor 표기가 없다.
#if compiler(>=6.2)
  typealias WebAlertCompletion = @MainActor @Sendable () -> Void
#else
  typealias WebAlertCompletion = @Sendable () -> Void
#endif

/// A retained browser surface: layout changes move this view without reloading its page.
@MainActor
final class WebPreviewView: NSView, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {
  let webView: WKWebView
  let addressField = InsetTextField(frame: .zero)
  private(set) var url: URL?
  var onFocus: (() -> Void)?
  var onURLChange: (() -> Void)?
  var openExternally: (URL) -> Void = { NSWorkspace.shared.open($0) }
  private var observations: [NSKeyValueObservation] = []
  private var isClosed = false
  private var showingError = false
  private var scriptAlert: NSAlert?
  private var scriptCompletion: ((NSApplication.ModalResponse) -> Void)?
  var errorMessage: String? { showingError ? noticeLabel.stringValue : nil }
  var canGoBack: Bool {
    webView.canGoBack || (showingError && webView.url != nil && webView.url != url)
  }
  private let toolbar = NSView()
  private let content = NSView()
  private let notice = NSView()
  private let noticeLabel = NSTextField(wrappingLabelWithString: "주소를 입력해 웹사이트를 열어 주세요.")
  private let retryButton = NSButton(title: "다시 불러오기", target: nil, action: nil)
  private lazy var backButton = ChopStyle.iconButton(
    "chevron.left", label: "뒤로", target: self, action: #selector(goBack))
  private lazy var forwardButton = ChopStyle.iconButton(
    "chevron.right", label: "앞으로", target: self, action: #selector(goForward))
  private lazy var reloadButton = ChopStyle.iconButton(
    "arrow.clockwise", label: "새로고침", target: self, action: #selector(reloadOrStop))
  private lazy var externalButton = ChopStyle.iconButton(
    "arrow.up.right", label: "브라우저에서 열기", target: self, action: #selector(openInBrowser))

  init(dataStore: WKWebsiteDataStore = .default()) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init(frame: .zero)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.allowsMagnification = true
    webView.setAccessibilityLabel("웹사이트 미리보기")
    configureViews()
    for keyPath in [\WKWebView.isLoading, \WKWebView.canGoBack, \WKWebView.canGoForward] {
      observations.append(
        webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
          Task { @MainActor [weak self] in self?.refreshControls() }
        })
    }
    observations.append(
      webView.observe(\.url, options: [.new]) { [weak self] _, _ in
        Task { @MainActor [weak self] in
          guard let self, !self.isClosed, let actual = self.webView.url, WebAddress.accepts(actual)
          else {
            return
          }
          self.updateURL(actual)
        }
      })
    refreshControls()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init().") }

  func load(_ url: URL) {
    guard !isClosed, let normalized = WebAddress.parse(url.absoluteString) else { return }
    updateURL(normalized)
    showPage()
    webView.load(URLRequest(url: normalized))
  }

  func focus() {
    if url == nil || showingError {
      focusAddress()
      return
    }
    window?.makeFirstResponder(webView)
    onFocus?()
  }

  @objc func focusAddress() {
    window?.makeFirstResponder(addressField)
    addressField.selectText(nil)
    onFocus?()
  }

  func controlTextDidBeginEditing(_ notification: Notification) { onFocus?() }

  @objc func navigate() {
    onFocus?()
    guard let address = WebAddress.parse(addressField.stringValue) else {
      showNotice("http 또는 https 웹사이트 주소를 입력해 주세요.", retry: false)
      return
    }
    load(address)
    window?.makeFirstResponder(webView)
  }

  @objc func goBack() {
    if showingError, let previous = webView.url, WebAddress.accepts(previous), previous != url {
      updateURL(previous)
      showPage()
    } else {
      showPage()
      webView.goBack()
    }
    focus()
  }

  @objc func goForward() {
    showPage()
    webView.goForward()
    focus()
  }

  @objc func reloadOrStop() {
    if webView.isLoading {
      webView.stopLoading()
      focus()
    } else {
      reload()
    }
  }

  @objc func reload() {
    guard let url, !isClosed else { return }
    let needsRequest =
      showingError || webView.backForwardList.currentItem == nil || webView.url != url
    showPage()
    if needsRequest { load(url) } else { webView.reload() }
    focus()
  }

  @objc func openInBrowser() {
    guard let url, WebAddress.accepts(url), !isClosed else { return }
    focus()
    openExternally(url)
  }

  func changeZoom(by increment: Double) {
    webView.pageZoom = min(3, max(0.5, webView.pageZoom + increment))
  }

  func resetZoom() { webView.pageZoom = 1 }

  func close() {
    isClosed = true
    if let alert = scriptAlert {
      let parent = alert.window.sheetParent
      finishScriptDialog(.abort)
      parent?.endSheet(alert.window, returnCode: .abort)
      alert.window.orderOut(nil)
    }
    observations.removeAll()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    onFocus = nil
    onURLChange = nil
  }

  func applyAppearance(_ mode: AppearanceMode) {
    appearance = mode.appearance
    toolbar.layer?.backgroundColor = mode.headerBackground.cgColor
    notice.layer?.backgroundColor = mode.background.cgColor
    noticeLabel.textColor = mode.secondaryForeground
    webView.underPageBackgroundColor = mode.background
    for button in [backButton, forwardButton, reloadButton, externalButton] {
      button.contentTintColor = mode.secondaryForeground
    }
  }

  private func updateURL(_ actual: URL) {
    // History API 변경도 저장 가능한 주소만 반영한다.
    guard !isClosed, WebAddress.accepts(actual) else { return }
    let changed = url != actual
    url = actual
    if addressField.currentEditor() == nil { addressField.stringValue = actual.absoluteString }
    addressField.toolTip = actual.absoluteString
    refreshControls()
    if changed { onURLChange?() }
  }

  private func showPage() {
    guard !isClosed else { return }
    showingError = false
    notice.isHidden = true
    webView.isHidden = false
    refreshControls()
  }

  private func showNotice(_ message: String, retry: Bool) {
    guard !isClosed else { return }
    showingError = true
    noticeLabel.stringValue = message
    retryButton.isHidden = !retry
    notice.isHidden = false
    webView.isHidden = true
    refreshControls()
    NSAccessibility.post(element: noticeLabel, notification: .valueChanged)
  }

  private func refreshControls() {
    guard !isClosed else { return }
    backButton.isEnabled = canGoBack
    forwardButton.isEnabled = webView.canGoForward
    reloadButton.isEnabled = url != nil
    externalButton.isEnabled = url != nil
    let label = webView.isLoading ? "불러오기 중지" : "새로고침"
    reloadButton.image = NSImage(
      systemSymbolName: webView.isLoading ? "xmark" : "arrow.clockwise",
      accessibilityDescription: label)
    reloadButton.setAccessibilityLabel(label)
    reloadButton.toolTip = label
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    showPage()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if let url = webView.url { updateURL(url) }
    refreshControls()
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    report(error)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) { report(error) }

  private func report(_ error: Error) {
    let code = (error as NSError).code
    guard code != NSURLErrorCancelled else { return }
    showNotice(
      code == NSURLErrorAppTransportSecurityRequiresSecureConnection
        ? "HTTPS 주소로 열어 주세요. 로컬 서버라면 주소도 확인해 주세요."
        : "페이지를 열지 못했어요. 주소와 서버 실행 상태를 확인해 주세요.", retry: true)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    showNotice("웹페이지를 다시 불러와 주세요.", retry: true)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    guard !isClosed else {
      decisionHandler(.cancel)
      return
    }
    if navigationAction.targetFrame?.isMainFrame != false {
      guard let destination = navigationAction.request.url, WebAddress.accepts(destination) else {
        showNotice("이 주소는 미리보기에서 열 수 없어요. http 또는 https 주소를 입력해 주세요.", retry: false)
        decisionHandler(.cancel)
        return
      }
      if navigationAction.shouldPerformDownload {
        updateURL(destination)
        showNotice("다운로드는 오른쪽 위 버튼으로 브라우저에서 열어 주세요.", retry: false)
        decisionHandler(.cancel)
        return
      }
      updateURL(destination)
    }
    decisionHandler(.allow)
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
  ) {
    if navigationResponse.isForMainFrame, !navigationResponse.canShowMIMEType {
      showNotice("이 파일은 오른쪽 위 버튼으로 브라우저에서 열어 주세요.", retry: false)
      decisionHandler(.cancel)
    } else {
      decisionHandler(isClosed ? .cancel : .allow)
    }
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if !isClosed, let destination = navigationAction.request.url, WebAddress.accepts(destination) {
      updateURL(destination)
      showPage()
      webView.load(navigationAction.request)
    }
    return nil
  }

  func webView(
    _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping WebAlertCompletion
  ) {
    let alert = makeScriptAlert(message)
    alert.addButton(withTitle: "확인")
    presentScriptDialog(alert) { _ in completionHandler() }
  }

  func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    let alert = makeScriptAlert(message)
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "확인")
    alert.buttons[0].keyEquivalent = "\u{1b}"
    alert.buttons[1].keyEquivalent = "\r"
    presentScriptDialog(alert) { completionHandler($0 == .alertSecondButtonReturn) }
  }

  func webView(
    _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable (String?) -> Void
  ) {
    let alert = makeScriptAlert(prompt)
    let field = InsetTextField(string: defaultText ?? "")
    field.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
    field.font = ChopStyle.font
    field.setAccessibilityLabel("웹사이트 입력")
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "확인")
    alert.buttons[0].keyEquivalent = "\u{1b}"
    alert.buttons[1].keyEquivalent = "\r"
    presentScriptDialog(alert) {
      completionHandler($0 == .alertSecondButtonReturn ? field.stringValue : nil)
    }
  }

  private func makeScriptAlert(_ message: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "웹사이트 알림"
    alert.informativeText = message
    alert.window.preventsApplicationTerminationWhenModal = false
    return alert
  }

  private func presentScriptDialog(
    _ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void
  ) {
    guard !isClosed, scriptAlert == nil, let window, window.attachedSheet == nil else {
      completion(.abort)
      return
    }
    scriptAlert = alert
    scriptCompletion = completion
    alert.beginSheetModal(for: window) { [weak self] in self?.finishScriptDialog($0) }
  }

  private func finishScriptDialog(_ response: NSApplication.ModalResponse) {
    let completion = scriptCompletion
    scriptCompletion = nil
    scriptAlert = nil
    completion?(response)
  }

  private func configureViews() {
    toolbar.wantsLayer = true
    notice.wantsLayer = true
    addressField.font = ChopStyle.font
    addressField.placeholderString = "localhost:3000 또는 웹사이트 주소"
    addressField.setAccessibilityLabel("웹사이트 주소")
    addressField.delegate = self
    addressField.target = self
    addressField.action = #selector(navigate)
    let row = NSStackView(views: [
      backButton, forwardButton, reloadButton, addressField, externalButton,
    ])
    row.spacing = 4
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    addressField.heightAnchor.constraint(equalToConstant: 28).isActive = true
    addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    toolbar.addSubview(row)
    for view in [toolbar, content] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    for view in [webView, notice] {
      content.addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        view.topAnchor.constraint(equalTo: content.topAnchor),
        view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      ])
    }
    noticeLabel.font = ChopStyle.font
    noticeLabel.alignment = .center
    retryButton.font = ChopStyle.font
    retryButton.bezelStyle = .rounded
    retryButton.target = self
    retryButton.action = #selector(reload)
    retryButton.isHidden = true
    let message = NSStackView(views: [noticeLabel, retryButton])
    message.orientation = .vertical
    message.alignment = .centerX
    message.spacing = 12
    message.translatesAutoresizingMaskIntoConstraints = false
    notice.addSubview(message)
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
      toolbar.topAnchor.constraint(equalTo: topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 40),
      row.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
      row.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
      row.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
      content.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
      message.centerXAnchor.constraint(equalTo: notice.centerXAnchor),
      message.centerYAnchor.constraint(equalTo: notice.centerYAnchor),
      message.widthAnchor.constraint(lessThanOrEqualTo: notice.widthAnchor, constant: -32),
    ])
  }
}
