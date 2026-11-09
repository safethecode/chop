import Darwin
import Foundation

/// Owns one clone and its process group. Cancellation cannot affect an existing destination.
public final class GitCloneJob: @unchecked Sendable {
  private let lock = NSLock()
  private let inheritedEnvironment: [String: String]
  private var processID: pid_t = 0
  private var cancelled = false
  private var published = false

  public init() { inheritedEnvironment = ProcessInfo.processInfo.environment }

  init(environment: [String: String]) { inheritedEnvironment = environment }

  /// Downloads into a private staging directory, then publishes without replacing a destination.
  /// Retry after a failure is supported; each job is used by one operation at a time.
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

  /// Stops this job's process group. Returns false after publication has already completed.
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
    var environment = Self.cloneEnvironment(from: inheritedEnvironment)
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

  /// Git's repository-local environment must not redirect clone or fixture writes into a caller.
  static func cloneEnvironment(from inherited: [String: String]) -> [String: String] {
    let repositoryKeys: Set<String> = [
      "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
      "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE",
      "GIT_GRAFT_FILE",
      "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
      "GIT_SHALLOW_FILE", "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_INTERNAL_SUPER_PREFIX",
    ]
    return inherited.filter {
      !repositoryKeys.contains($0.key)
        && !$0.key.hasPrefix("GIT_CONFIG_KEY_") && !$0.key.hasPrefix("GIT_CONFIG_VALUE_")
    }
  }
}
