import Darwin
import Foundation

/// A local TCP listener. The browser uses HTTP unless the terminal advertises HTTPS for this port.
public struct LocalServer: Hashable, Sendable {
  private static let urlExpression = try! NSRegularExpression(
    pattern:
      #"(https?)://(\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::([0-9]+)(?=$|[/#?\s<>"'()\[\]{},;.!]|[^\x00-\x7f])|(?=$|[/#?\s<>"'()\[\]{},;!]))"#,
    options: .caseInsensitive)
  public let host: String
  public let port: UInt16

  public init(host: String, port: UInt16) {
    self.host = host
    self.port = port
  }

  public var address: String { "\(host.contains(":") ? "[\(host)]" : host):\(port)" }

  public static func advertisedPorts(in screenText: String) -> Set<UInt16> {
    Set(hints(in: screenText).map(\.port))
  }

  private static func hints(in screenText: String) -> [(host: String, port: UInt16, https: Bool)] {
    let text = String(screenText.suffix(32_768)) as NSString
    return urlExpression.matches(
      in: text as String, range: NSRange(location: 0, length: text.length)
    )
    .compactMap { match in
      let host = text.substring(with: match.range(at: 2)).lowercased()
      var address = in_addr()
      let loopback =
        host.withCString { inet_pton(AF_INET, $0, &address) } == 1
        && (UInt32(bigEndian: address.s_addr) >> 24 == 127 || address.s_addr == 0)
      guard loopback || ["localhost", "[::1]", "[::]"].contains(host) else { return nil }
      let https = text.substring(with: match.range(at: 1)).lowercased() == "https"
      let port =
        match.range(at: 3).location == NSNotFound
        ? UInt16(https ? 443 : 80) : UInt16(text.substring(with: match.range(at: 3)))
      guard let port, port > 0 else { return nil }
      return (host, port, https)
    }
  }

  public func browserURL(screenText: String = "", preferringHTTPS: Bool = false) -> URL {
    var scheme = preferringHTTPS ? "https" : "http"
    // Only use the scheme, never a terminal-provided destination or executable URL scheme.
    for hint in Self.hints(in: screenText)
    where hint.port == port
      && ["localhost", "127.0.0.1", "0.0.0.0", "[::1]", "[::]", host].contains(hint.host)
    {
      scheme = hint.https ? "https" : "http"
    }
    return URL(string: "\(scheme)://\(address)")!
  }
}

/// Inspect owned shells and their descendants. Shared Codex workers also require a matching project
/// directory and an advertised port. No shell command, environment read, or network request is needed.
public enum LocalServerDiscovery {
  private struct Project {
    let rootPID: Int32
    let directory: String
    let ports: Set<UInt16>

    func contains(_ path: String) -> Bool {
      path == directory || path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }
  }

  private struct SharedServer {
    let servers: [LocalServer]
    let directory: String
  }

  public struct Target: Sendable {
    public let rootPID: Int32
    public let workingDirectory: String?
    public let advertisedPorts: Set<UInt16>

    public init(
      rootPID: Int32, workingDirectory: String? = nil, advertisedPorts: Set<UInt16> = []
    ) {
      self.rootPID = rootPID
      self.workingDirectory = workingDirectory
      self.advertisedPorts = advertisedPorts
    }
  }

  public static func scan(rootPIDs: [Int32]) -> [Int32: [LocalServer]] {
    scan(targets: rootPIDs.map { Target(rootPID: $0) })
  }

  public static func scan(targets: [Target]) -> [Int32: [LocalServer]] {
    var result: [Int32: Set<LocalServer>] = [:]
    let ownedRoots = Set(children(of: getpid()))
    let roots = Set(targets.map(\.rootPID)).filter {
      $0 > 0 && ($0 == getpid() || ownedRoots.contains($0))
    }
    let projects = targets.compactMap { target -> Project? in
      guard roots.contains(target.rootPID), let directory = target.workingDirectory,
        directory.hasPrefix("/"), !target.advertisedPorts.isEmpty
      else { return nil }
      return Project(
        rootPID: target.rootPID,
        directory: URL(fileURLWithPath: directory, isDirectory: true)
          .resolvingSymlinksInPath().standardizedFileURL.path,
        ports: target.advertisedPorts)
    }
    var shared: [SharedServer] = []
    var inspected = Set<Int32>()
    func scanTree(_ root: Int32, sharedRuntime: Bool) -> (Set<LocalServer>, [SharedServer])? {
      guard !Task.isCancelled else { return nil }
      let before = identity(root)
      if sharedRuntime {
        guard before?.pbi_uid == getuid(), isSharedRuntime(executablePath(root)) else { return nil }
      }
      var pending = [(pid: root, shared: sharedRuntime)]
      var visited = Set<Int32>()
      var servers = Set<LocalServer>()
      var rootShared: [SharedServer] = []
      while let entry = pending.popLast(), visited.count < 4096, !Task.isCancelled {
        let pid = entry.pid
        let process = identity(pid)
        guard pid == root || process.map({ visited.contains(Int32($0.pbi_ppid)) }) == true,
          visited.insert(pid).inserted
        else { continue }
        let path = executablePath(pid)
        let sharedRuntime = entry.shared || isSharedRuntime(path)
        inspected.insert(pid)
        if let process {
          // Agent transports listen on loopback too. Their own sockets are not app previews;
          // keep traversing their children so an agent-started dev server is still discovered.
          let directory = sharedRuntime ? workingDirectory(pid) : nil
          let ports =
            directory.map { directory in
              projects.filter { $0.contains(directory) }.reduce(into: Set<UInt16>()) {
                $0.formUnion($1.ports)
              }
            } ?? []
          let found =
            path?.lastPathComponent == "codex" || (sharedRuntime && ports.isEmpty)
            ? [] : listeners(pid).filter { !sharedRuntime || ports.contains($0.port) }
          if let current = identity(pid), process.pbi_start_tvsec == current.pbi_start_tvsec,
            process.pbi_start_tvusec == current.pbi_start_tvusec,
            process.pbi_ppid == current.pbi_ppid
          {
            if sharedRuntime {
              if let directory, !found.isEmpty {
                rootShared.append(SharedServer(servers: found, directory: directory))
              }
            } else {
              servers.formUnion(found)
            }
          }
        }
        // macOS login(1) is privileged: its BSD info can be denied even though its children are ours.
        pending += children(of: pid).map { (pid: $0, shared: sharedRuntime) }
      }
      if let before {
        guard let after = identity(root), before.pbi_start_tvsec == after.pbi_start_tvsec,
          before.pbi_start_tvusec == after.pbi_start_tvusec, before.pbi_ppid == after.pbi_ppid
        else { return nil }
      } else if !children(of: getpid()).contains(root) {
        return nil
      }
      if sharedRuntime && !isSharedRuntime(executablePath(root)) { return nil }
      return (servers, rootShared)
    }
    for root in roots {
      if let (servers, candidates) = scanTree(root, sharedRuntime: false) {
        result[root] = servers
        shared += candidates
      }
    }
    if !projects.isEmpty, !Task.isCancelled {
      // A reusable worker can outlive its original terminal. Enumerate only this user's processes;
      // inspect sockets solely below recognized runtimes and inside a hinted project directory.
      let runtimes = userProcesses().filter {
        !Task.isCancelled && !inspected.contains($0) && isSharedRuntime(executablePath($0))
      }
      let runtimeSet = Set(runtimes)
      for runtime in runtimes
      where !inspected.contains(runtime)
        && identity(runtime).map({ !runtimeSet.contains(Int32($0.pbi_ppid)) }) == true
      {
        if let (_, candidates) = scanTree(runtime, sharedRuntime: true) { shared += candidates }
      }
    }
    for project in projects where result[project.rootPID] != nil && !Task.isCancelled {
      for candidate in shared where project.contains(candidate.directory) {
        result[project.rootPID]?.formUnion(
          candidate.servers.filter { project.ports.contains($0.port) })
      }
    }
    return result.mapValues { servers in
      servers.sorted {
        $0.port == $1.port ? $0.host < $1.host : $0.port < $1.port
      }
    }
  }

  private static func isSharedRuntime(_ path: URL?) -> Bool {
    path?.lastPathComponent == "codex" && path?.pathComponents.contains("app-server-daemon") == true
  }

  private static func userProcesses() -> [Int32] {
    let stride = MemoryLayout<Int32>.stride
    let bytes = Int(proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0))
    guard bytes > 0, bytes / stride < 65_536 else { return [] }
    var pids = [Int32](repeating: 0, count: bytes / stride + 32)
    let count = pids.withUnsafeMutableBytes {
      proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
    }
    return count > 0 ? pids.prefix(Int(count) / stride).filter { $0 > 0 } : []
  }

  private static func children(of pid: Int32) -> [Int32] {
    // Unlike proc_pidinfo, proc_listchildpids returns a PID count, not a byte count.
    let capacity = Int(proc_listchildpids(pid, nil, 0)) + 32
    guard capacity > 0, capacity < 65_536 else { return [] }
    var children = [Int32](repeating: 0, count: capacity)
    let count = children.withUnsafeMutableBytes {
      proc_listchildpids(pid, $0.baseAddress, Int32($0.count))
    }
    return count > 0 ? children.prefix(Int(count)).filter { $0 > 0 } : []
  }

  private static func identity(_ pid: Int32) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
  }

  private static func executablePath(_ pid: Int32) -> URL? {
    // PROC_PIDPATHINFO_MAXSIZE is a C expression macro, unavailable to Swift.
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard count > 0 else { return nil }
    let path = String(
      decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return URL(fileURLWithPath: path)
  }

  private static func workingDirectory(_ pid: Int32) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    guard path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL.path
  }

  private static func listeners(_ pid: Int32) -> [LocalServer] {
    let stride = MemoryLayout<proc_fdinfo>.stride
    let required = Int(proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0))
    guard required > 0, required < 16_777_216 else { return [] }
    var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: required / stride + 32)
    let bytes = descriptors.withUnsafeMutableBytes {
      proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
    }
    guard bytes > 0 else { return [] }
    var result: [LocalServer] = []
    for descriptor in descriptors.prefix(Int(bytes) / stride)
    where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
      if Task.isCancelled { break }
      var socket = socket_fdinfo()
      let size = Int32(MemoryLayout.size(ofValue: socket))
      guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &socket, size) == size,
        socket.psi.soi_kind == SOCKINFO_TCP,
        socket.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
      else { continue }
      let info = socket.psi.soi_proto.pri_tcp.tcpsi_ini
      let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: info.insi_lport))
      guard port > 0 else { continue }
      if info.insi_vflag & UInt8(INI_IPV4) != 0 {
        var address = info.insi_laddr.ina_46.i46a_addr4
        let value = UInt32(bigEndian: address.s_addr)
        guard value == 0 || value >> 24 == 127 else { continue }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
          continue
        }
        let host =
          value == 0 || value == 0x7f00_0001
          ? "localhost"
          : String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        result.append(LocalServer(host: host, port: port))
      } else if info.insi_vflag & UInt8(INI_IPV6) != 0 {
        var address = info.insi_laddr.ina_6
        let values = withUnsafeBytes(of: &address) { Array($0) }
        guard
          values.allSatisfy({ $0 == 0 })
            || (values.dropLast().allSatisfy({ $0 == 0 }) && values.last == 1)
        else { continue }
        result.append(LocalServer(host: "localhost", port: port))
      }
    }
    return result
  }
}
