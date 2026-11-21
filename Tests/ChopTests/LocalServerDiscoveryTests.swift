import AppKit
import ChopCore
import GhosttyKit
import Testing

@testable import Chop

@MainActor
@Test func localServerHintsKeepRecentOutputAndSurviveDirectoryAliases() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let project = directory.appendingPathComponent("project")
  let other = directory.appendingPathComponent("other")
  let alias = directory.appendingPathComponent("project-alias")
  for folder in [project, other] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
  let script = directory.appendingPathComponent("output.py")
  try #"""
  from pathlib import Path
  import time
  root=Path(__file__).parent
  while not (root/'start').exists(): time.sleep(.02)
  for _ in range(240): print('가'*180)
  print('http://localhost:3000에서 확인하세요.',flush=True)
  while not (root/'clear').exists(): time.sleep(.02)
  print('\x1b[2J\x1b[HHINT_CLEARED',flush=True)
  while True: time.sleep(1)
  """#.write(to: script, atomically: true, encoding: .utf8)
  let quoted = "'" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  let engine = TerminalEngine(command: "/usr/bin/python3 -u \(quoted)")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let frame = NSRect(x: 0, y: 0, width: 3200, height: 1800)
  let terminal = try TerminalView(engine: engine, workingDirectory: alias.path, frame: frame)
  let window = NSWindow(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
  window.contentView = terminal
  window.orderFront(nil)
  terminal.frame = frame
  defer {
    terminal.close()
    window.orderOut(nil)
    engine.shutdown()
  }
  let surface = try #require(terminal.surface)
  func activeText() -> String {
    let selection = ghostty_selection_s(
      top_left: ghostty_point_s(
        tag: GHOSTTY_POINT_ACTIVE, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
      bottom_right: ghostty_point_s(
        tag: GHOSTTY_POINT_ACTIVE, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
      rectangle: false)
    var text = ghostty_text_s()
    guard ghostty_surface_read_text(surface, selection, &text), let contents = text.text else {
      return ""
    }
    defer { ghostty_surface_free_text(surface, &text) }
    let bytes = UnsafeBufferPointer(start: contents, count: Int(text.text_len))
    return String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
  func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition())
  }
  try Data().write(to: directory.appendingPathComponent("start"))
  try await waitFor { activeText().contains("http://localhost:3000") }
  #expect(
    activeText().utf8.count > 32_768, "The address must follow more than 32 KB of active text")
  #expect(terminal.serverDiscoveryTarget().advertisedPorts == [3000])
  try Data().write(to: directory.appendingPathComponent("clear"))
  try await waitFor { activeText().contains("HINT_CLEARED") }
  #expect(terminal.serverDiscoveryTarget().advertisedPorts.isEmpty)
  terminal.workingDirectory = alias.path
  terminal.updateLocalServers([LocalServer(host: "localhost", port: 3000)])
  terminal.workingDirectory = project.resolvingSymlinksInPath().standardizedFileURL.path
  #expect(terminal.serverDiscoveryTarget().advertisedPorts == [3000])
  terminal.workingDirectory = other.path
  #expect(terminal.serverDiscoveryTarget().advertisedPorts.isEmpty)
  terminal.workingDirectory = project.path
  terminal.updateLocalServers([])
  #expect(terminal.serverDiscoveryTarget().advertisedPorts.isEmpty)
}
