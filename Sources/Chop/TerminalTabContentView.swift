import AppKit

/// Reused split panes must fill their new viewport before focus can scroll them.
@MainActor
final class TerminalTabContentView: NSView {
  private let tabBar: TerminalTabBar
  private let pane: TerminalPaneView

  override var isFlipped: Bool { true }

  init(tabBar: TerminalTabBar, pane: TerminalPaneView) {
    self.tabBar = tabBar
    self.pane = pane
    super.init(frame: .zero)
    for child in [tabBar, pane] {
      child.translatesAutoresizingMaskIntoConstraints = true
      addSubview(child)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(tabBar:pane:).") }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    let height = min(ChopStyle.headerHeight, bounds.height)
    tabBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
    pane.frame = NSRect(
      x: 0, y: height, width: bounds.width, height: max(0, bounds.height - height))
  }
}
