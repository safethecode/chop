import Foundation

public struct FileTreeSearchMatch: Equatable, Sendable {
  public let entry: FileTreeEntry
  /// Built while walking, so canonicalized /tmp or /var URLs do not lose their ancestry.
  public let relativePath: String
}

public struct FileTreeSearchResult: Equatable, Sendable {
  public let matches: [FileTreeSearchMatch]
  public var entries: [FileTreeEntry] { matches.map(\.entry) }
  public let isTruncated: Bool
  public let skippedDirectories: Int
}

public enum FileTreeSearch {
  public typealias Reader = @Sendable (URL) async throws -> [FileTreeEntry]
  public typealias Progress = @Sendable (FileTreeSearchResult) async -> Void

  /// Searches visible names below a root, using the tree's package and symlink leaf rules.
  public static func search(
    at directory: URL, matching query: String, limit: Int = 500,
    reader: Reader = { try FileTree.entries(at: $0) }, onProgress: Progress? = nil
  ) async throws -> FileTreeSearchResult {
    precondition(limit > 0)
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var matches: [FileTreeSearchMatch] = []
    var skipped = 0
    func result(truncated: Bool = false) -> FileTreeSearchResult {
      FileTreeSearchResult(
        matches: Array(matches.prefix(limit)).sorted {
          if $0.entry.isDirectory != $1.entry.isDirectory { return $0.entry.isDirectory }
          return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }, isTruncated: truncated, skippedDirectories: skipped)
    }
    try Task.checkCancellation()
    guard !query.isEmpty else { return result() }
    let root = directory.standardizedFileURL
    var pending = [(url: root, path: "")]
    var visited = Set<URL>()
    var nextProgress = ContinuousClock.now
    var reportedCount = 0
    while let (folder, parentPath) = pending.popLast() {
      try Task.checkCancellation()
      guard visited.insert(folder.standardizedFileURL).inserted else { continue }
      let entries: [FileTreeEntry]
      do {
        entries = try await reader(folder)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try Task.checkCancellation()
        if folder == root { throw error }
        skipped += 1
        continue
      }
      var children: [(url: URL, path: String)] = []
      for entry in entries {
        try Task.checkCancellation()
        let path =
          parentPath.isEmpty
          ? entry.url.lastPathComponent : parentPath + "/" + entry.url.lastPathComponent
        if entry.name.localizedStandardContains(query)
          || entry.url.lastPathComponent.localizedStandardContains(query)
        {
          matches.append(FileTreeSearchMatch(entry: entry, relativePath: path))
          if matches.count > limit { return result(truncated: true) }
        }
        if entry.isDirectory { children.append((entry.url, path)) }
      }
      pending.append(contentsOf: children.reversed())
      if let onProgress, matches.count != reportedCount, ContinuousClock.now >= nextProgress {
        try Task.checkCancellation()
        await onProgress(result())
        reportedCount = matches.count
        nextProgress = .now.advanced(by: .milliseconds(75))
      }
    }
    return result()
  }
}
