import AppKit
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
  workspace.focusedPane.openTerminal()
  let firstID = workspace.focusedID
  let first = try #require(workspace.focusedPane.terminal)
  try await waitFor { !first.needsConfirmClose }
  first.insertText(
    "export CHOP_PANE_VALUE=preserved", replacementRange: NSRange(location: NSNotFound, length: 0))
  try pressReturn(on: first, window: window)
  try await waitFor { !first.needsConfirmClose }
  #expect(workspace.applyPreset(.grid))
  #expect(workspace.panes[firstID]?.terminal === first)
  for id in workspace.layout.paneIDs where id != firstID { workspace.panes[id]?.openTerminal() }
  try await waitFor { !workspace.needsConfirmClose }
  #expect(workspace.panes.values.filter { $0.isRunning }.count == 4)
  #expect(!workspace.applyPreset(.columns), "A smaller preset must never kill running shells")
  workspace.panes[firstID]?.focus()
  let originalLayout = workspace.layout
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
  try await waitFor {
    (first.accessibilityValue() as? String ?? "").components(separatedBy: "HIDDEN_TASK_DONE").count
      >= 3 && !first.needsConfirmClose
  }
  workspace.toggleZoom()
  #expect(workspace.maximizedID == nil)
  #expect(workspace.panes[firstID]?.terminal === first)
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
  #expect(
    workspace.layout.paneIDs == [keepID],
    "Shrinking keeps a running pane even when it was the last slot")
  #expect(workspace.focusedPane.terminal === keep)
  workspace.focusedPane.closeTerminal()
  workspace.removeEmptyPane(keepID)
  #expect(workspace.layout.paneIDs == [keepID], "Keep the final empty slot")
  #expect(workspace.applyPreset(.columns))
  let emptyID = try #require(workspace.layout.paneIDs.last)
  workspace.removeEmptyPane(emptyID)
  #expect(workspace.layout.paneIDs == [keepID])
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
private func waitFor(_ condition: () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(15)
  while !condition(), Date() < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(condition(), "Terminal integration timed out")
  if !condition() { throw TerminalError.surface }
}
