import AppKit
import Testing

@testable import Chop

@MainActor
@Test func renamedSelectedTabStaysVisibleWhenItsTitleGrows() throws {
  _ = NSApplication.shared
  let engine = TerminalEngine()
  for mode in [AppearanceMode.light, .dark] {
    for style in [NSScroller.Style.overlay, .legacy] {
      let panes = (1...4).map { TerminalPaneView(engine: engine, name: "터미널 \($0)") }
      let selected = try #require(panes.last)
      let bar = TerminalTabBar(
        panes: panes, selectedID: selected.id, mode: mode,
        onSelect: { _ in }, onAdd: {}, onClose: {}, onRename: { _ in })
      bar.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
      let scroll = try #require(bar.subviews.compactMap { $0 as? NSScrollView }.first)
      scroll.scrollerStyle = style
      bar.layoutSubtreeIfNeeded()
      bar.revealSelection(selected.id)
      for name in [
        String(repeating: "아주 긴 터미널 이름 ", count: 4), "빌드", String(repeating: "W", count: 64),
      ] {
        selected.name = name
        bar.update(panes: panes, selectedID: selected.id)
        bar.layoutSubtreeIfNeeded()
        let tabs = try #require(scroll.documentView as? NSStackView)
        let button = try #require(tabs.arrangedSubviews.compactMap { $0 as? NSButton }.last)
        #expect(button.title == selected.name && button.state == .on)
        #expect(button.frame.minX >= scroll.contentView.bounds.minX - 0.5)
        #expect(button.frame.maxX <= scroll.contentView.bounds.maxX + 0.5)
      }
    }
  }
}
