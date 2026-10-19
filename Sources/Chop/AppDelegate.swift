import AppKit
import ChopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
  private var workspaceWindow: WorkspaceWindowController?
  private let engine = TerminalEngine()
  private let session = SessionCoordinator(
    store: SessionStore(
      fileURL:
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chop/session.json")))
  private var initialSnapshot: WorkspaceSnapshot?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    let mode = AppearanceMode.load()
    NSApp.appearance = mode.appearance
    do {
      try engine.start(appearanceMode: mode)
    } catch {
      let alert = NSAlert()
      alert.messageText = error.localizedDescription
      alert.addButton(withTitle: "종료")
      alert.runModal()
      NSApp.terminate(nil)
      return
    }
    configureMainMenu()
    initialSnapshot = session.load()
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
      workspaceWindow = WorkspaceWindowController(engine: engine, snapshot: initialSnapshot)
      workspaceWindow?.workspace.onAppearanceChangeRequested = { [weak self] mode in
        self?.applyAppearance(mode)
      }
      initialSnapshot = nil
    }
    workspaceWindow?.showWindow(nil)
    workspaceWindow?.window?.makeKeyAndOrderFront(nil)
    if let workspace = workspaceWindow?.workspace {
      workspace.layoutSubtreeIfNeeded()
      workspace.startRestoredTerminals()
      session.attach(workspace)
      session.saveNow()
    }
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
    return session.confirmTerminationIfUnsaved() ? .terminateNow : .terminateCancel
  }

  func applicationWillTerminate(_ notification: Notification) {
    session.prepareToTerminate()
    workspaceWindow?.workspace.closeAll()
    engine.shutdown()
  }

  @objc private func openTerminal() { workspaceWindow?.workspace.addTerminal() }
  @objc private func closeTerminal() { workspaceWindow?.workspace.requestCloseFocused() }
  @objc private func splitRight() { workspaceWindow?.workspace.splitRight() }
  @objc private func splitDown() { workspaceWindow?.workspace.splitDown() }
  @objc private func toggleLayoutEditing() { workspaceWindow?.workspace.toggleEditing() }
  @objc private func focusLeft() { workspaceWindow?.workspace.moveFocus(.left) }
  @objc private func focusRight() { workspaceWindow?.workspace.moveFocus(.right) }
  @objc private func focusUp() { workspaceWindow?.workspace.moveFocus(.up) }
  @objc private func focusDown() { workspaceWindow?.workspace.moveFocus(.down) }
  @objc private func swapLeft() { workspaceWindow?.workspace.swapFocusedPane(.left) }
  @objc private func swapRight() { workspaceWindow?.workspace.swapFocusedPane(.right) }
  @objc private func swapUp() { workspaceWindow?.workspace.swapFocusedPane(.up) }
  @objc private func swapDown() { workspaceWindow?.workspace.swapFocusedPane(.down) }
  @objc private func toggleZoom() { workspaceWindow?.workspace.toggleZoom() }
  @objc private func renamePane() { workspaceWindow?.workspace.requestRename() }
  @objc private func retrySave() { session.retrySave() }
  @objc private func toggleFileTree() { workspaceWindow?.content.toggleFileTree() }
  @objc private func chooseFileTreeFolder() {
    workspaceWindow?.content.showFileTree()
    guard workspaceWindow?.content.isFileTreeVisible == true else { return }
    workspaceWindow?.content.fileBrowser.chooseFolder()
  }

  @objc private func chooseAppearance(_ sender: NSMenuItem) {
    guard let value = sender.representedObject as? String,
      let mode = AppearanceMode(rawValue: value)
    else { return }
    applyAppearance(mode)
  }

  private func applyAppearance(_ mode: AppearanceMode) {
    engine.applyAppearance(mode)
    NSApp.appearance = mode.appearance
    workspaceWindow?.workspace.applyAppearance(mode)
    mode.save()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(chooseAppearance(_:)) {
      menuItem.state =
        (menuItem.representedObject as? String) == engine.appearanceMode.rawValue ? .on : .off
      return true
    }
    guard let workspace = workspaceWindow?.workspace, workspaceWindow?.window?.isVisible == true
    else { return false }
    switch menuItem.action {
    case #selector(openTerminal): return workspace.canAddTerminal
    case #selector(toggleFileTree):
      menuItem.title =
        workspaceWindow?.content.isFileTreeVisible == true
        ? "파일 트리 숨기기" : "파일 트리 보기"
      return true
    case #selector(splitRight): return workspace.canSplit(workspace.focusedID, axis: .horizontal)
    case #selector(splitDown): return workspace.canSplit(workspace.focusedID, axis: .vertical)
    case #selector(toggleZoom): return workspace.focusedPane.canZoom
    case #selector(swapLeft): return workspace.canSwapFocusedPane(.left)
    case #selector(swapRight): return workspace.canSwapFocusedPane(.right)
    case #selector(swapUp): return workspace.canSwapFocusedPane(.up)
    case #selector(swapDown): return workspace.canSwapFocusedPane(.down)
    case #selector(closeTerminal):
      menuItem.title =
        workspace.isTabbed ? "탭 닫기" : workspace.focusedPane.isRunning ? "터미널 닫기" : "빈 칸 제거"
      return workspace.focusedPane.isRunning || workspace.layout.paneIDs.count > 1
    default: return true
    }
  }

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
      withTitle: "터미널 추가", action: #selector(openTerminal), keyEquivalent: "t")
    open.target = self
    let close = terminalMenu.addItem(
      withTitle: "터미널 닫기", action: #selector(closeTerminal), keyEquivalent: "w")
    close.target = self
    terminalMenu.addItem(.separator())
    for (title, action, key, modifiers) in [
      ("오른쪽으로 나누기", #selector(splitRight), "d", NSEvent.ModifierFlags.command),
      ("아래로 나누기", #selector(splitDown), "d", [.command, .shift]),
      ("레이아웃 편집", #selector(toggleLayoutEditing), "l", [.command, .shift]),
      ("칸 확대·복귀", #selector(toggleZoom), "\r", [.command, .shift]),
      ("칸 이름 바꾸기…", #selector(renamePane), "r", [.command, .shift]),
      ("레이아웃 다시 저장", #selector(retrySave), "", []),
      (
        "왼쪽 칸으로 이동", #selector(focusLeft), String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        [.command, .option]
      ),
      (
        "오른쪽 칸으로 이동", #selector(focusRight), String(UnicodeScalar(NSRightArrowFunctionKey)!),
        [.command, .option]
      ),
      (
        "위 칸으로 이동", #selector(focusUp), String(UnicodeScalar(NSUpArrowFunctionKey)!),
        [.command, .option]
      ),
      (
        "아래 칸으로 이동", #selector(focusDown), String(UnicodeScalar(NSDownArrowFunctionKey)!),
        [.command, .option]
      ),
      (
        "왼쪽 칸과 자리 바꾸기", #selector(swapLeft), String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        [.command, .option, .shift]
      ),
      (
        "오른쪽 칸과 자리 바꾸기", #selector(swapRight), String(UnicodeScalar(NSRightArrowFunctionKey)!),
        [.command, .option, .shift]
      ),
      (
        "위 칸과 자리 바꾸기", #selector(swapUp), String(UnicodeScalar(NSUpArrowFunctionKey)!),
        [.command, .option, .shift]
      ),
      (
        "아래 칸과 자리 바꾸기", #selector(swapDown), String(UnicodeScalar(NSDownArrowFunctionKey)!),
        [.command, .option, .shift]
      ),
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
    editMenu.addItem(.separator())
    for (title, action, key, modifiers) in [
      (
        "한 페이지 위로", #selector(TerminalView.scrollPageUp(_:)),
        String(UnicodeScalar(NSPageUpFunctionKey)!), NSEvent.ModifierFlags.shift
      ),
      (
        "한 페이지 아래로", #selector(TerminalView.scrollPageDown(_:)),
        String(UnicodeScalar(NSPageDownFunctionKey)!), .shift
      ),
      (
        "맨 위로 스크롤", #selector(TerminalView.scrollToTop(_:)),
        String(UnicodeScalar(NSUpArrowFunctionKey)!), .command
      ),
      (
        "맨 아래로 스크롤", #selector(TerminalView.scrollToBottom(_:)),
        String(UnicodeScalar(NSDownArrowFunctionKey)!), .command
      ),
    ] {
      let item = editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
    }
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    let viewItem = NSMenuItem()
    let viewMenu = NSMenu(title: "보기")
    for mode in AppearanceMode.allCases {
      let item = viewMenu.addItem(
        withTitle: mode.title, action: #selector(chooseAppearance(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = mode.rawValue
    }
    viewMenu.addItem(.separator())
    let fileTree = viewMenu.addItem(
      withTitle: "파일 트리 보기", action: #selector(toggleFileTree), keyEquivalent: "e")
    fileTree.keyEquivalentModifierMask = [.command, .shift]
    fileTree.target = self
    let folder = viewMenu.addItem(
      withTitle: "폴더 선택…", action: #selector(chooseFileTreeFolder), keyEquivalent: "o")
    folder.target = self
    viewItem.submenu = viewMenu
    mainMenu.addItem(viewItem)

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
