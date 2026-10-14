import Foundation
import Testing

@testable import ChopCore

private func snapshot() -> WorkspaceSnapshot {
  let ids = (0..<4).map { _ in UUID() }
  return WorkspaceSnapshot(
    layout: .preset(.grid, ids: ids),
    panes: ids.enumerated().map {
      PaneSnapshot(
        id: $0.element, name: "터미널 \($0.offset + 1)", workingDirectory: "/tmp",
        wasRunning: $0.offset != 2)
    }, focusedID: ids[1])
}

@Test func sessionRoundTripsAndPreservesCorruptBytes() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-store-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(fileURL: directory.appendingPathComponent("session.json"))
  #expect(try store.load().snapshot == nil)
  let original = snapshot()
  try store.save(original)
  #expect(try store.load().snapshot == original)
  let permissions =
    try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions]
    as? NSNumber
  #expect(permissions?.intValue == 0o600)
  let corrupt = Data("{ broken session".utf8)
  try corrupt.write(to: store.fileURL)
  let recovered = try store.load()
  #expect(recovered.snapshot == nil)
  let backup = try #require(recovered.recoveredFile)
  #expect(try Data(contentsOf: backup) == corrupt)
  try store.save(original)
  #expect(
    try Data(contentsOf: backup) == corrupt, "Saving a new layout must preserve the unreadable file"
  )
}

@Test func unsafeSnapshotsAreRejectedWithoutOverwritingGoodData() throws {
  let good = snapshot()
  var unsupported = good
  unsupported.version = 2
  #expect(throws: SnapshotError.self) { try unsupported.validate() }
  let first = good.panes[0]
  let duplicate = WorkspaceSnapshot(
    layout: .pane(first.id), panes: [first, first], focusedID: first.id)
  #expect(throws: SnapshotError.self) { try duplicate.validate() }
  let invalidRatio = WorkspaceSnapshot(
    layout: .split(
      id: UUID(), axis: .horizontal, ratio: 0,
      first: .pane(good.panes[0].id), second: .pane(good.panes[1].id)),
    panes: Array(good.panes.prefix(2)), focusedID: first.id)
  #expect(throws: SnapshotError.self) { try invalidRatio.validate() }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-store-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(fileURL: directory.appendingPathComponent("session.json"))
  try store.save(good)
  #expect(throws: SnapshotError.self) { try store.save(duplicate) }
  #expect(try store.load().snapshot == good)
  try Data(repeating: 32, count: SessionStore.maximumBytes + 1).write(to: store.fileURL)
  #expect(try store.load().recoveredFile != nil)
}

@Test func snapshotsRejectInvalidReferencesPathsAndDeepTrees() throws {
  let good = snapshot()
  let first = good.panes[0]
  let badFocus = WorkspaceSnapshot(layout: .pane(first.id), panes: [first], focusedID: UUID())
  #expect(throws: SnapshotError.self) { try badFocus.validate() }
  let relative = PaneSnapshot(
    id: first.id, name: "터미널", workingDirectory: "../tmp", wasRunning: true)
  #expect(throws: SnapshotError.self) {
    try WorkspaceSnapshot(layout: .pane(first.id), panes: [relative], focusedID: first.id)
      .validate()
  }
  var deep: LayoutNode = .pane(first.id)
  for _ in 0..<18 {
    deep = .split(id: UUID(), axis: .horizontal, ratio: 0.5, first: deep, second: .pane(UUID()))
  }
  #expect(throws: SnapshotError.self) {
    try WorkspaceSnapshot(layout: deep, panes: [first], focusedID: first.id).validate()
  }
  let json = try #require(String(data: JSONEncoder().encode(good), encoding: .utf8))
  #expect(!json.contains("command"))
  #expect(!json.contains("environment"))
  #expect(!json.contains("contents"))
  var extra = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  extra["command"] = "printf SHOULD_NEVER_RUN"
  let decoded = try JSONDecoder().decode(
    WorkspaceSnapshot.self, from: JSONSerialization.data(withJSONObject: extra))
  #expect(decoded == good, "Unknown command fields must not become executable configuration")
}

@Test func unreadableLocationsAreReportedRatherThanOverwritten() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-store-\(UUID())")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let notDirectory = directory.appendingPathComponent("file")
  let original = Data("keep".utf8)
  try original.write(to: notDirectory)
  let store = SessionStore(fileURL: notDirectory.appendingPathComponent("session.json"))
  #expect(throws: (any Error).self) { try store.save(snapshot()) }
  #expect(try Data(contentsOf: notDirectory) == original)
}

@Test func tabbedPresentationRoundTripsAndLegacySessionsRemainReadable() throws {
  let legacy = snapshot()
  let decoder = JSONDecoder()
  let encoder = JSONEncoder()
  let legacyData = try encoder.encode(legacy)
  let fields = try #require(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
  #expect(fields["tabbed"] == nil)
  #expect(try decoder.decode(WorkspaceSnapshot.self, from: legacyData).tabbed == nil)
  let tabbed = WorkspaceSnapshot(
    layout: legacy.layout, panes: legacy.panes, focusedID: legacy.focusedID, tabbed: true)
  let restored = try decoder.decode(WorkspaceSnapshot.self, from: encoder.encode(tabbed))
  try restored.validate()
  #expect(restored == tabbed)
  #expect(restored.layout.paneIDs == legacy.layout.paneIDs)
}
