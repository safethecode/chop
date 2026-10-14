import Foundation

public struct PaneSnapshot: Codable, Equatable, Sendable {
  public let id: UUID
  public let name: String
  public let workingDirectory: String
  public let wasRunning: Bool

  public init(id: UUID, name: String, workingDirectory: String, wasRunning: Bool) {
    self.id = id
    self.name = name
    self.workingDirectory = workingDirectory
    self.wasRunning = wasRunning
  }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
  public var version: Int = 1
  public let layout: LayoutNode
  public let panes: [PaneSnapshot]
  public let focusedID: UUID

  public init(layout: LayoutNode, panes: [PaneSnapshot], focusedID: UUID) {
    self.layout = layout
    self.panes = panes
    self.focusedID = focusedID
  }

  public func validate() throws {
    guard version == 1 else { throw SnapshotError.unsupportedVersion }
    guard (1...16).contains(panes.count) else { throw SnapshotError.invalid }
    var identities = Set<UUID>()
    var leafIDs = [UUID]()
    func visit(_ node: LayoutNode, depth: Int) throws {
      guard depth <= 16 else { throw SnapshotError.invalid }
      switch node {
      case .pane(let id):
        guard identities.insert(id).inserted else { throw SnapshotError.invalid }
        leafIDs.append(id)
      case .split(let id, _, let ratio, let first, let second):
        guard identities.insert(id).inserted, ratio.isFinite, (0.05...0.95).contains(ratio) else {
          throw SnapshotError.invalid
        }
        try visit(first, depth: depth + 1)
        try visit(second, depth: depth + 1)
      }
    }
    try visit(layout, depth: 0)
    let paneIDs = panes.map(\.id)
    guard paneIDs.count == Set(paneIDs).count, Set(leafIDs) == Set(paneIDs),
      paneIDs.contains(focusedID)
    else { throw SnapshotError.invalid }
    for pane in panes {
      guard !pane.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        pane.name.count <= 64,
        !pane.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
        pane.workingDirectory.hasPrefix("/"), pane.workingDirectory.utf8.count <= 4096,
        !pane.workingDirectory.contains("\0")
      else { throw SnapshotError.invalid }
    }
  }
}

public enum SnapshotError: LocalizedError {
  case invalid, unsupportedVersion, tooLarge
  public var errorDescription: String? {
    switch self {
    case .invalid: return "저장된 레이아웃의 형식이 올바르지 않습니다."
    case .unsupportedVersion: return "이 버전에서 읽을 수 없는 레이아웃입니다."
    case .tooLarge: return "저장된 레이아웃 파일이 너무 큽니다."
    }
  }
}
