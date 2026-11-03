import Darwin
import Foundation

/// A local TCP listener. The browser uses HTTP unless the terminal advertises HTTPS for this port.
public struct LocalServer: Hashable, Sendable {
  private static let urlExpression = try! NSRegularExpression(
    pattern: #"https?://[^\s<>\"']+"#, options: .caseInsensitive)
  public let host: String
  public let port: UInt16

  public init(host: String, port: UInt16) {
    self.host = host
    self.port = port
  }

  public var address: String { "\(host.contains(":") ? "[\(host)]" : host):\(port)" }

  public func browserURL(screenText: String = "") -> URL {
    var scheme = "http"
    // Only use the scheme, never a terminal-provided destination or executable URL scheme.
    do {
      let text = String(screenText.suffix(32_768))
      for match in Self.urlExpression.matches(
        in: text, range: NSRange(text.startIndex..., in: text))
      {
        guard let range = Range(match.range, in: text),
          let parts = URLComponents(string: String(text[range])),
          ["localhost", "127.0.0.1", "0.0.0.0", "[::1]", "[::]", host].contains(
            parts.host?.lowercased() ?? ""),
          parts.user == nil, parts.password == nil,
          (parts.port ?? (parts.scheme == "https" ? 443 : 80)) == Int(port)
        else { continue }
        scheme = parts.scheme == "https" ? "https" : "http"
      }
    }
    return URL(string: "\(scheme)://\(address)")!
  }
}

/// Inspect only the supplied shells and their descendants. No shell command, system-wide port scan,
/// environment read, or network request is needed.
public enum LocalServerDiscovery {
  public static func scan(rootPIDs: [Int32]) -> [Int32: [LocalServer]] {
    var result: [Int32: [LocalServer]] = [:]
    let ownedRoots = Set(children(of: getpid()))
    for root in Set(rootPIDs) where root > 0 {
      guard !Task.isCancelled, root == getpid() || ownedRoots.contains(root)
      else { continue }
      let before = identity(root)
      var pending = [root]
      var visited = Set<Int32>()
      var servers = Set<LocalServer>()
      while let pid = pending.popLast(), visited.count < 4096, !Task.isCancelled {
        let process = identity(pid)
        guard pid == root || process.map({ visited.contains(Int32($0.pbi_ppid)) }) == true,
          visited.insert(pid).inserted
        else { continue }
        if let process {
          let found = listeners(pid)
          if let current = identity(pid), process.pbi_start_tvsec == current.pbi_start_tvsec,
            process.pbi_start_tvusec == current.pbi_start_tvusec,
            process.pbi_ppid == current.pbi_ppid
          {
            servers.formUnion(found)
          }
        }
        // macOS login(1) is privileged: its BSD info can be denied even though its children are ours.
        pending += children(of: pid)
      }
      if let before {
        guard let after = identity(root), before.pbi_start_tvsec == after.pbi_start_tvsec,
          before.pbi_start_tvusec == after.pbi_start_tvusec, before.pbi_ppid == after.pbi_ppid
        else { continue }
      } else if !children(of: getpid()).contains(root) {
        continue
      }
      result[root] = servers.sorted {
        $0.port == $1.port ? $0.host < $1.host : $0.port < $1.port
      }
    }
    return result
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
