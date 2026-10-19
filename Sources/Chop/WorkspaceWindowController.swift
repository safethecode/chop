import AppKit
import ChopCore

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
  let id: UUID
  let projectDirectory: String
  let workspace: WorkspaceView
  let content: WorkspaceSplitView
  var pane: TerminalPaneView { workspace.focusedPane }
  var onClose: (() -> Void)?
  var onActivate: (() -> Void)?

  init(
    engine: TerminalEngine, id: UUID = UUID(), snapshot: WorkspaceSnapshot? = nil,
    projectDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
    defaults: UserDefaults = .standard
  ) {
    self.id = id
    self.projectDirectory = projectDirectory
    workspace = WorkspaceView(
      engine: engine, snapshot: snapshot, initialDirectory: projectDirectory)
    content = workspace.installFileBrowser(defaults: defaults)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "\((projectDirectory as NSString).lastPathComponent) — Chop"
    window.minSize = NSSize(width: 640, height: 400)
    window.isReleasedWhenClosed = false
    window.center()

    window.contentView = workspace

    super.init(window: window)
    // The controller applies its own autosave name when it takes ownership of the window.
    windowFrameAutosaveName = "ChopWorkspaceWindow-\(id.uuidString)"
    window.delegate = self
    content.onMinimumSizeChange = { [weak window] minimum in
      guard let window else { return }
      window.contentMinSize = minimum
      let current = window.contentLayoutRect.size
      if current.width < minimum.width || current.height < minimum.height {
        window.setContentSize(
          NSSize(
            width: max(current.width, minimum.width), height: max(current.height, minimum.height)))
      }
    }
    content.refreshMinimumSize()
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

  func windowWillClose(_ notification: Notification) { onClose?() }
  func windowDidBecomeKey(_ notification: Notification) { onActivate?() }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Use init() to create the workspace window.")
  }
}
