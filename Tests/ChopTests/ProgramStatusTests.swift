import AppKit
import ChopCore
import Testing

@testable import Chop

@MainActor
@Test func activityNavigationRevealsTheRequestedPaneAcrossZoomAndTabs() throws {
  _ = NSApplication.shared
  let workspace = WorkspaceView(engine: TerminalEngine())
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 450),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = workspace
  window.orderFront(nil)
  defer { window.orderOut(nil) }
  let ids = workspace.layout.paneIDs
  workspace.toggleZoom(ids[0])
  #expect(workspace.maximizedID == ids[0])
  workspace.activatePane(ids[1])
  #expect(workspace.maximizedID == ids[1] && workspace.focusedID == ids[1])
  #expect(workspace.panes[ids[1]]?.window === window)
  #expect(workspace.applyPreset(.single))
  workspace.selectTab(ids[0])
  workspace.activatePane(ids[1])
  #expect(workspace.isTabbed && workspace.focusedID == ids[1])
  #expect(workspace.panes[ids[1]]?.window === window)
}

@MainActor
@Test func realProgramStatusHandshakeReportsAndLifecycleReachPaneAndTabs() async throws {
  _ = NSApplication.shared
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-status-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  let script = directory.appendingPathComponent("status.py")
  try """
  import os,sys,tty,termios,select,time,re,base64
  previous=termios.tcgetattr(0);tty.setraw(0)
  os.write(1,b'\\x1b]7501;?\\x07\\x1b[c')
  reply=b'';deadline=time.monotonic()+4
  while time.monotonic()<deadline:
   if select.select([0],[],[],0.1)[0]: reply+=os.read(0,4096)
   if b']7501;?' in reply and re.search(rb'\\x1b\\[\\?[0-9;]+c',reply): break
  termios.tcsetattr(0,termios.TCSANOW,previous)
  good=b']7501;?' in reply and reply.find(b']7501;?')<reply.find(b'\\x1b[?')
  print('QUERY_OK' if good else 'QUERY_BAD:'+repr(reply),flush=True)
  payloads={
   'progress':b'\\x1b]9;4;1;42\\x07',
     'legacy-after-status':b'\\x1b]9;4;1;42\\x07',
     'paused':b'\\x1b]9;4;4;42\\x07',
   'working':b'\\x1b]7501;state=working:app=fixture\\x1b\\\\',
   'blocked':b'\\x1b]7501;state=blocked:kind=permission:app=fixture\\x07',
     'child':b'\\x1b]7501;state=done:id=worker\\x07',
     'childclear':b'\\x1b]7501;state=clear:id=worker\\x07',
   'invalid':b'\\x1b]7501;state=done:msg=Cg==\\x07',
     'large':b'\\x1b]7501;state=blocked:kind=question:msg='+base64.b64encode(('설명'*200+chr(0x202e)).encode())+b'\\x07',
   'done-prompt':b'\\x1b]7501;state=done\\x07\\x1b]133;A\\x07',
   'working-prompt':b'\\x1b]7501;state=working\\x07\\x1b]133;A\\x07',
   'reset':b'\\x1bc',
  }
  for line in sys.stdin:
   key=line.strip()
   if key in payloads: os.write(1,payloads[key])
   print('ACK:'+key,flush=True)
  """.write(to: script, atomically: true, encoding: .utf8)
  let engine = TerminalEngine(command: "/usr/bin/python3 -u '\(script.path)'")
  var attention: [ProgramStatus] = []
  engine.onAttention = { _, status in attention.append(status) }
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let pane = TerminalPaneView(engine: engine)
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
  window.makeFirstResponder(nil)
  let terminal = try #require(pane.terminal)
  func waitFor(_ phase: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition(), "\(phase): \(terminal.outputSnapshot()?.suffix(1000) ?? "")")
  }
  func send(_ text: String) throws {
    terminal.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    terminal.keyDown(
      with: try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: "\r",
          charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
  }
  try await waitFor("protocol handshake") {
    terminal.outputSnapshot()?.contains("QUERY_OK") == true
  }
  try send("progress")
  try await waitFor("legacy progress") { pane.programStatus?.progress == 42 }
  try send("paused")
  try await waitFor("paused progress") { pane.programStatus?.state == .idle }
  #expect(attention.isEmpty)
  try send("blocked")
  try await waitFor("blocked") { pane.programStatus?.kind == .permission }
  #expect(pane.programStatus?.statusLabel == "승인 필요" && attention.count == 1)
  try send("child")
  try await waitFor("child completion") { terminal.outputSnapshot()?.contains("ACK:child") == true }
  #expect(pane.programStatus?.state == .blocked && attention.count == 1)
  try send("childclear")
  try await waitFor("child cleared") {
    terminal.outputSnapshot()?.contains("ACK:childclear") == true
  }
  let bar = TerminalTabBar(
    panes: [pane], selectedID: pane.id, mode: .light,
    onSelect: { _ in }, onAdd: {}, onClose: {}, onRename: { _ in })
  func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
  #expect(
    descendants(pane).contains {
      ($0 as? ProgramStatusView)?.accessibilityLabel()?.contains("승인 필요") == true
    })
  #expect(
    descendants(bar).compactMap { $0 as? NSButton }.contains {
      $0.accessibilityLabel()?.contains("승인 필요") == true
    })
  try send("legacy-after-status")
  try await waitFor("legacy report acknowledged") {
    terminal.outputSnapshot()?.contains("ACK:legacy-after-status") == true
  }
  #expect(pane.programStatus?.kind == .permission)
  try send("invalid")
  try await waitFor("invalid report acknowledged") {
    terminal.outputSnapshot()?.contains("ACK:invalid") == true
  }
  #expect(pane.programStatus?.kind == .permission && attention.count == 1)
  try send("large")
  try await waitFor("allocated report") {
    pane.programStatus?.message == String(repeating: "설명", count: 200) + "\u{202E}"
  }
  #expect(pane.programStatus?.statusDescription.contains("\u{202E}") == false)
  #expect(pane.programStatus?.statusLabel == "답변 필요" && attention.count == 2)
  try send("done-prompt")
  try await waitFor("completion survives prompt") { pane.programStatus?.state == .done }
  #expect(attention.last?.state == .done)
  try send("working-prompt")
  try await waitFor("prompt removes active report") { pane.programStatus == nil }
  try send("blocked")
  try await waitFor("next blocked report") { pane.programStatus?.state == .blocked }
  try send("reset")
  try await waitFor("terminal reset") { pane.programStatus == nil }
  try send("progress")
  try await waitFor("legacy support after reset") { pane.programStatus?.progress == 42 }
}
