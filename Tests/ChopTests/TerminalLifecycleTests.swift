import AppKit
import Darwin
import Foundation
import GhosttyKit
import Testing

@testable import Chop

private final class LifecycleTestBundle: NSObject {}

@MainActor
@Test func rapidTerminalCloseRemainsResponsive() async throws {
  if let path = ProcessInfo.processInfo.environment["CHOP_LIFECYCLE_FIXTURE"] {
    try await runLifecycleProbe(at: URL(fileURLWithPath: path))
    return
  }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop lifecycle's-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  let script = """
    import os,sys
    print('READY',flush=True)
    for line in sys.stdin:
     if line.strip() in ('title','reply','render'):
      payload={'title':b'\\x1b]0;CHOP_BUSY\\x07',
       'reply':b'\\x1b[6n',
       'render':b'\\x1b]11;#123456\\x07\\x1b]11;#654321\\x07'}[line.strip()]
      while True: os.write(1,payload)
     if line.startswith('keep-'): print('\\x1b]0;'+line.strip()+'\\x07',flush=True)
     print('ACK:'+line.strip(),flush=True)
    """
  try script.write(
    to: directory.appendingPathComponent("terminal.py"), atomically: true, encoding: .utf8)
  let log = directory.appendingPathComponent("output.log")
  FileManager.default.createFile(atPath: log.path, contents: nil)
  let output = try FileHandle(forWritingTo: log)
  defer { try? output.close() }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
  let binary = try #require(Bundle(for: LifecycleTestBundle.self).executableURL).path
  let arguments = [
    "--testing-library", "swift-testing", "--filter", "rapidTerminalCloseRemainsResponsive",
    "--no-parallel",
  ]
  process.arguments =
    CommandLine.arguments.contains("--test-bundle-path")
    ? ["--test-bundle-path", binary] + arguments + [binary] : arguments
  var environment = ProcessInfo.processInfo.environment
  environment["CHOP_LIFECYCLE_FIXTURE"] = directory.path
  process.environment = environment
  process.standardOutput = output
  process.standardError = output
  try process.run()
  let deadline = ContinuousClock.now.advanced(by: .seconds(45))
  while process.isRunning, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(50))
  }
  if process.isRunning {
    // 이 테스트가 띄운 하위 검사만 중단한다. 메인 스레드 교착도 CI를 무한 대기시키지 않는다.
    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
    let progress = try? String(
      contentsOf: directory.appendingPathComponent("progress"), encoding: .utf8)
    Issue.record("터미널 종료가 제한 시간을 넘겼습니다: \(progress ?? "진행 기록 없음")")
  }
  let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
  #expect(process.terminationStatus == 0, "하위 검사 실패: \(text.suffix(4000))")
  #expect(
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("completed").path))
}

@MainActor
private func runLifecycleProbe(at directory: URL) async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let scriptPath = directory.appendingPathComponent("terminal.py").path
  let quotedPath = "'" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
  let engine = TerminalEngine(command: "/usr/bin/python3 -u \(quotedPath)")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
    styleMask: [.titled], backing: .buffered, defer: false)
  let container = NSView(frame: window.contentLayoutRect)
  window.contentView = container
  window.orderFront(nil)
  var terminals: [TerminalView] = []
  defer {
    for terminal in terminals { terminal.close() }
    window.orderOut(nil)
    engine.shutdown()
  }
  func addTerminal() throws -> TerminalView {
    let terminal = try TerminalView(engine: engine, workingDirectory: directory.path)
    container.addSubview(terminal)
    terminals.append(terminal)
    return terminal
  }
  func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition())
  }
  func send(_ text: String, to terminal: TerminalView) throws {
    terminal.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "\r",
        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    terminal.keyDown(with: event)
  }
  func changeFont(in terminal: TerminalView) throws {
    let surface = try #require(terminal.surface)
    let action = "increase_font_size:1"
    #expect(
      action.withCString { ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) })
  }
  let survivor = try addTerminal()
  try await waitFor { (survivor.accessibilityValue() as? String ?? "").contains("READY") }
  for mode in ["title", "reply", "render"] {
    let closing = try addTerminal()
    try await waitFor { (closing.accessibilityValue() as? String ?? "").contains("READY") }
    try changeFont(in: closing)
    try send(mode, to: closing)
    let title = "keep-\(mode)"
    try send(title, to: survivor)
    try "메시지 큐 포화 직후 종료: \(mode)".write(
      to: directory.appendingPathComponent("progress"), atomically: true, encoding: .utf8)
    blockAppThreadForQueuePressure()
    closing.close()
    closing.removeFromSuperview()
    try await waitFor { survivor.terminalTitle == title }
    let marker = "ping-\(mode)"
    try send(marker, to: survivor)
    try await waitFor {
      (survivor.accessibilityValue() as? String ?? "").contains("ACK:\(marker)")
    }
  }
  for round in 1...3 {
    try "준비 대기 없이 16개 연속 종료: \(round)회".write(
      to: directory.appendingPathComponent("progress"), atomically: true, encoding: .utf8)
    let batch = try (0..<16).map { _ in try addTerminal() }
    for terminal in batch {
      try changeFont(in: terminal)
      terminal.close()
      terminal.removeFromSuperview()
    }
  }
  try send("after-batch", to: survivor)
  try await waitFor {
    (survivor.accessibilityValue() as? String ?? "").contains("ACK:after-batch")
  }
  survivor.close()
  survivor.removeFromSuperview()
  try Data().write(to: directory.appendingPathComponent("completed"))
}

@MainActor
private func blockAppThreadForQueuePressure() {
  Thread.sleep(forTimeInterval: 0.25)
}
