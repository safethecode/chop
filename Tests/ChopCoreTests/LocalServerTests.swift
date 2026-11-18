import Darwin
import Foundation
import Testing

@testable import ChopCore

@MainActor
@Test func agentTransportIsExcludedWithoutHidingItsDevServer() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  // A real executable named codex owns an internal listener and launches a separate server.
  // This catches filtering the whole agent subtree instead of just its transport sockets.
  let source = """
    #include <arpa/inet.h>
    #include <signal.h>
    #include <stdio.h>
    #include <sys/wait.h>
    #include <unistd.h>
    int main(int argc, char **argv) {
      int fd = socket(AF_INET, SOCK_STREAM, 0);
      struct sockaddr_in addr = {.sin_family=AF_INET, .sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
      if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || listen(fd, 4)) return 1;
      socklen_t len = sizeof(addr);
      if (getsockname(fd, (struct sockaddr *)&addr, &len)) return 2;
      FILE *out = fopen(argv[1], "w");
      if (!out) return 3;
      fprintf(out, "%u", ntohs(addr.sin_port)); fclose(out);
      pid_t child = fork();
      if (child < 0) return 4;
      if (!child) {
        close(fd);
        execl("/usr/bin/python3", "python3", "-c",
          "import socket,sys,time; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); open(sys.argv[1],'w').write(str(s.getsockname()[1])); time.sleep(30)",
          argv[2], NULL);
        _exit(5);
      }
      char command;
      read(STDIN_FILENO, &command, 1);
      kill(child, SIGKILL); waitpid(child, NULL, 0); close(fd);
      return 0;
    }
    """
  let sourceURL = directory.appendingPathComponent("fixture.c")
  let executable = directory.appendingPathComponent("codex")
  try source.write(to: sourceURL, atomically: true, encoding: .utf8)
  let compiler = Process()
  compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
  compiler.arguments = [sourceURL.path, "-o", executable.path]
  try compiler.run()
  defer { if compiler.isRunning { kill(compiler.processIdentifier, SIGKILL) } }
  let compileDeadline = ContinuousClock.now.advanced(by: .seconds(15))
  while compiler.isRunning, ContinuousClock.now < compileDeadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  try #require(!compiler.isRunning)
  try #require(compiler.terminationStatus == 0)
  let agentPortFile = directory.appendingPathComponent("agent-port")
  let serverPortFile = directory.appendingPathComponent("server-port")
  let input = Pipe()
  let agent = Process()
  agent.executableURL = executable
  agent.arguments = [agentPortFile.path, serverPortFile.path]
  agent.standardInput = input
  try agent.run()
  defer { try? input.fileHandleForWriting.close() }
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  var serverPort: UInt16?
  while serverPort == nil, ContinuousClock.now < deadline {
    serverPort = (try? String(contentsOf: serverPortFile, encoding: .utf8)).flatMap(UInt16.init)
    if serverPort == nil { try await Task.sleep(for: .milliseconds(20)) }
  }
  let port = try #require(serverPort)
  let internalPort = try #require(
    (try? String(contentsOf: agentPortFile, encoding: .utf8)).flatMap(UInt16.init))
  let servers = LocalServerDiscovery.scan(rootPIDs: [agent.processIdentifier])
  #expect(
    servers[agent.processIdentifier]?.contains(LocalServer(host: "localhost", port: port)) == true)
  #expect(
    servers[agent.processIdentifier]?.contains(LocalServer(host: "localhost", port: internalPort))
      == false)
  try input.fileHandleForWriting.close()
  let exitDeadline = ContinuousClock.now.advanced(by: .seconds(5))
  while agent.isRunning, ContinuousClock.now < exitDeadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(!agent.isRunning)
}

@MainActor
@Test func localServerDiscoveryReadsAChildProcessWithoutIncludingOtherRoots() async throws {
  let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
  process.arguments = [
    "-c",
    "import socket,time,sys; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); open(sys.argv[1],'w').write(str(s.getsockname()[1])); time.sleep(30)",
    marker.path,
  ]
  try process.run()
  defer {
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
    try? FileManager.default.removeItem(at: marker)
  }
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  var announcedPort: UInt16?
  while announcedPort == nil, ContinuousClock.now < deadline {
    announcedPort = (try? String(contentsOf: marker, encoding: .utf8)).flatMap(UInt16.init)
    if announcedPort != nil { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let port = try #require(announcedPort)
  let root = process.processIdentifier
  let found = LocalServerDiscovery.scan(rootPIDs: [root])
  #expect(found[root]?.contains(LocalServer(host: "localhost", port: port)) == true)
  #expect(LocalServerDiscovery.scan(rootPIDs: [getppid()]).isEmpty)
  process.terminate()
  // Foundation Process keeps run-loop state. Never block a test indefinitely in waitUntilExit.
  let exitDeadline = ContinuousClock.now.advanced(by: .seconds(5))
  while process.isRunning, ContinuousClock.now < exitDeadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(!process.isRunning, "검사 서버가 제한 시간 안에 종료되어야 합니다.")
}

@Test func localServerHintsCannotReplaceTheListenerDestination() {
  let server = LocalServer(host: "localhost", port: 3000)
  #expect(server.browserURL().absoluteString == "http://localhost:3000")
  #expect(server.browserURL(preferringHTTPS: true).scheme == "https")
  #expect(server.browserURL(screenText: "HTTPS://LOCALHOST:3000").scheme == "https")
  #expect(
    server.browserURL(screenText: "http://localhost:3000", preferringHTTPS: true).scheme == "http")
  #expect(
    server.browserURL(screenText: "Local: https://localhost:3000/base/").absoluteString
      == "https://localhost:3000")
  for text in [
    "https://localhost.evil.example:3000", "https://user@localhost:3000", "https://localhost:4000",
    "file:///tmp/localhost:3000", "https://example.com:3000",
  ] {
    #expect(server.browserURL(screenText: text).absoluteString == "http://localhost:3000")
  }
  #expect(LocalServer(host: "127.0.0.2", port: 8080).browserURL().host == "127.0.0.2")
}

@Test func localServerDiscoveryTracksActualListenersAndRemovesClosedPorts() throws {
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  #expect(descriptor >= 0)
  guard descriptor >= 0 else { return }
  var shouldClose = true
  defer { if shouldClose { close(descriptor) } }
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_addr.s_addr = inet_addr("127.0.0.1")
  let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  #expect(bound == 0)
  var size = socklen_t(MemoryLayout<sockaddr_in>.size)
  let named = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
  }
  #expect(named == 0)
  let port = UInt16(bigEndian: address.sin_port)
  let expected = LocalServer(host: "localhost", port: port)
  // A bound TCP socket that has not begun listening must not be advertised.
  #expect(LocalServerDiscovery.scan(rootPIDs: [getpid()])[getpid()]?.contains(expected) == false)
  #expect(listen(descriptor, 4) == 0)
  #expect(LocalServerDiscovery.scan(rootPIDs: [getpid()])[getpid()]?.contains(expected) == true)
  #expect(LocalServerDiscovery.scan(rootPIDs: [-1, 0]).isEmpty)
  close(descriptor)
  shouldClose = false
  #expect(LocalServerDiscovery.scan(rootPIDs: [getpid()])[getpid()]?.contains(expected) == false)
}
