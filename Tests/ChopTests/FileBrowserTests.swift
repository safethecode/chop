import AppKit
import ChopCore
import Testing

@testable import Chop

@MainActor
@Test func fileBrowserControlsAndRowsRemainClickableAtMinimumWidth() async throws {
  _ = NSApplication.shared
  let suite = "chop-file-browser-hit-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let root = URL(fileURLWithPath: "/chop-preview")
  let browser = FileBrowserView(initialURL: root, defaults: defaults) { url in
    [
      FileTreeEntry(
        url: url.appendingPathComponent("README.md"), name: "README.md", isDirectory: false)
    ]
  }
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.contentView = browser
  defer { window.orderOut(nil) }
  try await waitForFileBrowser { !browser.isLoading }
  func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
  }
  for mode in [AppearanceMode.light, .dark] {
    browser.applyAppearance(mode)
    window.layoutIfNeeded()
    browser.layoutSubtreeIfNeeded()
    let views = descendants(of: browser)
    let buttons = views.compactMap { $0 as? NSButton }.filter {
      ["홈", "다운로드", "문서"].contains($0.title)
    }
    #expect(buttons.count == 3)
    let firstButton = try #require(buttons.first)
    let rowCenter = browser.convert(firstButton.bounds, from: firstButton).midY
    for button in buttons {
      let rect = browser.convert(button.bounds, from: button)
      #expect(rect.width > 0 && rect.height > 0)
      #expect(browser.bounds.contains(rect))
      #expect(rect.width >= button.intrinsicContentSize.width - 0.5)
      #expect(abs(rect.midY - rowCenter) <= 0.5)
      let point = button.convert(
        NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: browser.superview)
      #expect(browser.hitTest(point) === button)
    }
    let outline = try #require(views.compactMap { $0 as? NSOutlineView }.first)
    let row = outline.rect(ofRow: 0)
    let point = outline.convert(NSPoint(x: row.midX, y: row.midY), to: browser.superview)
    let hit = try #require(browser.hitTest(point))
    #expect(hit === outline || hit.isDescendant(of: outline))
  }
}

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
