import AppKit

@MainActor
enum ChopStyle {
  static let background = NSColor.white
  static let foreground = NSColor(srgbRed: 36 / 255, green: 38 / 255, blue: 43 / 255, alpha: 1)
  static let font = NSFont.systemFont(ofSize: 14, weight: .medium)
  static let headerHeight: CGFloat = 40
  static let inset: CGFloat = 12

  static func iconButton(_ symbol: String, label: String, target: AnyObject?, action: Selector)
    -> NSButton
  {
    let button = NSButton(
      image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: target,
      action: action)
    button.bezelStyle = .inline
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 28),
      button.heightAnchor.constraint(equalToConstant: 28),
    ])
    button.toolTip = label
    button.setAccessibilityLabel(label)
    return button
  }
}
