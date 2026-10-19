import AppKit
import ChopCore
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
  #expect(abs(second.bounds.width - (workspace.bounds.width - TerminalAreaView.railWidth)) < 0.5)
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

@MainActor
@Test func terminalAddRailStaysVisibleBesideTheViewportAtMinimumSizes() throws {
  _ = NSApplication.shared
  let suite = "chop-add-rail-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(FileManager.default.temporaryDirectory.path, forKey: "fileTreeRootPath")
  let workspace = WorkspaceView(engine: TerminalEngine())
  let split = workspace.installFileBrowser(defaults: defaults)
  // Exercise geometry without a physical display. Attaching to a runner's small
  // screen can turn a panel toggle into an interactive "not enough space" alert.
  workspace.setFrameSize(NSSize(width: 1100, height: 720))
  func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }
  let area = try #require(descendants(workspace).compactMap { $0 as? TerminalAreaView }.first)
  for visible in [true, false, true] {
    if split.isFileTreeVisible != visible { split.toggleFileTree() }
    for mode in AppearanceMode.allCases {
      workspace.applyAppearance(mode)
      for preset in LayoutPreset.allCases {
        workspace.applyPreset(preset)
        workspace.setFrameSize(split.minimumContentSize)
        workspace.layoutSubtreeIfNeeded()
        let button = area.addButton
        let rect = area.convert(button.bounds, from: button)
        #expect(area.bounds.contains(rect))
        #expect(rect.size == NSSize(width: 32, height: 32))
        #expect(abs(rect.midX - (area.bounds.maxX - TerminalAreaView.railWidth / 2)) < 0.5)
        #expect(abs(rect.midY - area.bounds.midY) < 0.5)
        let point = button.convert(NSPoint(x: 16, y: 16), to: workspace.superview)
        #expect(workspace.hitTest(point) === button)
      }
    }
  }
}
