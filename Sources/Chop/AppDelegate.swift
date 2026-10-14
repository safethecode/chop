import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var workspaceWindow: WorkspaceWindowController?
  private let engine = TerminalEngine()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    do {
      try engine.start()
    } catch {
      let alert = NSAlert()
      alert.messageText = error.localizedDescription
      alert.addButton(withTitle: "종료")
      alert.runModal()
      NSApp.terminate(nil)
      return
    }
    configureMainMenu()
    showWorkspace()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showWorkspace()
    }
    return true
  }

  private func showWorkspace() {
    if workspaceWindow == nil {
      workspaceWindow = WorkspaceWindowController(engine: engine)
    }
    workspaceWindow?.showWindow(nil)
    workspaceWindow?.window?.makeKeyAndOrderFront(nil)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if workspaceWindow?.workspace.needsConfirmClose == true {
      let alert = NSAlert()
      alert.messageText = "Chop을 종료할까요?"
      alert.informativeText = "실행 중인 터미널 작업이 종료됩니다."
      alert.addButton(withTitle: "취소")
      alert.addButton(withTitle: "종료")
      if alert.runModal() != .alertSecondButtonReturn { return .terminateCancel }
    }
    return .terminateNow
  }

  func applicationWillTerminate(_ notification: Notification) {
    workspaceWindow?.workspace.closeAll()
    engine.shutdown()
  }

  @objc private func openTerminal() { workspaceWindow?.pane.openTerminal() }
  @objc private func closeTerminal() { workspaceWindow?.pane.requestClose() }
  @objc private func splitRight() { workspaceWindow?.workspace.splitRight() }
  @objc private func splitDown() { workspaceWindow?.workspace.splitDown() }
  @objc private func toggleLayoutEditing() { workspaceWindow?.workspace.toggleEditing() }

  private func configureMainMenu() {
    let mainMenu = NSMenu()

    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "Chop")
    applicationMenu.addItem(
      withTitle: "Chop에 관하여",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      withTitle: "Chop 가리기",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    applicationMenu.addItem(.separator())
    applicationMenu.addItem(
      withTitle: "Chop 종료",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)

    let terminalItem = NSMenuItem()
    let terminalMenu = NSMenu(title: "터미널")
    let open = terminalMenu.addItem(
      withTitle: "터미널 열기", action: #selector(openTerminal), keyEquivalent: "t")
    open.target = self
    let close = terminalMenu.addItem(
      withTitle: "터미널 닫기", action: #selector(closeTerminal), keyEquivalent: "w")
    close.target = self
    terminalMenu.addItem(.separator())
    for (title, action, key, modifiers) in [
      ("오른쪽으로 나누기", #selector(splitRight), "d", NSEvent.ModifierFlags.command),
      ("아래로 나누기", #selector(splitDown), "d", [.command, .shift]),
      ("레이아웃 편집", #selector(toggleLayoutEditing), "l", [.command, .shift]),
    ] {
      let item = terminalMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
      item.target = self
      item.keyEquivalentModifierMask = modifiers
    }
    terminalItem.submenu = terminalMenu
    mainMenu.addItem(terminalItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "편집")
    editMenu.addItem(withTitle: "복사", action: #selector(TerminalView.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(
      withTitle: "붙여넣기", action: #selector(TerminalView.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "전체 선택", action: #selector(TerminalView.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "윈도우")
    windowMenu.addItem(
      withTitle: "최소화",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    let closeWindow = windowMenu.addItem(
      withTitle: "닫기",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    closeWindow.keyEquivalentModifierMask = [.command, .shift]
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
  }
}
