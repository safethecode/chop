import AppKit
import ChopCore
import Testing
import WebKit

@testable import Chop

@MainActor
@Test func webPreviewRetriesAnOfflineServerAndKeepsHistoryAndSafeAddressInput() async throws {
  _ = NSApplication.shared
  let server = try await WebPreviewFixture.make()
  defer { server.close() }
  let preview = WebPreviewView(dataStore: .nonPersistent())
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = preview
  window.orderFront(nil)
  defer {
    preview.close()
    window.orderOut(nil)
  }
  preview.applyAppearance(.light)
  preview.load(server.url)
  try await waitForWebPreview { preview.errorMessage != nil }
  #expect(preview.url == server.url)
  try await server.activate()
  preview.reload()
  try await waitForWebPreview { preview.webView.title == "미리보기 검사" && !preview.webView.isLoading }
  #expect(preview.errorMessage == nil)
  preview.load(server.url.appendingPathComponent("next"))
  try await waitForWebPreview { preview.webView.title == "다음 페이지" && preview.webView.canGoBack }
  preview.goBack()
  try await waitForWebPreview { preview.webView.title == "미리보기 검사" && preview.webView.canGoForward }
  preview.goForward()
  try await waitForWebPreview { preview.webView.title == "다음 페이지" }
  let previous = preview.url
  preview.addressField.stringValue = "file:///tmp/should-not-be-loaded"
  preview.navigate()
  #expect(preview.errorMessage?.contains("웹사이트 주소") == true)
  #expect(preview.url == previous)
  preview.reload()
  try await waitForWebPreview { !preview.webView.isLoading && preview.errorMessage == nil }
}

@MainActor
@Test func mixedWebAndTerminalPanesKeepTheirSurfacesAndRestoreContentKinds() async throws {
  _ = NSApplication.shared
  let server = try await WebPreviewFixture.make()
  defer { server.close() }
  try await server.activate()
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  let engine = TerminalEngine(command: "/bin/zsh -l")
  try engine.start(
    resources: root.appendingPathComponent("build/release/Chop.app/Contents/Resources"))
  let workspace = WorkspaceView(engine: engine, initialDirectory: server.directory.path)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 890, height: 450),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.contentView = workspace
  window.orderFront(nil)
  defer {
    workspace.closeAll()
    window.orderOut(nil)
    engine.shutdown()
  }
  workspace.startRestoredTerminals()
  let terminal = try #require(workspace.focusedPane.terminal)
  try await waitForWebPreview { !terminal.needsConfirmClose && terminal.childPID > 0 }
  let process = terminal.childPID
  workspace.openWebPreview(server.url)
  let webID = workspace.focusedID
  let preview = try #require(workspace.focusedPane.browser)
  try await waitForWebPreview { preview.webView.title == "미리보기 검사" && !preview.webView.isLoading }
  _ = try await webScript(
    preview, "document.getElementById('draft').value='보존한 입력'; window.keepValue=42; '준비'")
  for mode in AppearanceMode.allCases {
    workspace.applyAppearance(mode)
    for preset in LayoutPreset.allCases {
      #expect(workspace.applyPreset(preset))
      #expect(workspace.panes[webID]?.browser === preview)
      #expect(terminal.childPID == process)
      #expect(try await webScript(preview, "document.getElementById('draft').value") == "보존한 입력")
      #expect(try await webScript(preview, "String(window.keepValue)") == "42")
    }
  }
  let count = workspace.panes.count
  workspace.openWebPreview(server.url)
  #expect(workspace.focusedID == webID && workspace.panes.count == count)
  let terminalPane = try #require(workspace.panes.values.first(where: { $0.terminal === terminal }))
  terminalPane.focus()
  preview.reloadOrStop()
  workspace.updateFocusFromResponder(window.firstResponder)
  #expect(workspace.focusedID == webID, "웹 도구를 누른 뒤 키보드 초점도 해당 칸을 따라야 합니다")
  try await waitForWebPreview { !preview.webView.isLoading }
  workspace.addTerminal()
  #expect(
    workspace.panes[webID]?.browser === preview, "Adding a terminal must not replace a web pane")
  let saved = workspace.snapshot()
  try saved.validate()
  #expect(saved.panes.first(where: { $0.id == webID })?.contentKind == .web)
  #expect(saved.panes.first(where: { $0.id == webID })?.wasRunning == false)
  let restored = WorkspaceView(engine: engine, snapshot: saved)
  let restoreWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 890, height: 450),
    styleMask: [.titled], backing: .buffered, defer: false)
  restoreWindow.contentView = restored
  restoreWindow.orderFront(nil)
  defer {
    restored.closeAll()
    restoreWindow.orderOut(nil)
  }
  restored.startRestoredTerminals()
  let restoredWeb = try #require(restored.panes[webID]?.browser)
  try await waitForWebPreview { restoredWeb.webView.title == "미리보기 검사" }
  #expect(restoredWeb !== preview && restoredWeb.url == server.url)
}

@MainActor
@Test func aSingleBlankWebPaneRestoresWithoutBecomingATerminalGrid() throws {
  _ = NSApplication.shared
  let id = UUID()
  let saved = WorkspaceSnapshot(
    layout: .pane(id),
    panes: [
      PaneSnapshot(
        id: id, name: "웹 1", workingDirectory: "/tmp", wasRunning: false, contentKind: .web)
    ],
    focusedID: id)
  let workspace = WorkspaceView(engine: TerminalEngine(), snapshot: saved)
  defer { workspace.closeAll() }
  workspace.startRestoredTerminals()
  #expect(workspace.layout.paneIDs == [id])
  #expect(workspace.focusedPane.browser != nil && workspace.focusedPane.terminal == nil)
  #expect(workspace.snapshot().panes[0].contentKind == .web)
}

@MainActor
private func webScript(_ preview: WebPreviewView, _ script: String) async throws -> String {
  try await withCheckedThrowingContinuation { continuation in
    preview.webView.evaluateJavaScript(script) { value, error in
      if let error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: value as? String ?? "")
      }
    }
  }
}

@MainActor
private func waitForWebPreview(
  sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(12))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  try #require(condition(), sourceLocation: sourceLocation)
}

@MainActor
private final class WebPreviewFixture {
  let directory: URL
  let process: Process
  let url: URL

  private init(directory: URL, process: Process, url: URL) {
    self.directory = directory
    self.process = process
    self.url = url
  }

  static func make() async throws -> WebPreviewFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "chop-web-test-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.arguments = [
      "-c",
      """
      from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
      from pathlib import Path
      import sys,time
      root=Path(sys.argv[1])
      class Handler(BaseHTTPRequestHandler):
       def do_GET(self):
        title='다음 페이지' if self.path.startswith('/next') else '미리보기 검사'
        body=('<!doctype html><meta charset="utf-8"><title>'+title+'</title><input id="draft"><p>'+title+'</p>').encode()
        self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
      server=ThreadingHTTPServer(('127.0.0.1',0),Handler,bind_and_activate=False)
      server.server_bind();port=server.server_port;server.server_close()
      (root/'port').write_text(str(port))
      while not (root/'activate').exists(): time.sleep(0.01)
      server=ThreadingHTTPServer(('127.0.0.1',port),Handler)
      (root/'ready').touch();server.serve_forever()
      """, directory.path,
    ]
    try process.run()
    do {
      var port: UInt16?
      try await waitForWebPreview {
        port = (try? String(contentsOf: directory.appendingPathComponent("port"), encoding: .utf8))
          .flatMap(UInt16.init)
        return port != nil
      }
      let url = try #require(URL(string: "http://127.0.0.1:\(port!)/"))
      return WebPreviewFixture(directory: directory, process: process, url: url)
    } catch {
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  func activate() async throws {
    try Data().write(to: directory.appendingPathComponent("activate"))
    try await waitForWebPreview {
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path)
    }
  }

  func close() {
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    try? FileManager.default.removeItem(at: directory)
  }
}
