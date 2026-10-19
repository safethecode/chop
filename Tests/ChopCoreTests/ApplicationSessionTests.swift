import Foundation
import Testing

@testable import ChopCore

private func projectWorkspace(_ path: String) -> WorkspaceSnapshot {
  let id = UUID()
  return WorkspaceSnapshot(
    layout: .pane(id),
    panes: [PaneSnapshot(id: id, name: "작업", workingDirectory: path, wasRunning: true)],
    focusedID: id)
}

@Test func applicationSessionMigratesLegacyWithoutChangingItAndRoundTripsWindows() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(fileURL: directory.appendingPathComponent("session.json"))
  let legacy = projectWorkspace("/project-a")
  try store.save(legacy)
  let original = try Data(contentsOf: store.fileURL)
  let loaded = try store.loadApplication()
  let migrated = try #require(loaded.snapshot)
  #expect(loaded.migratedLegacyWorkspace && loaded.recoveredFile == nil)
  #expect(migrated.windows.count == 1 && migrated.windows[0].workspace == legacy)
  #expect(migrated.windows[0].projectDirectory == "/project-a")
  #expect(try Data(contentsOf: store.fileURL) == original)
  let second = WorkspaceWindowSnapshot(
    id: UUID(), projectDirectory: "/project-b", workspace: projectWorkspace("/project-b"))
  let combined = ApplicationSnapshot(
    windows: migrated.windows + [second], focusedWindowID: second.id)
  try store.save(combined)
  let restored = try store.loadApplication()
  #expect(restored.snapshot == combined && !restored.migratedLegacyWorkspace)
  try store.save(ApplicationSnapshot(windows: []))
  #expect(try store.loadApplication().snapshot?.windows.isEmpty == true)
}

@Test func applicationSessionsRejectInvalidWindowsAndPreserveTheLastGoodFile() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = SessionStore(fileURL: directory.appendingPathComponent("session.json"))
  let window = WorkspaceWindowSnapshot(
    id: UUID(), projectDirectory: "/project", workspace: projectWorkspace("/project"))
  let good = ApplicationSnapshot(windows: [window], focusedWindowID: window.id)
  try store.save(good)
  let bytes = try Data(contentsOf: store.fileURL)
  for invalid in [
    ApplicationSnapshot(windows: [window, window]),
    ApplicationSnapshot(windows: [window], focusedWindowID: UUID()),
    ApplicationSnapshot(windows: [
      WorkspaceWindowSnapshot(id: UUID(), projectDirectory: "relative", workspace: window.workspace)
    ]),
  ] {
    #expect(throws: SnapshotError.self) { try store.save(invalid) }
    #expect(try Data(contentsOf: store.fileURL) == bytes)
  }
  let oversized = ApplicationSnapshot(
    windows: (0..<1100).map { _ in
      WorkspaceWindowSnapshot(
        id: UUID(), projectDirectory: "/" + String(repeating: "a", count: 4095),
        workspace: window.workspace)
    })
  #expect(throws: SnapshotError.self) { try store.save(oversized) }
  #expect(try Data(contentsOf: store.fileURL) == bytes)
  let broken = Data("{\"version\":999,\"windows\":[]}".utf8)
  try broken.write(to: store.fileURL)
  let recovered = try store.loadApplication()
  #expect(recovered.snapshot == nil)
  #expect(try Data(contentsOf: #require(recovered.recoveredFile)) == broken)
}
