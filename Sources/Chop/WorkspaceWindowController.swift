import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController {
  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Chop"
    window.minSize = NSSize(width: 640, height: 400)
    window.isReleasedWhenClosed = false
    window.setFrameAutosaveName("ChopWorkspaceWindow")
    window.center()

    let content = NSView()
    content.wantsLayer = true
    content.layer?.backgroundColor = NSColor.white.cgColor
    window.contentView = content

    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Use init() to create the workspace window.")
  }
}
