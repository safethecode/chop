import AppKit
import Testing

@testable import Chop

@MainActor
@Test func emptyTabbedPaneFillsTheViewportAndKeepsItsAddButtonCentered() throws {
  _ = NSApplication.shared
  let suite = "chop-geometry-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(false, forKey: "fileTreeVisible")
  defaults.set(FileManager.default.temporaryDirectory.path, forKey: "fileTreeRootPath")
  let workspace = WorkspaceView(engine: TerminalEngine())
  _ = workspace.installFileBrowser(defaults: defaults)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.contentView = workspace
  defer { window.orderOut(nil) }
  window.layoutIfNeeded()
  workspace.layoutSubtreeIfNeeded()
  let centerTolerance = 0.5 / window.backingScaleFactor + 0.001
  let second = try #require(workspace.panes[workspace.layout.paneIDs[1]])
  second.focus()
  #expect(workspace.applyPreset(.single))
  #expect(abs(second.bounds.width - workspace.bounds.width) < 0.5)
  #expect(abs(second.bounds.height - (workspace.bounds.height - 88)) < 0.5)
  for size in [NSSize(width: 917, height: 756), NSSize(width: 640, height: 400)] {
    #expect(workspace.applyPreset(.grid))
    second.focus()
    #expect(workspace.applyPreset(.single))
    window.setContentSize(size)
    workspace.selectTab(workspace.layout.paneIDs[2])
    workspace.selectTab(second.id)
    var parent: NSView? = second.superview
    while parent != nil && !(parent is TerminalCanvasScrollView) { parent = parent?.superview }
    let scroll = try #require(parent as? TerminalCanvasScrollView)
    let body = try #require(second.subviews.last)
    let add = try #require(body.subviews.compactMap { $0 as? NSButton }.first)
    let center = second.convert(NSPoint(x: add.frame.midX, y: add.frame.midY), from: body)
    #expect(abs(second.bounds.width - scroll.contentView.bounds.width) < 0.5)
    #expect(abs(second.bounds.height - (scroll.contentView.bounds.height - 40)) < 0.5)
    let visibleCenter = scroll.contentView.convert(center, from: second)
    #expect(abs(visibleCenter.x - scroll.contentView.bounds.midX) <= centerTolerance)
    #expect(abs(visibleCenter.y - (scroll.contentView.bounds.midY + 20)) <= centerTolerance)
    #expect(abs(center.x - second.bounds.midX) <= centerTolerance)
    #expect(abs(center.y - second.bounds.midY) <= centerTolerance)
  }
}
