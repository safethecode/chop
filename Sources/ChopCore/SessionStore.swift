import Foundation

public struct SessionLoadResult: Sendable {
  public let snapshot: WorkspaceSnapshot?
  public let recoveredFile: URL?
}

/// Stores metadata only. A snapshot has no command, environment or terminal contents.
public struct SessionStore: Sendable {
  public static let maximumBytes = 256 * 1024
  public let fileURL: URL

  public init(fileURL: URL) { self.fileURL = fileURL }

  public func load() throws -> SessionLoadResult {
    let manager = FileManager.default
    guard manager.fileExists(atPath: fileURL.path) else {
      return SessionLoadResult(snapshot: nil, recoveredFile: nil)
    }
    let size = try manager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
    if size?.intValue ?? 0 > Self.maximumBytes { return try quarantine() }
    let data = try Data(contentsOf: fileURL)
    do {
      let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
      try snapshot.validate()
      return SessionLoadResult(snapshot: snapshot, recoveredFile: nil)
    } catch {
      return try quarantine()
    }
  }

  private func quarantine() throws -> SessionLoadResult {
    let backup = fileURL.deletingLastPathComponent().appendingPathComponent(
      "session-unreadable-\(UUID().uuidString).json")
    try FileManager.default.moveItem(at: fileURL, to: backup)
    return SessionLoadResult(snapshot: nil, recoveredFile: backup)
  }

  public func save(_ snapshot: WorkspaceSnapshot) throws {
    try snapshot.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    guard data.count <= Self.maximumBytes else { throw SnapshotError.tooLarge }
    let manager = FileManager.default
    try manager.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try data.write(to: fileURL, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}
