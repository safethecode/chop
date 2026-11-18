import AppKit
import ChopCore

@MainActor
final class TerminalSearchView: NSView, NSSearchFieldDelegate {
  let searchField = InsetSearchField(frame: .zero)
  let output = TerminalSearchTextView()
  private let scroll = NSScrollView()
  private let status = NSTextField(labelWithString: "")
  private let bar = NSView()
  private var searchTask: Task<Void, Never>?
  private(set) var matches: [NSRange] = []
  private(set) var selectedMatch = 0
  private var isLimited = false
  private var previous: NSButton!
  private var next: NSButton!
  var onClose: (() -> Void)?
  var onRefresh: (() -> String?)?

  init(text: String, mode: AppearanceMode) {
    super.init(frame: .zero)
    setAccessibilityLabel("터미널 출력 검색")
    wantsLayer = true
    bar.wantsLayer = true
    searchField.placeholderString = "출력에서 찾기"
    searchField.setAccessibilityLabel("터미널 출력에서 찾기")
    searchField.font = ChopStyle.font
    searchField.delegate = self
    status.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    status.setContentHuggingPriority(.required, for: .horizontal)
    previous = ChopStyle.iconButton(
      "chevron.up", label: "이전 결과", target: self, action: #selector(previousMatch))
    next = ChopStyle.iconButton(
      "chevron.down", label: "다음 결과", target: self, action: #selector(nextMatch))
    let refresh = ChopStyle.iconButton(
      "arrow.clockwise", label: "최신 출력 불러오기", target: self, action: #selector(refreshOutput))
    let close = ChopStyle.iconButton(
      "xmark", label: "검색 닫기", target: self, action: #selector(closeSearch))
    let row = ChopStyle.headerRow(views: [searchField, status, previous, next, refresh, close])
    row.spacing = 4
    bar.addSubview(row)
    output.isEditable = false
    output.isSelectable = true
    output.isRichText = false
    output.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    output.textContainerInset = NSSize(width: 12, height: 12)
    output.isVerticallyResizable = true
    output.isHorizontallyResizable = false
    output.autoresizingMask = [.width]
    output.textContainer?.widthTracksTextView = true
    output.setAccessibilityLabel("검색할 터미널 출력")
    output.onEscape = { [weak self] in self?.onClose?() }
    scroll.documentView = output
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    for view in [bar, scroll] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor),
      bar.topAnchor.constraint(equalTo: topAnchor),
      bar.heightAnchor.constraint(equalToConstant: 40),
      row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
      row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
      row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      searchField.heightAnchor.constraint(equalToConstant: 28),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    output.string = text
    applyAppearance(mode)
    updateStatus()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(text:mode:).") }

  func applyAppearance(_ mode: AppearanceMode) {
    appearance = mode.appearance
    bar.layer?.backgroundColor = mode.headerBackground.cgColor
    output.backgroundColor = mode.background
    output.textColor = mode.foreground
    status.textColor = mode.secondaryForeground
  }

  func focusSearch() { window?.makeFirstResponder(searchField) }

  func stop() {
    searchTask?.cancel()
    searchTask = nil
  }

  func controlTextDidChange(_ notification: Notification) {
    guard (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
    search()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
    guard !textView.hasMarkedText() else { return false }
    switch command {
    case #selector(NSResponder.insertNewline(_:)):
      selectMatch(by: NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? -1 : 1)
    case #selector(NSResponder.cancelOperation(_:)):
      onClose?()
    default: return false
    }
    return true
  }

  func search() {
    stop()
    let query = searchField.stringValue
    let text = output.string
    matches = []
    selectedMatch = 0
    isLimited = false
    output.setSelectedRange(NSRange(location: 0, length: 0))
    updateStatus()
    guard !query.isEmpty else { return }
    status.stringValue = "검색 중"
    searchTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
      let worker = Task.detached(priority: .userInitiated) {
        TerminalOutputSearch.find(in: text, query: query)
      }
      let result = await withTaskCancellationHandler {
        await worker.value
      } onCancel: {
        worker.cancel()
      }
      guard !Task.isCancelled, let self, searchField.stringValue == query else { return }
      matches = result.ranges
      isLimited = result.isLimited
      showMatch()
    }
  }

  func selectMatch(by delta: Int) {
    guard !matches.isEmpty else { return }
    selectedMatch = (selectedMatch + delta % matches.count + matches.count) % matches.count
    showMatch()
  }

  private func showMatch() {
    if !matches.isEmpty {
      let range = matches[selectedMatch]
      output.setSelectedRange(range)
      output.scrollRangeToVisible(range)
    }
    updateStatus()
  }

  private func updateStatus() {
    previous.isEnabled = !matches.isEmpty
    next.isEnabled = !matches.isEmpty
    status.stringValue =
      matches.isEmpty
      ? (searchField.stringValue.isEmpty ? "" : "결과 없음")
      : "\(selectedMatch + 1)/\(matches.count)\(isLimited ? "+" : "")"
    status.setAccessibilityLabel(status.stringValue)
    status.toolTip = isLimited ? "결과가 10,000개를 넘어요. 검색어를 좁혀 주세요." : nil
  }

  @objc private func previousMatch() { selectMatch(by: -1) }
  @objc private func nextMatch() { selectMatch(by: 1) }
  @objc private func closeSearch() { onClose?() }
  @objc private func refreshOutput() {
    guard let text = onRefresh?() else {
      NSSound.beep()
      return
    }
    output.string = text
    search()
  }
}

@MainActor
final class TerminalSearchTextView: NSTextView {
  var onEscape: (() -> Void)?
  override func cancelOperation(_ sender: Any?) { onEscape?() }
}
