import AppKit

/// The add control stays beside the viewport, including when the canvas scrolls or the tree is hidden.
@MainActor
final class TerminalAreaView: NSView {
  static let railWidth: CGFloat = 48
  private let canvas: NSView
  private let rail = NSView()
  private let leadingBorder = NSView()
  private let trailingBorder = NSView()
  let addButton: NSButton
  let cloneButton: NSButton
  let webButton: NSButton
  var onWebRequested: (() -> Void)?
  var onCloneRequested: (() -> Void)?

  init(canvas: NSView, target: AnyObject, action: Selector) {
    self.canvas = canvas
    addButton = NSButton(
      image: NSImage(systemSymbolName: "plus", accessibilityDescription: "터미널 추가")!,
      target: target, action: action)
    cloneButton = NSButton(
      image: NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)!,
      target: nil, action: nil)
    webButton = NSButton(
      image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!, target: nil,
      action: nil)
    super.init(frame: .zero)
    rail.wantsLayer = true
    addButton.bezelStyle = .circular
    addButton.controlSize = .regular
    addButton.setAccessibilityLabel("터미널 추가")
    addButton.toolTip = "터미널 추가 (⌘T)"
    addSubview(canvas)
    addSubview(rail)
    for border in [leadingBorder, trailingBorder] {
      border.wantsLayer = true
      rail.addSubview(border)
    }
    rail.addSubview(addButton)
    cloneButton.bezelStyle = .circular
    cloneButton.controlSize = .regular
    cloneButton.target = self
    cloneButton.action = #selector(requestClone)
    cloneButton.toolTip = "GitHub 프로젝트 클론…"
    cloneButton.setAccessibilityLabel("GitHub 프로젝트 클론")
    rail.addSubview(cloneButton)
    webButton.bezelStyle = .circular
    webButton.controlSize = .regular
    webButton.target = self
    webButton.action = #selector(requestWeb)
    webButton.toolTip = "새 칸에서 웹사이트 열기 (⌘⇧B)"
    webButton.setAccessibilityLabel("웹사이트 추가")
    rail.addSubview(webButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(canvas:target:action:).") }

  func applyAppearance(_ mode: AppearanceMode) {
    rail.layer?.backgroundColor = mode.fileListBackground.cgColor
    for border in [leadingBorder, trailingBorder] {
      border.layer?.backgroundColor = mode.terminalRailBorder.cgColor
    }
  }

  func setFileTreeVisible(_ visible: Bool) {
    // The file tree already owns the adjacent resize divider. Draw only one edge there.
    trailingBorder.isHidden = visible
  }

  @objc private func requestClone() { onCloneRequested?() }
  @objc private func requestWeb() { onWebRequested?() }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    let width = min(Self.railWidth, bounds.width)
    canvas.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - width), height: bounds.height)
    rail.frame = NSRect(x: canvas.frame.maxX, y: 0, width: width, height: bounds.height)
    let borderWidth = min(1, width)
    leadingBorder.frame = NSRect(x: 0, y: 0, width: borderWidth, height: bounds.height)
    trailingBorder.frame = NSRect(
      x: width - borderWidth, y: 0, width: borderWidth, height: bounds.height)
    addButton.frame = NSRect(
      x: (width - 32) / 2, y: (bounds.height - 32) / 2, width: 32, height: 32)
    cloneButton.frame = NSRect(x: (width - 32) / 2, y: 12, width: 32, height: 32)
    webButton.frame = NSRect(x: (width - 32) / 2, y: 52, width: 32, height: 32)
  }
}
