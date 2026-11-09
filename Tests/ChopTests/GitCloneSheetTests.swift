import AppKit
import ChopCore
import Testing

@testable import Chop

private actor CloneSheetFixture {
  var attempts = 0
  func clone(parent: URL, name: String) async throws -> URL {
    attempts += 1
    try await Task.sleep(for: .milliseconds(30))
    if attempts == 1 { throw GitCloneError.failed }
    return parent.appendingPathComponent(name)
  }
}

@MainActor
@Test func cloneSheetPreservesInputsThroughFailureAndOpensOnlyAfterRetry() async throws {
  _ = NSApplication.shared
  let fixture = CloneSheetFixture()
  let parent = FileManager.default.temporaryDirectory
  let sheet = GitCloneSheet(parentDirectory: parent) { _, parent, name, _ in
    try await fixture.clone(parent: parent, name: name)
  }
  var results: [URL?] = []
  sheet.onFinish = { results.append($0) }
  sheet.repositoryField.stringValue = "octocat/Hello-World"
  sheet.controlTextDidChange(
    Notification(name: NSControl.textDidChangeNotification, object: sheet.repositoryField))
  #expect(sheet.nameField.stringValue == "Hello-World")
  sheet.nameField.stringValue = "한글 프로젝트 🪴"
  sheet.repositoryField.stringValue = "owner/another-repository"
  sheet.controlTextDidChange(
    Notification(name: NSControl.textDidChangeNotification, object: sheet.repositoryField))
  #expect(sheet.nameField.stringValue == "한글 프로젝트 🪴")
  #expect(sheet.cloneButton.isEnabled)
  sheet.startClone()
  sheet.startClone()
  #expect(sheet.isCloning && !sheet.cloneButton.isEnabled && !sheet.repositoryField.isEnabled)
  await sheet.waitForCompletion()
  #expect(await fixture.attempts == 1)
  #expect(results.isEmpty && !sheet.isCloning && sheet.cloneButton.isEnabled)
  #expect(sheet.repositoryField.stringValue == "owner/another-repository")
  #expect(sheet.nameField.stringValue == "한글 프로젝트 🪴")
  #expect(sheet.status.stringValue.contains("클론하지 못했어요"))
  sheet.startClone()
  await sheet.waitForCompletion()
  #expect(await fixture.attempts == 2)
  #expect(results == [parent.appendingPathComponent("한글 프로젝트 🪴")])
}

@MainActor
@Test func cloneSheetCancellationWaitsForWorkAndDoesNotOpenAProject() async throws {
  _ = NSApplication.shared
  let sheet = GitCloneSheet(parentDirectory: FileManager.default.temporaryDirectory) { _, _, _, _ in
    try await Task.sleep(for: .seconds(30))
    throw GitCloneError.failed
  }
  var finished = false
  sheet.onFinish = { url in
    finished = true
    #expect(url == nil)
  }
  sheet.repositoryField.stringValue = "octocat/Hello-World"
  sheet.controlTextDidChange(
    Notification(name: NSControl.textDidChangeNotification, object: sheet.repositoryField))
  sheet.startClone()
  sheet.cancel()
  #expect(!finished && !sheet.cancelButton.isEnabled)
  await sheet.waitForCompletion()
  #expect(finished && !sheet.isCloning)
}
