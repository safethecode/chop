import AppKit
import ChopCore
import Testing

@testable import Chop

@MainActor
@Test func fileBrowserRemembersSuccessfulRootsAndRecoversAfterFailure() async throws {
  _ = NSApplication.shared
  let suite = "chop-file-browser-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let browser = FileBrowserView(initialURL: root, defaults: defaults)
  try await waitForFileBrowser { !browser.isLoading }
  #expect(browser.loadError == nil)
  #expect(defaults.string(forKey: "fileTreeRootPath") == root.path)
  browser.navigate(to: root.appendingPathComponent("missing"))
  try await waitForFileBrowser { !browser.isLoading }
  #expect(browser.loadError != nil)
  #expect(defaults.string(forKey: "fileTreeRootPath") == root.path)
  browser.navigate(to: root)
  try await waitForFileBrowser { !browser.isLoading }
  #expect(browser.loadError == nil)
  let restored = FileBrowserView(
    initialURL: root.appendingPathComponent("unused"), defaults: defaults)
  try await waitForFileBrowser { !restored.isLoading }
  #expect(restored.rootURL.path == root.path && restored.loadError == nil)
}

@MainActor
@Test func fileBrowserIgnoresLateResultsFromPreviousNavigation() async throws {
  _ = NSApplication.shared
  let suite = "chop-file-browser-race-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let reader = SuspendedFolderReader()
  let slow = URL(fileURLWithPath: "/slow")
  let fast = URL(fileURLWithPath: "/fast")
  let browser = FileBrowserView(initialURL: slow, defaults: defaults) { url in
    try await reader.entries(at: url)
  }
  try await waitForFileBrowser { await reader.isWaiting }
  browser.navigate(to: fast)
  try await waitForFileBrowser { !browser.isLoading }
  #expect(defaults.string(forKey: "fileTreeRootPath") == fast.path)
  await reader.finish()
  try await waitForFileBrowser { await reader.didReturn }
  await Task.yield()
  #expect(browser.rootURL == fast)
  #expect(defaults.string(forKey: "fileTreeRootPath") == fast.path)
  #expect(browser.loadError == nil && !browser.isLoading)
}

private actor SuspendedFolderReader {
  private var continuation: CheckedContinuation<[FileTreeEntry], any Error>?
  private(set) var isWaiting = false
  private(set) var didReturn = false

  func entries(at url: URL) async throws -> [FileTreeEntry] {
    if url.path != "/slow" { return [] }
    let result: [FileTreeEntry] = try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      isWaiting = true
    }
    didReturn = true
    return result
  }

  func finish() { continuation?.resume(returning: []) }
}

@MainActor
private func waitForFileBrowser(_ condition: () async -> Bool) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(5))
  while !(await condition()) {
    guard clock.now < deadline else { throw CocoaError(.fileReadUnknown) }
    try await Task.sleep(for: .milliseconds(20))
  }
}
