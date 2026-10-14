import AppKit
import ChopCore
import GhosttyKit
import Testing

@testable import Chop

@MainActor
@Test func realShellExecutesCommandAndReturnsToEmptyPane() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let resources = root.appendingPathComponent("build/release/Chop.app/Contents/Resources")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let clipboard = NSPasteboard.withUniqueName()
  let engine = TerminalEngine(clipboard: clipboard, command: "/bin/zsh -l")
  try engine.start(resources: resources)
  let pane = TerminalPaneView(engine: engine, workingDirectory: directory.path)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = pane
  window.orderFront(nil)
  pane.layoutSubtreeIfNeeded()
  defer {
    pane.closeTerminal()
    window.orderOut(nil)
    engine.shutdown()
  }

  pane.openTerminal()
  let terminal = try #require(pane.terminal)
  pane.openTerminal()
  #expect(pane.terminal === terminal, "Repeated open must not launch a second shell")
  do {
    try await waitFor { !terminal.needsConfirmClose }
  } catch {
    Issue.record("Initial screen: \(terminal.accessibilityValue() as? String ?? "")")
    throw error
  }
  terminal.insertText(
    "printf 'CHOP_SHELL_OK\\n'; pwd", replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: terminal, window: window)
  do {
    try await waitFor {
      let output = terminal.accessibilityValue() as? String ?? ""
      return output.components(separatedBy: "CHOP_SHELL_OK").count >= 3
        && output.contains(directory.lastPathComponent)
    }
  } catch {
    Issue.record("Screen at timeout: \(terminal.accessibilityValue() as? String ?? "")")
    throw error
  }
  // Verify command output, not only the terminal's echo of the input line.
  let output = terminal.accessibilityValue() as? String ?? ""
  #expect(output.components(separatedBy: "CHOP_SHELL_OK").count >= 3)
  try await waitFor { !terminal.needsConfirmClose }
  terminal.selectAll(nil)
  terminal.copy(nil)
  #expect(clipboard.string(forType: .string)?.contains("CHOP_SHELL_OK") == true)
  clipboard.clearContents()
  clipboard.setString("printf 'CHOP_PASTE_OK\\n'", forType: .string)
  terminal.paste(nil)
  try pressReturn(on: terminal, window: window)
  try await waitFor {
    let pasted = terminal.accessibilityValue() as? String ?? ""
    return pasted.components(separatedBy: "CHOP_PASTE_OK").count >= 3
      && !terminal.needsConfirmClose
  }
  terminal.insertText("printf 'CHOP_", replacementRange: NSRange(location: NSNotFound, length: 0))
  terminal.setMarkedText(
    "한글", selectedRange: NSRange(location: 2, length: 0),
    replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(terminal.hasMarkedText())
  #expect(terminal.markedRange().length == 2)
  terminal.insertText("한글", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(!terminal.hasMarkedText())
  terminal.insertText("_IME_OK\\n'", replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: terminal, window: window)
  try await waitFor {
    let text = terminal.accessibilityValue() as? String ?? ""
    return text.components(separatedBy: "\n").contains {
      $0.trimmingCharacters(in: .whitespacesAndNewlines) == "CHOP_한글_IME_OK"
    } && !terminal.needsConfirmClose
  }
  terminal.insertText(
    "for i in {1..120}; do printf 'SCROLL_%03d\\n' \"$i\"; done",
    replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: terminal, window: window)
  try await waitFor { viewport(of: terminal).contains("SCROLL_120") && !terminal.needsConfirmClose }
  let bottom = viewport(of: terminal)
  terminal.scrollToTop(nil)
  try await waitFor { viewport(of: terminal).contains("CHOP_SHELL_OK") }
  let top = viewport(of: terminal)
  #expect(!top.contains("SCROLL_120"))
  terminal.scrollPageDown(nil)
  try await waitFor { viewport(of: terminal) != top }
  terminal.scrollPageUp(nil)
  try await waitFor { viewport(of: terminal) == top }
  terminal.scrollToBottom(nil)
  try await waitFor { viewport(of: terminal) == bottom }
  terminal.insertText("exit", replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: terminal, window: window)
  do {
    try await waitFor { pane.terminal == nil }
  } catch {
    Issue.record("Screen after exit: \(terminal.accessibilityValue() as? String ?? "")")
    if let surface = terminal.surface {
      Issue.record(
        "Ghostty process exited: \(ghostty_surface_process_exited(surface)); busy: \(terminal.needsConfirmClose)"
      )
    }
    throw error
  }
  #expect(!pane.isRunning)
  pane.openTerminal()
  #expect(pane.terminal != nil)
  #expect(pane.terminal !== terminal)
  pane.closeTerminal()

  let workspace = WorkspaceView(engine: engine)
  window.setContentSize(NSSize(width: 1100, height: 720))
  window.contentView = workspace
  window.layoutIfNeeded()
  defer { workspace.closeAll() }
  #expect(workspace.layout.paneIDs.count == 4)
  #expect(
    workspace.layout.paneIDs.compactMap { workspace.panes[$0]?.name } == [
      "터미널 1", "터미널 2", "터미널 3", "터미널 4",
    ])
  workspace.startRestoredTerminals()
  #expect(workspace.panes.values.filter { $0.isRunning }.count == 1)
  #expect(workspace.layout.paneIDs.dropFirst().allSatisfy { workspace.panes[$0]?.terminal == nil })
  let firstID = workspace.focusedID
  let first = try #require(workspace.focusedPane.terminal)
  workspace.startRestoredTerminals()
  #expect(
    workspace.focusedPane.terminal === first,
    "Reopening the workspace must not duplicate the default shell")
  try await waitFor { !first.needsConfirmClose }
  first.insertText(
    "export CHOP_PANE_VALUE=preserved", replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: first, window: window)
  try await waitFor { !first.needsConfirmClose }
  #expect(workspace.applyPreset(.grid))
  #expect(workspace.panes[firstID]?.terminal === first)
  for (index, id) in workspace.layout.paneIDs.enumerated() where id != firstID {
    workspace.panes[id]?.openTerminal()
    #expect(workspace.panes.values.filter { $0.isRunning }.count == index + 1)
  }
  try await waitFor { !workspace.needsConfirmClose }
  #expect(workspace.panes.values.filter { $0.isRunning }.count == 4)
  let tabIDs = workspace.layout.paneIDs
  let tabSurfaces = tabIDs.map { workspace.panes[$0]?.terminal?.surface }
  #expect(workspace.applyPreset(.single), "All running terminals remain reachable as tabs")
  #expect(workspace.isTabbed && workspace.layout.paneIDs == tabIDs)
  #expect(workspace.panes.count == 4)
  for (index, id) in tabIDs.enumerated() {
    workspace.selectTab(id)
    #expect(workspace.focusedID == id)
    #expect(window.firstResponder === workspace.panes[id]?.terminal)
    #expect(workspace.panes[id]?.terminal?.surface == tabSurfaces[index])
    #expect(workspace.panes[id]?.showsHeader == false)
    #expect(workspace.panes[id]?.superview != nil)
    #expect(tabIDs.filter { workspace.panes[$0]?.superview != nil } == [id])
  }
  let tabbedSnapshot = workspace.snapshot()
  let tabbedRestore = WorkspaceView(engine: engine, snapshot: tabbedSnapshot)
  #expect(tabbedRestore.isTabbed && tabbedRestore.focusedID == workspace.focusedID)
  #expect(tabbedRestore.layout == workspace.layout)
  window.contentView = tabbedRestore
  window.layoutIfNeeded()
  tabbedRestore.startRestoredTerminals()
  #expect(tabbedRestore.panes.values.filter { $0.isRunning }.count == 4)
  #expect(tabbedRestore.focusedID == tabbedSnapshot.focusedID)
  #expect(window.firstResponder === tabbedRestore.focusedPane.terminal)
  for id in tabIDs {
    tabbedRestore.selectTab(id)
    #expect(tabbedRestore.panes[id]?.terminal?.window === window)
  }
  tabbedRestore.closeAll()
  window.contentView = workspace
  window.layoutIfNeeded()
  workspace.addTab()
  let addedTabID = workspace.focusedID
  #expect(!tabIDs.contains(addedTabID) && workspace.panes.count == 5)
  #expect(workspace.focusedPane.isRunning)
  try await waitFor { !workspace.focusedPane.needsConfirmClose }
  let addedTerminal = try #require(workspace.focusedPane.terminal)
  #expect(workspace.applyPreset(.columns))
  try await Task.sleep(for: .milliseconds(50))
  window.layoutIfNeeded()
  #expect(workspace.layout.paneIDs.count == 5 && workspace.focusedID == addedTabID)
  #expect(workspace.focusedPane.terminal === addedTerminal)
  let columnFrame = workspace.focusedPane.convert(workspace.focusedPane.bounds, to: workspace)
  #expect(columnFrame.minX >= -1 && columnFrame.maxX <= workspace.bounds.width + 1)
  workspace.toggleZoom()
  window.layoutIfNeeded()
  #expect(workspace.focusedPane.bounds.width <= workspace.bounds.width + 1)
  #expect(workspace.focusedPane.terminal === addedTerminal)
  workspace.toggleZoom()
  #expect(workspace.applyPreset(.grid))
  #expect(workspace.layout.paneIDs.count == 5 && workspace.focusedPane.terminal === addedTerminal)
  #expect(workspace.applyPreset(.single))
  try await Task.sleep(for: .milliseconds(50))
  window.layoutIfNeeded()
  workspace.requestCloseFocused()
  #expect(workspace.layout.paneIDs == tabIDs && workspace.panes[addedTabID] == nil)
  #expect(
    tabIDs.enumerated().allSatisfy {
      workspace.panes[$0.element]?.terminal?.surface == tabSurfaces[$0.offset]
    })
  #expect(workspace.applyPreset(.grid))
  #expect(!workspace.isTabbed && workspace.layout.paneIDs == tabIDs)
  #expect(tabIDs.allSatisfy { workspace.panes[$0]?.showsHeader == true })
  #expect(workspace.applyPreset(.columns), "Every running terminal must fit the columns mode")
  #expect(workspace.layout.paneIDs == tabIDs && workspace.panes.count == 4)
  for id in tabIDs {
    workspace.panes[id]?.focus()
    let frame = try #require(
      workspace.panes[id]?.convert(workspace.panes[id]!.bounds, to: workspace))
    #expect(frame.minX >= -1 && frame.maxX <= workspace.bounds.width + 1)
  }
  #expect(workspace.applyPreset(.grid))
  workspace.panes[firstID]?.focus()
  let beforeSwap = workspace.layout
  let swapTarget = try #require(workspace.layout.paneIDs.last)
  let swapTargetPane = try #require(workspace.panes[swapTarget])
  let swapTargetTerminal = try #require(swapTargetPane.terminal)
  let liveSurface = first.surface
  #expect(!workspace.swapPanes(firstID, with: swapTarget), "Reorder only during layout editing")
  workspace.toggleEditing()
  let sourcePane = try #require(workspace.panes[firstID])
  let preview = try #require(sourcePane.dragPreview(in: sourcePane))
  #expect(preview.frame == sourcePane.bounds, "Drag the whole pane, not only its handle icon")
  #expect(preview.components.first?.frame.size == sourcePane.bounds.size)
  #expect(preview.components.count == 2, "Include the rendered GPU terminal in the pane preview")
  #expect(preview.components.last?.contents != nil)
  #expect(preview.components.last?.frame.size == first.bounds.size)
  #expect(workspace.swapPanes(firstID, with: swapTarget))
  #expect(workspace.layout.paneIDs.last == firstID)
  #expect(workspace.focusedID == firstID)
  #expect(workspace.panes[firstID]?.terminal === first && first.surface == liveSurface)
  #expect(workspace.panes[swapTarget] === swapTargetPane)
  #expect(workspace.panes[swapTarget]?.terminal === swapTargetTerminal)
  let swappedSnapshot = try JSONDecoder().decode(
    WorkspaceSnapshot.self, from: JSONEncoder().encode(workspace.snapshot()))
  try swappedSnapshot.validate()
  #expect(swappedSnapshot.layout == workspace.layout)
  #expect(!workspace.swapPanes(firstID, with: firstID))
  #expect(!workspace.swapPanes(UUID(), with: firstID))
  #expect(workspace.canSwapFocusedPane(.left))
  workspace.swapFocusedPane(.left)
  #expect(workspace.layout.paneIDs[2] == firstID)
  workspace.swapFocusedPane(.right)
  #expect(workspace.swapPanes(firstID, with: swapTarget))
  #expect(workspace.layout == beforeSwap)
  workspace.toggleEditing()
  let originalLayout = workspace.layout
  let browserSuite = "chop-workspace-files-\(UUID().uuidString)"
  let browserDefaults = try #require(UserDefaults(suiteName: browserSuite))
  defer { browserDefaults.removePersistentDomain(forName: browserSuite) }
  browserDefaults.set(directory.path, forKey: "fileTreeRootPath")
  let workspaceSplit = workspace.installFileBrowser(defaults: browserDefaults)
  window.layoutIfNeeded()
  let bodyFrame = workspaceSplit.convert(workspaceSplit.bounds, to: workspace)
  #expect(
    abs(workspace.bounds.maxY - bodyFrame.maxY - 48) < 0.5,
    "The global toolbar must span above both terminals and the file tree")
  #expect(workspaceSplit.fileBrowser.frame.height == workspaceSplit.bounds.height)
  #expect(workspaceSplit.isFileTreeVisible)
  #expect(workspaceSplit.minimumContentSize.width >= workspace.displayMinimumSize.width + 281)
  let shownMinimum = workspaceSplit.minimumContentSize
  workspaceSplit.toggleFileTree()
  #expect(!workspaceSplit.isFileTreeVisible)
  #expect(workspaceSplit.minimumContentSize.width < shownMinimum.width)
  workspaceSplit.toggleFileTree()
  #expect(workspaceSplit.isFileTreeVisible && workspaceSplit.minimumContentSize == shownMinimum)
  #expect(workspaceSplit.fileBrowser.frame.width >= WorkspaceSplitView.fileTreeMinimumWidth)
  #expect(workspaceSplit.fileBrowser.frame.maxX == workspaceSplit.bounds.maxX)
  #expect(workspace.layout == originalLayout && workspace.focusedPane.terminal === first)
  #expect(first.surface == liveSurface, "File tree visibility must not restart a terminal")
  let dropPasteboard = NSPasteboard.withUniqueName()
  defer { dropPasteboard.releaseGlobally() }
  let droppedFile = directory.appendingPathComponent("DROP_ARG_한글 'a' $.txt")
  try Data().write(to: droppedFile)
  #expect(dropPasteboard.writeObjects([droppedFile as NSURL]))
  let dropResult = directory.appendingPathComponent("drop-result")
  let resultArgument = try #require(TerminalFileDrop.text(for: [dropResult]))
  let dropSurface = swapTargetTerminal.surface
  let clipboardBeforeDrop = clipboard.string(forType: .string)
  swapTargetTerminal.insertText(
    "printf '%s' > " + resultArgument,
    replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(swapTargetTerminal.insertDroppedFiles(from: dropPasteboard))
  try await waitFor {
    window.firstResponder === swapTargetTerminal
      && viewport(of: swapTargetTerminal).replacingOccurrences(of: "\n", with: "").contains(
        "DROP_ARG")
  }
  #expect(!FileManager.default.fileExists(atPath: dropResult.path), "A drop must not send Enter")
  #expect(workspace.focusedID == swapTarget)
  #expect(swapTargetTerminal.surface == dropSurface && first.surface == liveSurface)
  #expect(clipboard.string(forType: .string) == clipboardBeforeDrop)
  try pressReturn(on: swapTargetTerminal, window: window)
  try await waitFor {
    FileManager.default.fileExists(atPath: dropResult.path) && !swapTargetTerminal.needsConfirmClose
  }
  #expect(try Data(contentsOf: dropResult) == Data(droppedFile.path.utf8))
  #expect(!terminal.insertDroppedFiles(from: dropPasteboard), "Closed surfaces reject a drop")
  workspace.panes[firstID]?.focus()
  workspaceSplit.toggleFileTree()
  workspace.moveFocus(.right)
  #expect(workspace.focusedID == workspace.layout.paneIDs[1])
  #expect(workspace.renameFocused(to: "서버"))
  #expect(workspace.focusedPane.name == "서버")
  #expect(!workspace.renameFocused(to: "  "))
  #expect(!workspace.renameFocused(to: String(repeating: "a", count: 65)))
  first.insertText(
    "sleep 0.2; printf 'HIDDEN_TASK_DONE\\n'",
    replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: first, window: window)
  workspace.toggleZoom()
  #expect(workspace.maximizedID == workspace.focusedID)
  #expect(workspace.layout == originalLayout)
  let firstSurface = first.surface
  let focusedBeforeTheme = workspace.focusedID
  workspace.applyAppearance(.dark)
  #expect(engine.appearanceMode == .dark)
  #expect(first.surface == firstSurface)
  #expect(first.effectiveAppearance.name == .darkAqua, "Detached surfaces also change mode")
  #expect(workspace.panes.values.allSatisfy { $0.effectiveAppearance.name == .darkAqua })
  #expect(workspace.layout == originalLayout && workspace.focusedID == focusedBeforeTheme)
  try await waitFor {
    (first.accessibilityValue() as? String ?? "").components(separatedBy: "HIDDEN_TASK_DONE").count
      >= 3 && !first.needsConfirmClose
  }
  workspace.toggleZoom()
  #expect(workspace.maximizedID == nil)
  #expect(workspace.panes[firstID]?.terminal === first)
  workspace.applyAppearance(.light)
  workspace.applyAppearance(.dark)
  #expect(first.surface == firstSurface, "Repeated theme changes must retain the PTY")
  workspace.removeEmptyPane(firstID)
  #expect(workspace.layout == originalLayout, "Removing a running pane is never allowed")
  first.insertText(
    "printf 'VALUE=%s\\n' \"$CHOP_PANE_VALUE\"",
    replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: first, window: window)
  try await waitFor {
    (first.accessibilityValue() as? String ?? "").contains("VALUE=preserved")
      && !first.needsConfirmClose
  }
  let other = try #require(workspace.panes[workspace.layout.paneIDs[1]]?.terminal)
  other.insertText(
    "printf 'OTHER=%s\\n' \"${CHOP_PANE_VALUE-unset}\"",
    replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: other, window: window)
  try await waitFor {
    (other.accessibilityValue() as? String ?? "").contains("OTHER=unset")
      && !other.needsConfirmClose
  }
  let keepID = try #require(workspace.layout.paneIDs.last)
  let keep = try #require(workspace.panes[keepID]?.terminal)
  for id in workspace.layout.paneIDs where id != keepID { workspace.panes[id]?.closeTerminal() }
  #expect(workspace.applyPreset(.single))
  #expect(workspace.layout.paneIDs.count == 4, "Single view preserves empty slots too")
  workspace.selectTab(keepID)
  #expect(workspace.focusedPane.terminal === keep)
  for id in workspace.layout.paneIDs where id != keepID { workspace.removeEmptyPane(id) }
  workspace.focusedPane.closeTerminal()
  workspace.removeEmptyPane(keepID)
  #expect(workspace.layout.paneIDs == [keepID], "Keep the final empty slot")
  #expect(workspace.applyPreset(.columns))
  let emptyID = try #require(workspace.layout.paneIDs.last)
  workspace.removeEmptyPane(emptyID)
  #expect(workspace.layout.paneIDs == [keepID])
  #expect(workspace.applyPreset(.columns))
  let restoredIDs = workspace.layout.paneIDs
  let beforeRestore = try #require(workspace.panes[restoredIDs[0]])
  beforeRestore.workingDirectory = directory.path
  beforeRestore.openTerminal()
  let oldShell = try #require(beforeRestore.terminal)
  #expect(oldShell.effectiveAppearance.name == .darkAqua, "New shells inherit the selected mode")
  try await waitFor { !oldShell.needsConfirmClose }
  oldShell.insertText(
    "export CHOP_RESTORE_SECRET=old_process; printf 'OLD_PROCESS_READY\\n'",
    replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: oldShell, window: window)
  try await waitFor {
    (oldShell.accessibilityValue() as? String ?? "").components(separatedBy: "OLD_PROCESS_READY")
      .count >= 3 && !oldShell.needsConfirmClose
  }
  beforeRestore.focus()
  #expect(workspace.renameFocused(to: "복원 테스트"))
  let saved = try JSONDecoder().decode(
    WorkspaceSnapshot.self, from: JSONEncoder().encode(workspace.snapshot()))
  try saved.validate()
  workspace.closeAll()
  let restored = WorkspaceView(engine: engine, snapshot: saved)
  window.contentView = restored
  window.layoutIfNeeded()
  defer { restored.closeAll() }
  restored.startRestoredTerminals()
  #expect(restored.layout == saved.layout)
  #expect(restored.focusedID == saved.focusedID)
  #expect(restored.focusedPane.name == "복원 테스트")
  #expect(restored.panes[restoredIDs[1]]?.terminal == nil, "Empty slots stay empty on restore")
  let newShell = try #require(restored.focusedPane.terminal)
  #expect(newShell !== oldShell)
  #expect(newShell.effectiveAppearance.name == .darkAqua, "Restored shells inherit the mode")
  try await waitFor { !newShell.needsConfirmClose }
  newShell.insertText(
    "printf 'RESTORE=%s\\n' \"${CHOP_RESTORE_SECRET-fresh}\"; pwd",
    replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: newShell, window: window)
  try await waitFor {
    let text = newShell.accessibilityValue() as? String ?? ""
    return text.contains("RESTORE=fresh") && text.contains(directory.lastPathComponent)
      && !newShell.needsConfirmClose
  }
  let empty = try #require(restored.panes[restoredIDs[1]])
  empty.workingDirectory = directory.appendingPathComponent("missing").path
  var missingPaths: [String] = []
  restored.onMissingDirectories = { missingPaths += $0 }
  empty.openTerminal()
  #expect(missingPaths.count == 1)
  #expect(empty.workingDirectory == FileManager.default.homeDirectoryForCurrentUser.path)
  restored.closeAll()

  let legacyID = UUID()
  let legacy = WorkspaceSnapshot(
    layout: .pane(legacyID),
    panes: [
      PaneSnapshot(id: legacyID, name: "이전 이름", workingDirectory: directory.path, wasRunning: false)
    ], focusedID: legacyID)
  let migrated = WorkspaceView(engine: engine, snapshot: legacy)
  window.contentView = migrated
  window.layoutIfNeeded()
  defer { migrated.closeAll() }
  migrated.startRestoredTerminals()
  #expect(migrated.layout.paneIDs.count == 4)
  #expect(migrated.layout.paneIDs.first == legacyID)
  #expect(migrated.focusedPane.name == "이전 이름")
  #expect(migrated.focusedPane.workingDirectory == directory.path)
  #expect(migrated.panes.values.filter { $0.isRunning }.count == 1)
  migrated.closeAll()
  migrated.panes[try #require(migrated.layout.paneIDs.last)]?.focus()
  let emptyGrid = migrated.snapshot()
  let emptyRestored = WorkspaceView(engine: engine, snapshot: emptyGrid)
  window.contentView = emptyRestored
  window.layoutIfNeeded()
  defer { emptyRestored.closeAll() }
  emptyRestored.startRestoredTerminals()
  #expect(emptyRestored.layout == emptyGrid.layout)
  #expect(emptyRestored.panes.values.filter { $0.isRunning }.count == 1)
  #expect(emptyRestored.panes[emptyGrid.layout.paneIDs[0]]?.isRunning == true)
  #expect(emptyRestored.focusedID == emptyGrid.layout.paneIDs[0])
  emptyRestored.applyAppearance(.light)
  #expect(emptyRestored.focusedPane.terminal?.effectiveAppearance.name == .aqua)
}

@MainActor
private func pressReturn(on terminal: TerminalView, window: NSWindow) throws {
  let event = try #require(
    NSEvent.keyEvent(
      with: .keyDown, location: .zero,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
  terminal.keyDown(with: event)
  let release = try #require(
    NSEvent.keyEvent(
      with: .keyUp, location: .zero,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: "\r",
      charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
  terminal.keyUp(with: release)
}

@MainActor
private func viewport(of terminal: TerminalView) -> String {
  guard let surface = terminal.surface else { return "" }
  let selection = ghostty_selection_s(
    top_left: ghostty_point_s(
      tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
    bottom_right: ghostty_point_s(
      tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
    rectangle: false)
  var text = ghostty_text_s()
  guard ghostty_surface_read_text(surface, selection, &text), let contents = text.text else {
    return ""
  }
  defer { ghostty_surface_free_text(surface, &text) }
  return String(cString: contents)
}

@MainActor
private func waitFor(_ condition: () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(15)
  while !condition(), Date() < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(condition(), "Terminal integration timed out")
  if !condition() { throw TerminalError.surface }
}
