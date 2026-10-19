import Foundation

public struct WorkspaceWindowSnapshot: Codable, Equatable, Sendable {
  public let id: UUID
  public let projectDirectory: String
  public let workspace: WorkspaceSnapshot

  public init(id: UUID, projectDirectory: String, workspace: WorkspaceSnapshot) {
    self.id = id
    self.projectDirectory = projectDirectory
    self.workspace = workspace
  }
}

/// One atomic document keeps all open windows, including the active window, consistent.
public struct ApplicationSnapshot: Codable, Equatable, Sendable {
  public var version = 2
  public let windows: [WorkspaceWindowSnapshot]
  public let focusedWindowID: UUID?

  public init(windows: [WorkspaceWindowSnapshot], focusedWindowID: UUID? = nil) {
    self.windows = windows
    self.focusedWindowID = focusedWindowID
  }

  public func validate() throws {
    guard version == 2 else { throw SnapshotError.unsupportedVersion }
    let ids = windows.map(\.id)
    guard Set(ids).count == ids.count,
      focusedWindowID == nil || ids.contains(focusedWindowID!)
    else { throw SnapshotError.invalid }
    for window in windows {
      try window.workspace.validate()
      let path = window.projectDirectory
      guard path.hasPrefix("/"), path.utf8.count <= 4096, !path.contains("\0") else {
        throw SnapshotError.invalid
      }
    }
  }
}

public struct ApplicationSessionLoadResult: Sendable {
  public let snapshot: ApplicationSnapshot?
  public let recoveredFile: URL?
  public let migratedLegacyWorkspace: Bool
}
