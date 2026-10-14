import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var workspaceWindow: WorkspaceWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
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
      workspaceWindow = WorkspaceWindowController()
    }
    workspaceWindow?.showWindow(nil)
    workspaceWindow?.window?.makeKeyAndOrderFront(nil)
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

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "윈도우")
    windowMenu.addItem(
      withTitle: "최소화",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(
      withTitle: "닫기",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)

    NSApp.mainMenu = mainMenu
    NSApp.windowsMenu = windowMenu
  }
}
