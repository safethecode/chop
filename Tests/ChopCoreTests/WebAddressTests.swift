import Foundation
import Testing

@testable import ChopCore

@Test func webAddressesNormalizeLocalAndHTTPSAddressesWithoutExecutableSchemes() {
  let addresses = [
    "localhost:3000": "http://localhost:3000/",
    "127.0.0.1:8080/page?q=한글": "http://127.0.0.1:8080/page?q=%ED%95%9C%EA%B8%80",
    "[::1]:4000": "http://[::1]:4000/",
    "0.0.0.0:5000": "http://localhost:5000/",
    "example.com/path": "https://example.com/path",
    "HTTPS://example.com": "https://example.com/",
  ]
  for (input, expected) in addresses {
    #expect(WebAddress.parse(input)?.absoluteString == expected)
  }
  for input in [
    "", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,hello", "mailto:a@example.com",
    "https://user:password@example.com/", "http://localhost:0", "http://localhost:65536",
    "https://example.com/\ncommand", String(repeating: "a", count: 4097),
  ] { #expect(WebAddress.parse(input) == nil) }
}

@Test func webPaneSnapshotsPreserveOldTerminalSavesAndRejectInvalidWebState() throws {
  let id = UUID()
  let terminal = PaneSnapshot(id: id, name: "터미널 1", workingDirectory: "/tmp", wasRunning: true)
  let old = WorkspaceSnapshot(layout: .pane(id), panes: [terminal], focusedID: id)
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  let oldData = try encoder.encode(old)
  #expect(!String(decoding: oldData, as: UTF8.self).contains("contentKind"))
  #expect(try decoder.decode(WorkspaceSnapshot.self, from: oldData) == old)
  for address in [nil, "http://localhost:3000/page"] as [String?] {
    let web = PaneSnapshot(
      id: id, name: "웹 1", workingDirectory: "/tmp", wasRunning: false,
      contentKind: .web, webURL: address)
    let saved = WorkspaceSnapshot(layout: .pane(id), panes: [web], focusedID: id)
    try saved.validate()
    #expect(try decoder.decode(WorkspaceSnapshot.self, from: encoder.encode(saved)) == saved)
  }
  for (kind, address, running) in [
    (PaneContentKind.web, "file:///tmp/secret", false),
    (.web, "https://example.com", true), (.terminal, "http://localhost:3000", false),
  ] {
    let invalid = PaneSnapshot(
      id: id, name: "웹 1", workingDirectory: "/tmp", wasRunning: running,
      contentKind: kind, webURL: address)
    #expect(throws: SnapshotError.self) {
      try WorkspaceSnapshot(layout: .pane(id), panes: [invalid], focusedID: id).validate()
    }
  }
}
