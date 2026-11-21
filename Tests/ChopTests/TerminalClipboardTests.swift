import AppKit
import GhosttyKit
import Testing

@testable import Chop

@MainActor
@Test func unavailableClipboardDoesNotCrashEngineOrRequestItDuringInitialization() {
  var requests = 0
  let engine = TerminalEngine(clipboard: {
    requests += 1
    return nil
  })
  #expect(requests == 0)
  #expect(engine.readClipboardText().isEmpty)
  #expect(!engine.writeClipboardText("클립보드 서비스 없음"))
  #expect(requests == 2)
}

@MainActor
@Test func commandCCopiesSelectionWithoutSendingInputOrStealingTextFieldShortcuts() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let script = directory.appendingPathComponent("copy.py")
  let captured = directory.appendingPathComponent("input.bin")
  try """
  import os,tty
  tty.setraw(0)
  os.write(1,'COPY_READY\\r\\n한글 복사 확인\\r\\n'.encode())
  with open('\(captured.path)','wb',buffering=0) as output:
   while True:
    data=os.read(0,4096)
    if not data: break
    output.write(data)
    if b'\\x01' in data: os.write(1,b'\\r\\nSYNC_RECEIVED\\r\\n')
    if b'\\x03' in data: os.write(1,b'\\r\\nCTRL_C_RECEIVED\\r\\n')
  """.write(to: script, atomically: true, encoding: .utf8)
  let clipboard = NSPasteboard.withUniqueName()
  defer { clipboard.releaseGlobally() }
  let engine = TerminalEngine(
    clipboard: { clipboard }, command: "/usr/bin/python3 -u '\(script.path)'")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let terminal = try TerminalView(engine: engine, workingDirectory: directory.path)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
    styleMask: [.titled], backing: .buffered, defer: false)
  let container = NSView(frame: window.contentLayoutRect)
  window.contentView = container
  terminal.frame = container.bounds
  container.addSubview(terminal)
  window.makeKeyAndOrderFront(nil)
  window.makeFirstResponder(terminal)
  defer {
    terminal.close()
    window.orderOut(nil)
    engine.shutdown()
  }
  func waitFor(_ marker: String) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while terminal.outputSnapshot()?.contains(marker) != true, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(terminal.outputSnapshot()?.contains(marker) == true)
  }
  func key(
    _ text: String, code: UInt16 = 8, modifiers: NSEvent.ModifierFlags = .command,
    type: NSEvent.EventType = .keyDown
  ) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: modifiers, timestamp: 1,
        windowNumber: window.windowNumber, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
  }
  try await waitFor("COPY_READY")
  let surface = try #require(terminal.surface)
  terminal.selectAll(nil)
  try #require(ghostty_surface_has_selection(surface))
  try #require(terminal.performKeyEquivalent(with: key("c")))
  #expect(clipboard.string(forType: .string)?.contains("한글 복사 확인") == true)
  terminal.keyUp(with: try key("c", modifiers: [], type: .keyUp))
  for (text, code, modifiers) in [
    ("ㅊ", UInt16(8), NSEvent.ModifierFlags.command),
    ("C", 8, [.command, .capsLock]), ("c", 34, .command),
  ] {
    clipboard.clearContents()
    terminal.selectAll(nil)
    #expect(terminal.performKeyEquivalent(with: try key(text, code: code, modifiers: modifiers)))
    #expect(clipboard.string(forType: .string)?.contains("COPY_READY") == true)
    terminal.keyUp(with: try key(text, code: code, modifiers: [], type: .keyUp))
  }
  clipboard.clearContents()
  terminal.selectAll(nil)
  terminal.keyDown(with: try key("c"))
  #expect(clipboard.string(forType: .string)?.contains("COPY_READY") == true)
  terminal.keyUp(with: try key("c", modifiers: [], type: .keyUp))
  #expect(!terminal.performKeyEquivalent(with: try key("j", code: 8)))
  #expect(!terminal.performKeyEquivalent(with: try key("c", modifiers: [.command, .shift])))
  #expect(!terminal.performKeyEquivalent(with: try key("c", modifiers: .control)))
  let field = NSTextField(string: "입력창 선택")
  container.addSubview(field)
  window.makeFirstResponder(field)
  #expect(!terminal.performKeyEquivalent(with: try key("c")))
  #expect(window.firstResponder === field.currentEditor())
  window.makeFirstResponder(terminal)
  // Plain clicks clear the selection; Cmd+C must then leave the clipboard unchanged.
  let location = terminal.convert(NSPoint(x: 30, y: 20), to: nil)
  for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    let event = try #require(
      NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: 1,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    )
    if type == .leftMouseDown {
      terminal.mouseDown(with: event)
    } else {
      terminal.mouseUp(with: event)
    }
  }
  #expect(!ghostty_surface_has_selection(surface))
  clipboard.clearContents()
  clipboard.setString("기존 클립보드", forType: .string)
  #expect(terminal.performKeyEquivalent(with: try key("c")))
  terminal.keyUp(with: try key("c", modifiers: [], type: .keyUp))
  #expect(clipboard.string(forType: .string) == "기존 클립보드")
  terminal.keyDown(with: try key("\u{01}", code: 0, modifiers: .control))
  try await waitFor("SYNC_RECEIVED")
  #expect(try Data(contentsOf: captured) == Data([1]))
  terminal.keyDown(with: try key("\u{03}", modifiers: .control))
  try await waitFor("CTRL_C_RECEIVED")
  #expect(try Data(contentsOf: captured) == Data([1, 3]))
}
