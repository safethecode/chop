import AppKit

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
  let pane: TerminalPaneView

  init(engine: TerminalEngine) {
    pane = TerminalPaneView(engine: engine)
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

    window.contentView = pane

    super.init(window: window)
    window.delegate = self
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if pane.needsConfirmClose {
      let alert = NSAlert()
      alert.messageText = "윈도우를 닫을까요?"
      alert.informativeText = "이 윈도우에서 실행 중인 작업이 종료됩니다."
      alert.addButton(withTitle: "취소")
      alert.addButton(withTitle: "윈도우 닫기")
      guard alert.runModal() == .alertSecondButtonReturn else { return false }
    }
    pane.closeTerminal()
    return true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Use init() to create the workspace window.")
  }
}
