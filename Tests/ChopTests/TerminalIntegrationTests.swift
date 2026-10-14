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
  let engine = TerminalEngine(clipboard: clipboard)
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
  try await waitFor { !terminal.needsConfirmClose }
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
