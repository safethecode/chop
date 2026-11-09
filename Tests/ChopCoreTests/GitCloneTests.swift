import Foundation
import Testing

@testable import ChopCore

@Test func gitHubRepositoryAcceptsCloneAndBrowserAddressesOnly() throws {
  for value in [
    "octocat/Hello-World", "github.com/octocat/Hello-World",
    "https://github.com/octocat/Hello-World/",
    "https://github.com/octocat/Hello-World.git?tab=readme-ov-file#readme",
  ] {
    let repository = try GitHubRepository(value)
    #expect(repository.name == "Hello-World")
    #expect(repository.cloneAddress == "https://github.com/octocat/Hello-World.git")
  }
  for value in [
    "git@github.com:octocat/Hello-World.git", "ssh://git@github.com/octocat/Hello-World",
  ] {
    #expect(try GitHubRepository(value).cloneAddress == "git@github.com:octocat/Hello-World.git")
  }
  for value in [
    "", "--upload-pack=evil", "/tmp/repo", "file:///tmp/repo", "http://github.com/owner/repo",
    "https://github.com.evil.example/owner/repo", "https://token@github.com/owner/repo",
    "https://github.com:444/owner/repo", "https://github.com/owner/repo/tree/main",
    "git@other.example:owner/repo", "owner/..", "owner/repo\n--argument",
  ] {
    #expect(throws: GitCloneError.invalidRepository) { try GitHubRepository(value) }
  }
  for name in [
    "", ".", "..", "../other", "folder/name", "folder:name", "a\nb",
    String(repeating: "가", count: 86),
  ] {
    #expect(throws: GitCloneError.invalidFolderName) { try GitCloneError.validateFolderName(name) }
  }
  try GitCloneError.validateFolderName("한글 project 🪴")
}

@Test func gitClonePublishesARepositoryAndPreservesExistingItems() async throws {
  let root = try makeCloneTestDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source")
  try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
  try runFixtureGit(["init", source.path])
  try "fixture\n".write(
    to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
  try runFixtureGit(["-C", source.path, "add", "README.md"])
  try runFixtureGit([
    "-C", source.path, "-c", "user.name=Chop Test", "-c", "user.email=chop@example.invalid",
    "commit", "--no-gpg-sign", "-m", "fixture",
  ])
  let result = try await GitCloneJob().clone(source: source.path, parent: root, name: "새 프로젝트")
  #expect(
    try String(contentsOf: result.appendingPathComponent("README.md"), encoding: .utf8)
      == "fixture\n")
  #expect(FileManager.default.fileExists(atPath: result.appendingPathComponent(".git").path))
  do {
    _ = try await GitCloneJob().clone(source: source.path, parent: root, name: "새 프로젝트")
    Issue.record("An existing destination must not be replaced")
  } catch { #expect(error as? GitCloneError == .destinationExists) }
  let link = root.appendingPathComponent("broken-link")
  try FileManager.default.createSymbolicLink(
    at: link, withDestinationURL: root.appendingPathComponent("missing"))
  do {
    _ = try await GitCloneJob().clone(source: source.path, parent: root, name: "broken-link")
    Issue.record("A dangling symlink must not be replaced")
  } catch { #expect(error as? GitCloneError == .destinationExists) }
  do {
    _ = try await GitCloneJob().clone(
      source: root.appendingPathComponent("missing").path, parent: root, name: "failed")
    Issue.record("A missing source must fail")
  } catch { #expect(error as? GitCloneError == .failed) }
  #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("failed").path))
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy {
      !$0.hasPrefix(".chop-clone-")
    })
}

@Test func cancellingGitCloneStopsTheTransferAndRemovesOnlyItsStagingFolder() async throws {
  let root = try makeCloneTestDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let marker = root.appendingPathComponent("port")
  let connected = root.appendingPathComponent("connected")
  let disconnected = root.appendingPathComponent("disconnected")
  let server = Process()
  server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
  server.arguments = [
    "-c",
    """
    import socket,sys,pathlib
    s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen()
    pathlib.Path(sys.argv[1]).write_text(str(s.getsockname()[1]))
    c,_=s.accept(); c.recv(4096); pathlib.Path(sys.argv[2]).touch()
    while c.recv(4096): pass
    pathlib.Path(sys.argv[3]).touch()
    """, marker.path, connected.path, disconnected.path,
  ]
  try server.run()
  defer {
    if server.isRunning {
      server.terminate()
      server.waitUntilExit()
    }
  }
  try await waitForCloneFixture {
    (try? String(contentsOf: marker, encoding: .utf8)).flatMap(UInt16.init) != nil
  }
  let port = try String(contentsOf: marker, encoding: .utf8)
  let job = GitCloneJob()
  let task = Task {
    try await job.clone(source: "git://127.0.0.1:\(port)/fixture", parent: root, name: "cancelled")
  }
  defer {
    job.cancel()
    task.cancel()
  }
  try await waitForCloneFixture { FileManager.default.fileExists(atPath: connected.path) }
  try "keep".write(to: root.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
  task.cancel()
  do {
    _ = try await task.value
    Issue.record("Cancelled clone must not publish a repository")
  } catch { #expect(error is CancellationError) }
  try await waitForCloneFixture { FileManager.default.fileExists(atPath: disconnected.path) }
  #expect(
    try String(contentsOf: root.appendingPathComponent("keep.txt"), encoding: .utf8) == "keep")
  #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled").path))
  #expect(
    try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy {
      !$0.hasPrefix(".chop-clone-")
    })
}

private func makeCloneTestDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "chop-clone-test-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  return root
}

private func runFixtureGit(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments =
    ["-c", "core.hooksPath=/dev/null", "-c", "init.defaultBranch=main"] + arguments
  process.environment = ProcessInfo.processInfo.environment.merging([
    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
  ]) { _, value in value }
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
}

private func waitForCloneFixture(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !condition(), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  try #require(condition())
}
