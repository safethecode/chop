import Darwin
import Foundation

/// Owns one clone and its process group. Cancellation cannot affect an existing destination.
public final class GitCloneJob: @unchecked Sendable {
  private let lock = NSLock()
  private var processID: pid_t = 0
  private var cancelled = false
  private var published = false

  public init() {}

  public func clone(repository: GitHubRepository, parent: URL, name: String) async throws -> URL {
    try await clone(source: repository.cloneAddress, parent: parent, name: name)
  }

  // Local source support stays internal for real, network-independent clone/cancellation tests.
  func clone(source: String, parent: URL, name: String) async throws -> URL {
    let worker = Task.detached(priority: .userInitiated) {
      try self.performClone(source: source, parent: parent, name: name)
    }
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      self.cancel()
    }
  }

  @discardableResult
  public func cancel() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !published else { return false }
    cancelled = true
    // git, ssh and pack helpers share a group created exclusively for this job.
    if processID > 0 { kill(-processID, SIGKILL) }
    return true
  }

  private func checkCancellation() throws {
    lock.lock()
    defer { lock.unlock() }
    if cancelled { throw CancellationError() }
  }

  private func performClone(source: String, parent: URL, name: String) throws -> URL {
    try GitCloneError.validateFolderName(name)
    guard parent.isFileURL else { throw GitCloneError.invalidParent }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw GitCloneError.invalidParent }
    let destination = parent.appendingPathComponent(name, isDirectory: true)
    var entry = stat()
    guard lstat(destination.path, &entry) != 0 else { throw GitCloneError.destinationExists }
    try checkCancellation()
    let staging = parent.appendingPathComponent(
      ".chop-clone-\(UUID().uuidString)", isDirectory: true)
    guard mkdir(staging.path, 0o700) == 0 else { throw GitCloneError.invalidParent }
    defer { try? FileManager.default.removeItem(at: staging) }
    try runGit(arguments: ["clone", "--no-recurse-submodules", "--", source, staging.path])

    lock.lock()
    defer { lock.unlock() }
    guard !cancelled else { throw CancellationError() }
    // Atomic, same-filesystem publication; never replace an item created during the download.
    guard renamex_np(staging.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
      if errno == EEXIST || errno == ENOTEMPTY { throw GitCloneError.destinationExists }
      throw GitCloneError.invalidParent
    }
    published = true
    return destination
  }

  private func runGit(arguments: [String]) throws {
    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    guard posix_spawn_file_actions_init(&actions) == 0 else { throw GitCloneError.unavailableGit }
    defer { posix_spawn_file_actions_destroy(&actions) }
    guard posix_spawnattr_init(&attributes) == 0 else { throw GitCloneError.unavailableGit }
    defer { posix_spawnattr_destroy(&attributes) }
    for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
      guard posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", O_RDWR, 0) == 0
      else { throw GitCloneError.unavailableGit }
    }
    guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
      posix_spawnattr_setpgroup(&attributes, 0) == 0
    else { throw GitCloneError.unavailableGit }
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_ASKPASS"] = "/usr/bin/false"
    environment["SSH_ASKPASS"] = "/usr/bin/false"
    environment["GIT_SSH_COMMAND"] = "/usr/bin/ssh -oBatchMode=yes -oStrictHostKeyChecking=yes"
    var argv = (["/usr/bin/git"] + arguments).map { strdup($0) } + [nil]
    var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
      for value in argv { free(value) }
      for value in envp { free(value) }
    }
    lock.lock()
    if cancelled {
      lock.unlock()
      throw CancellationError()
    }
    var child: pid_t = 0
    let result = posix_spawn(&child, "/usr/bin/git", &actions, &attributes, &argv, &envp)
    if result == 0 { processID = child }
    lock.unlock()
    guard result == 0 else { throw GitCloneError.unavailableGit }

    // Leave the leader unreaped until cancellation can no longer signal a recycled PID/group.
    var info = siginfo_t()
    var waited: Int32
    repeat {
      waited = waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT)
    } while waited != 0 && errno == EINTR
    lock.lock()
    defer { lock.unlock() }
    var status: Int32 = 0
    while waitpid(child, &status, 0) < 0 && errno == EINTR {}
    processID = 0
    guard !cancelled else { throw CancellationError() }
    guard waited == 0, status == 0 else { throw GitCloneError.failed }
  }
}
