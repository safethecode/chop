import Foundation

/// Reuse directory reads while editing a query, with bounded storage and a short freshness window.
public actor FileTreeSearchCache {
  private let reader: FileTreeSearch.Reader
  private let maximumEntries: Int
  private let lifetime: Duration
  private var entryCount = 0
  private var directories: [URL: (entries: [FileTreeEntry], readAt: ContinuousClock.Instant)] = [:]

  public init(
    maximumEntries: Int = 100_000, lifetime: Duration = .seconds(10),
    reader: @escaping FileTreeSearch.Reader = { try FileTree.entries(at: $0) }
  ) {
    self.reader = reader
    self.maximumEntries = maximumEntries
    self.lifetime = lifetime
  }

  public func entries(at directory: URL) async throws -> [FileTreeEntry] {
    try Task.checkCancellation()
    let key = directory.standardizedFileURL
    if let cached = directories[key] {
      if cached.readAt.duration(to: .now) < lifetime { return cached.entries }
      entryCount -= max(1, cached.entries.count)
      directories.removeValue(forKey: key)
    }
    let entries = try await reader(directory)
    // A cancelled, slow read must not replace a newer query's cached contents.
    try Task.checkCancellation()
    let cost = max(1, entries.count)
    if directories[key] == nil, entryCount + cost <= maximumEntries {
      directories[key] = (entries, .now)
      entryCount += cost
    }
    return entries
  }
}
