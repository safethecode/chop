import AppKit
import GhosttyKit
import Testing

@testable import Chop

@MainActor
@Test func fileLinksUseRealWrappedTerminalCellsAndKeepSelectionAndURLs() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-file-links-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let image = directory.appendingPathComponent(
    "noci-og-preview-" + String(repeating: "long-", count: 12) + ".png")
  let unicode = directory.appendingPathComponent("한글 공백 (2) 👩‍💻.png")
  let relative = directory.appendingPathComponent("relative.png")
  for file in [image, unicode, relative] { try Data().write(to: file) }
  let script = directory.appendingPathComponent("fixture.py")
  let lines = [
    "PNG 다운로드 (\(image.path)) · SVG 원본 (/tmp/chop-missing-image.svg)",
    "한글 공백 경로: \"\(unicode.path)\"", "./relative.png", "https://example.com/chop",
    "\u{1B}]8;;\(image.absoluteString)\u{1B}\\파일 URI\u{1B}]8;;\u{1B}\\", "LINK_READY",
  ]
  let data = try JSONSerialization.data(withJSONObject: lines)
  let encoded = data.base64EncodedString()
  try """
  import base64,json,sys,time
  sys.stdout.write('\u{1B}[2J\u{1B}[H')
  for line in json.loads(base64.b64decode('\(encoded)')): print(line, flush=True)
  while True: time.sleep(1)
  """.write(to: script, atomically: true, encoding: .utf8)
  let engine = TerminalEngine(command: "/usr/bin/python3 -u \(script.path)")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let pane = TerminalPaneView(engine: engine, workingDirectory: directory.path)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = pane
  window.makeKeyAndOrderFront(nil)
  pane.layoutSubtreeIfNeeded()
  pane.openTerminal()
  defer {
    pane.closeTerminal()
    window.orderOut(nil)
    engine.shutdown()
  }
  let terminal = try #require(pane.terminal)
  func waitFor(_ phase: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition(), "\(phase): \(terminal.outputSnapshot() ?? "")")
  }
  try await waitFor("fixture output") { terminal.outputSnapshot()?.contains("LINK_READY") == true }
  let pid = terminal.childPID
  let surface = try #require(terminal.surface)
  var revealed: [URL] = []
  var external: [URL] = []
  terminal.revealFile = { revealed.append($0) }
  terminal.openExternalURL = { external.append($0) }
  func event(_ type: NSEvent.EventType, at point: NSPoint, mods: NSEvent.ModifierFlags = .command)
    throws -> NSEvent
  {
    try #require(
      NSEvent.mouseEvent(
        with: type, location: terminal.convert(point, to: nil), modifierFlags: mods,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 0))
  }
  func points(for text: String) throws -> [NSPoint] {
    let size = ghostty_surface_size(surface)
    let scale = window.backingScaleFactor
    var found: [NSPoint] = []
    for row in 0..<min(Int(size.rows), 36) {
      for column in 0..<Int(size.columns) {
        let point = NSPoint(
          x: 12 + (Double(column) + 0.5) * Double(size.cell_width_px) / scale,
          y: terminal.bounds.height - 12 - (Double(row) + 0.5) * Double(size.cell_height_px) / scale
        )
        terminal.mouseMoved(with: try event(.mouseMoved, at: point))
        if terminal.hoveredLink == text { found.append(point) }
      }
    }
    return found
  }
  func click(_ point: NSPoint, mods: NSEvent.ModifierFlags = .command) throws {
    terminal.mouseDown(with: try event(.leftMouseDown, at: point, mods: mods))
    terminal.mouseUp(with: try event(.leftMouseUp, at: point, mods: mods))
  }
  let wrapped = try points(for: "(\(image.path))")
  let first = try #require(wrapped.first)
  let last = try #require(wrapped.last)
  #expect(first.y != last.y, "The path must span more than one physical row")
  try #require(wrapped.count >= image.path.count, "Every cell must resolve the complete path")
  try click(first, mods: [])
  #expect(revealed.isEmpty && terminal.hoveredLink == nil)
  try click(wrapped[wrapped.count / 2])
  try await waitFor("wrapped path click") { revealed.count == 1 }
  #expect(revealed.last?.path == image.path)
  #expect(terminal.toolTip?.contains("⌘클릭") == true)
  terminal.mouseDown(with: try event(.leftMouseDown, at: first))
  let outside = NSPoint(x: 20, y: 15)
  terminal.mouseDragged(with: try event(.leftMouseDragged, at: outside))
  terminal.mouseUp(with: try event(.leftMouseUp, at: outside))
  await Task.yield()
  #expect(revealed.count == 1, "Dragging must cancel link opening")
  for (text, expected) in [
    ("\"\(unicode.path)\"", unicode), ("./relative.png", relative),
    (image.absoluteString, image),
  ] {
    let matchingPoints = try points(for: text)
    let minimumCells = text == image.absoluteString ? "파일 URI".count : text.count
    try #require(matchingPoints.count >= minimumCells, "Partial link: \(text)")
    let point = matchingPoints[matchingPoints.count / 2]
    let previousCount = revealed.count
    try click(point)
    try await waitFor("local path click") { revealed.count == previousCount + 1 }
    #expect(revealed.last?.path == expected.path)
  }
  let missing = try #require(points(for: "(/tmp/chop-missing-image.svg)").first)
  try click(missing)
  await Task.yield()
  #expect(revealed.count == 4 && external.isEmpty)
  let web = try #require(points(for: "https://example.com/chop").first)
  try click(web)
  try await waitFor("web URL click") { external.count == 1 }
  #expect(external.first?.absoluteString == "https://example.com/chop")
  engine.applyAppearance(.dark)
  pane.applyAppearance()
  #expect(try !points(for: "./relative.png").isEmpty)
  #expect(terminal.surface == surface && terminal.childPID == pid)
}
