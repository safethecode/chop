import AppKit
import ChopCore

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
  let workspace: WorkspaceView
  var pane: TerminalPaneView { workspace.focusedPane }

  init(engine: TerminalEngine, snapshot: WorkspaceSnapshot? = nil) {
    workspace = WorkspaceView(engine: engine, snapshot: snapshot)
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

    window.contentView = workspace

    super.init(window: window)
    window.delegate = self
    workspace.onMinimumSizeChange = { [weak window] size in
      guard let window else { return }
      let minimum = NSSize(width: max(640, size.width), height: max(400, size.height + 48))
      window.contentMinSize = minimum
      let current = window.contentLayoutRect.size
      if current.width < minimum.width || current.height < minimum.height {
        window.setContentSize(
          NSSize(
            width: max(current.width, minimum.width), height: max(current.height, minimum.height)))
      }
    }
    workspace.refreshMinimumSize()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if workspace.needsConfirmClose {
      let alert = NSAlert()
      alert.messageText = "윈도우를 닫을까요?"
      alert.informativeText = "이 윈도우에서 실행 중인 작업이 종료됩니다."
      alert.addButton(withTitle: "취소")
      alert.addButton(withTitle: "윈도우 닫기")
      guard alert.runModal() == .alertSecondButtonReturn else { return false }
    }
    workspace.closeAll()
    return true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Use init() to create the workspace window.")
  }
}
