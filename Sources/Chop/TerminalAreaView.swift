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

  init(canvas: NSView, target: AnyObject, action: Selector) {
    self.canvas = canvas
    addButton = NSButton(
      image: NSImage(systemSymbolName: "plus", accessibilityDescription: "터미널 추가")!,
      target: target, action: action)
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
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(canvas:target:action:).") }

  func applyAppearance(_ mode: AppearanceMode) {
    rail.layer?.backgroundColor = mode.fileListBackground.cgColor
    for border in [leadingBorder, trailingBorder] {
      border.layer?.backgroundColor = mode.terminalRailBorder.cgColor
    }
  }

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
  }
}
