import AppKit
import ChopCore

@MainActor
final class TerminalPaneView: NSView {
  let id: UUID
  let engine: TerminalEngine
  private(set) var terminal: TerminalView?
  var workingDirectory: String
  var name: String {
    didSet {
      updateHeader()
      onChange?()
    }
  }
  var onChange: (() -> Void)?
  var onFocus: (() -> Void)?
  var onSplitRequested: ((SplitAxis) -> Void)?
  var canSplit: ((SplitAxis) -> Bool)?
  var onRemoveRequested: (() -> Void)?
  var onZoomRequested: (() -> Void)?
  var onDirectoryFallback: ((String) -> Void)?
  var canRemove = false { didSet { updateHeader() } }
  var canZoom = false { didSet { updateHeader() } }
  var isZoomed = false { didSet { updateHeader() } }
  var isFocused = false {
    didSet {
      layer?.borderWidth = isFocused ? 1 : 0
      layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
    }
  }
  var isEditing = false { didSet { updateAddButton() } }
  private let header = NSView()
  private let body = NSView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let pathLabel = NSTextField(labelWithString: "")
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private var openButton: NSButton!
  private var closeButton: NSButton!
  private var zoomButton: NSButton!

  init(
    engine: TerminalEngine, id: UUID = UUID(), name: String = "터미널 1",
    workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) {
    self.engine = engine
    self.id = id
    self.name = name
    self.workingDirectory = workingDirectory
    super.init(frame: .zero)
    appearance = NSAppearance(named: .aqua)
    wantsLayer = true
    layer?.backgroundColor = ChopStyle.background.cgColor
    setAccessibilityIdentifier("pane-\(id.uuidString)")
    configureViews()
    updateHeader()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(engine:).") }

  var isRunning: Bool { terminal != nil }
  var needsConfirmClose: Bool { terminal?.needsConfirmClose ?? false }

  @objc func openTerminal() {
    guard terminal == nil else {
      focus()
      return
    }
    do {
      if let missing = resolveWorkingDirectory() { onDirectoryFallback?(missing) }
      layoutSubtreeIfNeeded()
      let view = try TerminalView(
        engine: engine, workingDirectory: workingDirectory, frame: body.bounds)
      terminal = view
      view.onExit = { [weak self, weak view] in
        guard let self, let view, self.terminal === view else { return }
        self.closeTerminal()
      }
      view.onFocus = { [weak self] in self?.onFocus?() }
      view.onMetadataChange = { [weak self] in
        guard let self, let terminal = self.terminal else { return }
        self.workingDirectory = terminal.workingDirectory
        self.updateHeader()
        self.onChange?()
      }
      body.addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: body.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        view.topAnchor.constraint(equalTo: body.topAnchor),
        view.bottomAnchor.constraint(equalTo: body.bottomAnchor),
      ])
      body.addSubview(openButton, positioned: .above, relativeTo: view)
      updateAddButton()
      errorLabel.isHidden = true
      updateHeader()
      focus()
      onChange?()
    } catch {
      errorLabel.stringValue = error.localizedDescription
      errorLabel.isHidden = false
      openButton.setAccessibilityLabel("다시 열기")
      openButton.toolTip = "다시 열기"
    }
  }

  func closeTerminal() {
    guard let terminal else { return }
    workingDirectory = terminal.workingDirectory
    terminal.close()
    terminal.removeFromSuperview()
    self.terminal = nil
    openButton.isHidden = false
    errorLabel.isHidden = true
    openButton.setAccessibilityLabel("터미널 열기")
    openButton.toolTip = "터미널 열기"
    updateHeader()
    focus()
    onChange?()
  }

  /// Resolve every saved path before restore; no path is interpreted as a command.
  func resolveWorkingDirectory() -> String? {
    var isDirectory: ObjCBool = false
    guard
      !FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory)
        || !isDirectory.boolValue || !FileManager.default.isReadableFile(atPath: workingDirectory)
        || !FileManager.default.isExecutableFile(atPath: workingDirectory)
    else { return nil }
    let missing = workingDirectory
    workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    updateHeader()
    onChange?()
    return missing
  }

  func focus() {
    window?.makeFirstResponder(terminal ?? openButton)
    onFocus?()
  }

  @objc func requestClose() {
    guard isRunning else {
      onRemoveRequested?()
      return
    }
    if needsConfirmClose {
      let alert = NSAlert()
      alert.messageText = "이 터미널을 닫을까요?"
      alert.informativeText = "이 칸에서 실행 중인 작업이 종료됩니다."
      alert.addButton(withTitle: "취소")
      alert.addButton(withTitle: "터미널 닫기")
      guard alert.runModal() == .alertSecondButtonReturn else { return }
    }
    closeTerminal()
  }

  override func mouseDown(with event: NSEvent) { focus() }

  @objc private func toggleZoom() { onZoomRequested?() }

  @objc private func addFromCenter() {
    guard isRunning else {
      openTerminal()
      return
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (title, action, axis) in [
      ("오른쪽에 추가", #selector(addRight), SplitAxis.horizontal),
      ("아래에 추가", #selector(addDown), .vertical),
    ] {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
      item.isEnabled = canSplit?(axis) ?? false
    }
    menu.popUp(
      positioning: nil, at: NSPoint(x: openButton.frame.minX, y: openButton.frame.minY), in: body)
  }

  @objc private func addRight() { onSplitRequested?(.horizontal) }
  @objc private func addDown() { onSplitRequested?(.vertical) }

  private func updateAddButton() {
    openButton.isHidden = isRunning && !isEditing
    let label = isRunning ? "터미널 추가" : "터미널 열기"
    openButton.setAccessibilityLabel(label)
    openButton.toolTip = label
  }

  private func configureViews() {
    for view in [header, body] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    titleLabel.font = ChopStyle.font
    titleLabel.textColor = ChopStyle.foreground
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    pathLabel.font = ChopStyle.font
    pathLabel.textColor = .secondaryLabelColor
    pathLabel.lineBreakMode = .byTruncatingMiddle
    pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let close = ChopStyle.iconButton(
      "xmark", label: "터미널 닫기", target: self, action: #selector(requestClose))
    closeButton = close
    zoomButton = ChopStyle.iconButton(
      "arrow.up.left.and.arrow.down.right", label: "칸 확대", target: self,
      action: #selector(toggleZoom))
    let row = NSStackView(views: [titleLabel, pathLabel, zoomButton, close])
    row.orientation = .horizontal
    row.distribution = .fill
    row.spacing = 12
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(row)
    openButton = NSButton(
      image: NSImage(systemSymbolName: "plus", accessibilityDescription: "터미널 열기")!, target: self,
      action: #selector(addFromCenter))
    openButton.bezelStyle = .circular
    openButton.controlSize = .large
    openButton.toolTip = "터미널 열기"
    openButton.setAccessibilityLabel("터미널 열기")
    openButton.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(openButton)
    errorLabel.font = ChopStyle.font
    errorLabel.textColor = .secondaryLabelColor
    errorLabel.alignment = .center
    errorLabel.isHidden = true
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(errorLabel)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: leadingAnchor),
      header.trailingAnchor.constraint(equalTo: trailingAnchor),
      header.topAnchor.constraint(equalTo: topAnchor),
      header.heightAnchor.constraint(equalToConstant: ChopStyle.headerHeight),
      row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: ChopStyle.inset),
      row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -ChopStyle.inset),
      row.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      body.leadingAnchor.constraint(equalTo: leadingAnchor),
      body.trailingAnchor.constraint(equalTo: trailingAnchor),
      body.topAnchor.constraint(equalTo: header.bottomAnchor),
      body.bottomAnchor.constraint(equalTo: bottomAnchor),
      openButton.centerXAnchor.constraint(equalTo: body.centerXAnchor),
      openButton.centerYAnchor.constraint(equalTo: body.centerYAnchor),
      openButton.widthAnchor.constraint(equalToConstant: 56),
      openButton.heightAnchor.constraint(equalToConstant: 56),
      errorLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 16),
      errorLabel.centerXAnchor.constraint(equalTo: body.centerXAnchor),
      errorLabel.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor, constant: -32),
    ])
  }

  private func updateHeader() {
    titleLabel.stringValue = name
    titleLabel.toolTip = "\(name) — 이름 바꾸기: ⌘⇧R"
    pathLabel.stringValue = (workingDirectory as NSString).abbreviatingWithTildeInPath
    pathLabel.toolTip = workingDirectory
    terminal?.setAccessibilityLabel("\(name) 터미널")
    closeButton.isEnabled = isRunning || canRemove
    let closeLabel = isRunning ? "터미널 닫기" : "빈 칸 제거"
    closeButton.setAccessibilityLabel(closeLabel)
    closeButton.toolTip = closeLabel
    let zoomLabel = isZoomed ? "전체 레이아웃으로 돌아가기" : "칸 확대"
    zoomButton.setAccessibilityLabel(zoomLabel)
    zoomButton.isEnabled = canZoom
    zoomButton.toolTip = zoomLabel
    zoomButton.image = NSImage(
      systemSymbolName: isZoomed
        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
      accessibilityDescription: zoomLabel)
  }
}
