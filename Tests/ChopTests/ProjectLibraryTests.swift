import AppKit
import ChopCore
import Testing

@testable import Chop

@MainActor
@Test func savedProjectConfigurationOpensANewWindowAndPreservesTheExistingShell() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let project = directory.appendingPathComponent("프로젝트 알파")
  let child = project.appendingPathComponent("소스")
  let other = directory.appendingPathComponent("프로젝트 베타")
  try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let engine = TerminalEngine(command: "/bin/sh")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let suite = "com.safethecode.chop.project-test.\(UUID())."
  var ids: [UUID] = []
  let manager = WorkspaceWindowManager(
    engine: engine, clearDefaultsForWindow: { _ in },
    defaultsForWindow: { id in
      ids.append(id)
      return UserDefaults(suiteName: suite + id.uuidString)!
    })
  defer {
    manager.shutdown()
    engine.shutdown()
    for id in ids {
      UserDefaults.standard.removePersistentDomain(forName: suite + id.uuidString)
      NSWindow.removeFrame(usingName: "ChopWorkspaceWindow-\(id.uuidString)")
    }
  }
  func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition())
  }
  func send(_ text: String, to terminal: TerminalView, window: NSWindow) throws {
    terminal.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    terminal.keyDown(with: event)
  }
  let store = ProjectLibraryStore(fileURL: directory.appendingPathComponent("projects.json"))
  let menus = ProjectLibraryController(manager: manager, store: store)
  menus.load(reportFailure: false)
  let first = manager.open(directory: project.path)
  let terminalID = first.workspace.focusedID
  let terminal = try #require(first.pane.terminal)
  try send(
    "export CONFIG_VALUE=kept; printf 'CONFIG_READY\\n'", to: terminal,
    window: #require(first.window))
  try await waitFor {
    (terminal.accessibilityValue() as? String ?? "").components(separatedBy: "\n")
      .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "CONFIG_READY" }
  }
  #expect(first.workspace.renameFocused(to: "원래 셸"))
  first.workspace.openWebPreview(URL(string: "http://127.0.0.1:9/preview"))
  first.workspace.applyPreset(.single)
  first.content.fileBrowser.navigate(to: child)
  try await waitFor { !first.content.fileBrowser.isLoading }
  first.content.toggleFileTree()
  let snapshot = first.workspace.snapshot()
  try store.update {
    try $0.saveConfiguration(
      name: "개발 환경", projectDirectory: project.path, workspace: snapshot,
      fileBrowser: first.content.projectSettings)
  }
  menus.load(reportFailure: false)
  let entry = try #require(menus.library.configurations.first)
  menus.menuNeedsUpdate(menus.configurationMenu)
  let item = try #require(
    menus.configurationMenu.items.first { ($0.representedObject as? String) == entry.id.uuidString }
  )
  #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
  let restored = try #require(manager.active)
  #expect(restored.id != first.id && manager.windows.count == 2)
  #expect(restored.workspace.layout == snapshot.layout && restored.workspace.isTabbed)
  #expect(restored.content.fileBrowser.rootURL.path == child.path)
  #expect(!restored.content.isFileTreeVisible)
  #expect(restored.workspace.panes[terminalID]?.name == "원래 셸")
  #expect(
    restored.workspace.panes.values.contains {
      $0.browser?.url?.absoluteString == "http://127.0.0.1:9/preview"
    })
  let restoredTerminal = try #require(restored.workspace.panes[terminalID]?.terminal)
  #expect(restoredTerminal !== terminal && first.workspace.panes[terminalID]?.terminal === terminal)
  restored.workspace.selectTab(terminalID)
  try send("pwd", to: restoredTerminal, window: #require(restored.window))
  try await waitFor {
    (restoredTerminal.accessibilityValue() as? String ?? "").contains(project.path)
  }
  manager.activate(first.id)
  first.workspace.selectTab(terminalID)
  try send(
    "printf 'PRESERVED=%s\\n' \"$CONFIG_VALUE\"", to: terminal, window: #require(first.window))
  try await waitFor { (terminal.accessibilityValue() as? String ?? "").contains("PRESERVED=kept") }
  let beta = manager.open(directory: other.path)
  menus.menuNeedsUpdate(menus.configurationMenu)
  #expect(menus.configurationMenu.items.allSatisfy { $0.representedObject == nil })
  #expect(try store.load().recentProjects.first == other.path)
  beta.workspace.closeAll()
  beta.window?.close()
  menus.menuNeedsUpdate(menus.configurationMenu)
  #expect(
    menus.configurationMenu.items.contains {
      ($0.representedObject as? String) == entry.id.uuidString
    })
  #expect(try store.load().configurations.count == 1)
}
