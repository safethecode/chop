import AppKit
import Testing

@testable import Chop

@MainActor
@Test func outputSearchFindsScrollbackAndKeepsTheLiveShell() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let engine = TerminalEngine(command: "/bin/sh")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let pane = TerminalPaneView(engine: engine)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = pane
  window.makeKeyAndOrderFront(nil)
  pane.layoutSubtreeIfNeeded()
  defer {
    pane.closeTerminal()
    window.orderOut(nil)
    engine.shutdown()
  }
  func waitFor(_ phase: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition(), "\(phase): \(pane.terminal?.outputSnapshot()?.suffix(1000) ?? "")")
  }
  func send(_ text: String, to terminal: TerminalView) throws {
    terminal.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    terminal.keyDown(
      with: try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: "\r",
          charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
  }
  pane.openTerminal()
  let terminal = try #require(pane.terminal)
  try await waitFor("shell prompt") {
    terminal.childPID > 0
      && !(terminal.outputSnapshot()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ?? true)
  }
  try send(
    "i=1; while [ $i -le 120 ]; do printf 'SCROLL_%03d\\n' $i; i=$((i+1)); done", to: terminal)
  try await waitFor("scrollback output") {
    terminal.outputSnapshot()?.contains("SCROLL_120") == true
  }
  let pid = terminal.childPID
  let surface = terminal.surface
  pane.showSearch()
  let search = try #require(pane.searchView)
  #expect(search.output.string.contains("SCROLL_001"))
  #expect(!search.output.isEditable && search.output.isSelectable)
  search.searchField.stringValue = "SCROLL_00"
  search.search()
  try await waitFor("first search") { search.matches.count == 9 }
  #expect(search.selectedMatch == 0)
  window.setContentSize(NSSize(width: 280, height: 180))
  pane.layoutSubtreeIfNeeded()
  #expect(search.searchField.frame.width > 0)
  #expect(
    search.searchField.convert(search.searchField.bounds, to: search).maxX <= search.bounds.width)
  search.selectMatch(by: -1)
  #expect(search.selectedMatch == 8)
  search.selectMatch(by: 1)
  #expect(search.selectedMatch == 0)
  engine.applyAppearance(.dark)
  pane.applyAppearance()
  #expect(search.matches.count == 9)
  search.searchField.stringValue = "absent"
  search.search()
  search.searchField.stringValue = "SCROLL_120"
  search.search()
  try await waitFor("replaced query") { search.matches.count == 1 }
  #expect((search.output.string as NSString).substring(with: search.matches[0]) == "SCROLL_120")
  try send("printf 'STILL_%s\\n' RUNNING", to: terminal)
  try await waitFor("live shell output") {
    terminal.outputSnapshot()?.contains("STILL_RUNNING") == true
  }
  #expect(!search.output.string.contains("STILL_RUNNING"))
  #expect(terminal.surface == surface && terminal.childPID == pid)
  func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }
  let refresh = try #require(
    descendants(search).compactMap { $0 as? NSButton }.first {
      $0.accessibilityLabel() == "최신 출력 불러오기"
    })
  refresh.performClick(nil)
  #expect(search.output.string.contains("STILL_RUNNING"))
  let editor = try #require(search.searchField.currentEditor() as? NSTextView)
  #expect(
    search.control(
      search.searchField, textView: editor,
      doCommandBy: #selector(NSResponder.cancelOperation(_:))))
  #expect(pane.searchView == nil && window.firstResponder === terminal)
  #expect(terminal.surface == surface && terminal.childPID == pid)
  pane.showSearch()
  let reopened = try #require(pane.searchView)
  window.makeFirstResponder(reopened.output)
  reopened.output.cancelOperation(nil)
  #expect(pane.searchView == nil && window.firstResponder === terminal)
}
