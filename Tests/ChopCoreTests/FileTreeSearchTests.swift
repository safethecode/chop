import Foundation
import Testing

@testable import ChopCore

@Test func fileSearchFindsNestedNamesWithoutEnteringHiddenPackagesOrSymlinkLoops() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for name in ["folder2", "folder10", ".hidden", "Bundle.app"] {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(name), withIntermediateDirectories: true)
  }
  for path in [
    "README.md", "folder2/Readme.KO.md", "folder10/보고서.md", ".hidden/readme.txt",
    "Bundle.app/readme.txt", "folder2/file2.txt", "folder2/file10.txt",
  ] {
    try Data().write(to: root.appendingPathComponent(path))
  }
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent("readme-link"),
    withDestinationURL: root.appendingPathComponent("folder2"))
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent("folder2/loop"), withDestinationURL: root)
  let result = try await FileTreeSearch.search(at: root, matching: "  readme  ")
  #expect(Set(result.entries.map(\.name)) == ["README.md", "Readme.KO.md", "readme-link"])
  #expect(
    Set(result.matches.map(\.relativePath)) == ["README.md", "folder2/Readme.KO.md", "readme-link"])
  #expect(!result.isTruncated && result.skippedDirectories == 0)
  #expect(result.entries.first { $0.name == "readme-link" }?.isDirectory == false)
  let korean = try await FileTreeSearch.search(at: root, matching: "보고서")
  #expect(korean.entries.count == 1)
  let natural = try await FileTreeSearch.search(at: root, matching: "file")
  #expect(natural.entries.map(\.name) == ["file2.txt", "file10.txt"])
}

@Test func fileSearchReportsRealTruncationPartialReadsAndRootFailure() async throws {
  let root = URL(fileURLWithPath: "/search")
  let entries = (1...4).map {
    FileTreeEntry(
      url: root.appendingPathComponent("file\($0)"), name: "file\($0)", isDirectory: false)
  }
  let limited = try await FileTreeSearch.search(at: root, matching: "file", limit: 3) { _ in entries
  }
  #expect(limited.entries.count == 3 && limited.isTruncated)
  let exact = try await FileTreeSearch.search(at: root, matching: "file", limit: 4) { _ in entries }
  #expect(exact.entries.count == 4 && !exact.isTruncated)
  let localized: FileTreeSearch.Reader = { _ in
    [FileTreeEntry(url: root.appendingPathComponent("Documents"), name: "문서", isDirectory: false)]
  }
  for query in ["Documents", "문서"] {
    let result = try await FileTreeSearch.search(at: root, matching: query, reader: localized)
    #expect(result.matches.map(\.relativePath) == ["Documents"])
  }
  let partial = try await FileTreeSearch.search(at: root, matching: "file") { url in
    guard url == root else { throw CocoaError(.fileReadNoPermission) }
    return entries + [
      FileTreeEntry(url: root.appendingPathComponent("denied"), name: "denied", isDirectory: true)
    ]
  }
  #expect(partial.entries.count == 4 && partial.skippedDirectories == 1)
  await #expect(throws: CocoaError.self) {
    try await FileTreeSearch.search(at: root, matching: "file") { _ in
      throw CocoaError(.fileReadNoSuchFile)
    }
  }
}

@Test func fileSearchCancelsAnInProgressReadAndDoesNotReadForAnEmptyQuery() async throws {
  let root = URL(fileURLWithPath: "/search")
  let empty = try await FileTreeSearch.search(at: root, matching: " \n ") { _ in
    Issue.record("Empty search must not read a directory")
    return []
  }
  #expect(empty.entries.isEmpty && !empty.isTruncated)
  let started = AsyncStream<Void>.makeStream()
  let task = Task {
    try await FileTreeSearch.search(at: root, matching: "file") { _ in
      started.continuation.yield(())
      try await Task.sleep(for: .seconds(10))
      return []
    }
  }
  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
  started.continuation.finish()
}

@Test func fileSearchReusesDirectoryReadsAcrossQueriesAndBoundsItsCache() async throws {
  let root = URL(fileURLWithPath: "/cached-search")
  let reader = CountingSearchReader()
  let cache = FileTreeSearchCache { try await reader.entries(at: $0) }
  for query in ["file", "file1", "no-match", "file2"] {
    let result = try await FileTreeSearch.search(at: root, matching: query) {
      try await cache.entries(at: $0)
    }
    #expect(result.entries.count == (query == "no-match" ? 0 : query == "file" ? 2 : 1))
  }
  #expect(await reader.calls == 2, "Editing queries should not re-read the filesystem")
  let bounded = FileTreeSearchCache(maximumEntries: 1) { try await reader.entries(at: $0) }
  _ = try await bounded.entries(at: root)
  _ = try await bounded.entries(at: root.appendingPathComponent("folder"))
  _ = try await bounded.entries(at: root)
  #expect(await reader.calls == 5, "Entries exceeding the memory budget are not cached")
  let expired = FileTreeSearchCache(lifetime: .zero) { try await reader.entries(at: $0) }
  _ = try await expired.entries(at: root)
  _ = try await expired.entries(at: root)
  #expect(await reader.calls == 7)
}

@Test func fileSearchPublishesMatchesBeforeASlowSubdirectoryFinishes() async throws {
  let root = URL(fileURLWithPath: "/progress-search")
  let progress = CountingSearchReader()
  let result = try await FileTreeSearch.search(
    at: root, matching: "file",
    reader: { url in
      if url == root {
        return [
          FileTreeEntry(
            url: root.appendingPathComponent("file1"), name: "file1", isDirectory: false),
          FileTreeEntry(
            url: root.appendingPathComponent("folder"), name: "folder", isDirectory: true),
        ]
      }
      #expect(await progress.calls == 1, "The first result must appear before the next read")
      return []
    },
    onProgress: { result in
      #expect(result.matches.map(\.relativePath) == ["file1"])
      _ = try? await progress.entries(at: root)
    })
  #expect(result.matches.count == 1)
}

private actor CountingSearchReader {
  private(set) var calls = 0

  func entries(at url: URL) throws -> [FileTreeEntry] {
    calls += 1
    if url.lastPathComponent == "folder" {
      return [
        FileTreeEntry(url: url.appendingPathComponent("file2"), name: "file2", isDirectory: false)
      ]
    }
    return [
      FileTreeEntry(url: url.appendingPathComponent("file1"), name: "file1", isDirectory: false),
      FileTreeEntry(url: url.appendingPathComponent("folder"), name: "folder", isDirectory: true),
    ]
  }
}
