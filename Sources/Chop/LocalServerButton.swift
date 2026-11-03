import AppKit

/// Shared by pane headers and the selected terminal's tab bar; opening is always user initiated.
@MainActor
final class LocalServerButton: NSButton {
  private(set) var urls: [URL] = []
  private var compact = false
  var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

  init() {
    super.init(frame: .zero)
    target = self
    action = #selector(openServer)
    isBordered = false
    bezelStyle = .inline
    font = ChopStyle.font
    image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    imagePosition = .imageTrailing
    alignment = .right
    cell?.lineBreakMode = .byTruncatingMiddle
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentHuggingPriority(.defaultHigh, for: .horizontal)
    isHidden = true
    translatesAutoresizingMaskIntoConstraints = false
    heightAnchor.constraint(equalToConstant: 28).isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init().") }

  func update(_ urls: [URL]) {
    self.urls = urls
    isHidden = urls.isEmpty
    guard let first = urls.first else { return }
    let address =
      compact
      ? ":\(first.port ?? 80)"
      : first.absoluteString
        .replacingOccurrences(of: "https://", with: "").replacingOccurrences(
          of: "http://", with: "")
    title = address + (urls.count > 1 ? " +\(urls.count - 1)" : "")
    toolTip = urls.map(\.absoluteString).joined(separator: "\n")
    setAccessibilityLabel(
      urls.count == 1 ? "로컬 서버 \(first.absoluteString) 열기" : "로컬 서버 \(urls.count)개 보기")
  }

  func setCompact(_ value: Bool) {
    guard compact != value else { return }
    compact = value
    update(urls)
  }

  @objc private func openServer() {
    guard let first = urls.first else { return }
    if urls.count == 1 {
      openURL(first)
    } else {
      let menu = NSMenu()
      for url in urls {
        let item = menu.addItem(
          withTitle: url.absoluteString, action: #selector(openItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
      }
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }
  }

  @objc private func openItem(_ sender: NSMenuItem) {
    // A menu can remain open while the listener exits; do not open a removed endpoint.
    guard let url = sender.representedObject as? URL, urls.contains(url) else { return }
    openURL(url)
  }
}
