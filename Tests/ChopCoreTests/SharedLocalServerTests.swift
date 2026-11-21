import Darwin
import Foundation
import Testing

@testable import ChopCore

@Test func localServerHintsReadKoreanSuffixesAndRejectForeignOrInvalidDestinations() {
  #expect(LocalServer.advertisedPorts(in: "http://localhost:3000에서 확인하세요.") == [3000])
  #expect(
    LocalServer.advertisedPorts(
      in: "https://[::1]:443/ · http://127.0.0.2:8080 · http://0.0.0.0:4000")
      == [443, 8080, 4000])
  #expect(LocalServer.advertisedPorts(in: "http://localhost/ https://localhost/") == [80, 443])
  for text in [
    "http://localhost.evil.example:3000", "http://user@localhost:3000",
    "http://localhost:3000@evil.example", "http://127.999.0.1:3000", "http://localhost:65536",
    "http://localhost:0", "http://localhost:300000", "ws://localhost:3000",
    "http://192.168.0.1:3000", "http://localhost악성.example", "http://[::1]suffix",
  ] {
    #expect(LocalServer.advertisedPorts(in: text).isEmpty, "\(text)")
  }
  let server = LocalServer(host: "localhost", port: 3000)
  #expect(server.browserURL(screenText: "https://localhost:3000에서 확인하세요.").scheme == "https")
  #expect(
    server.browserURL(screenText: "https://localhost:3000 · http://localhost:3000에서").scheme
      == "http")
}

@MainActor
@Test func sharedAgentServerAppearsOnlyInTheProjectThatReportsItsPort() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let host = directory.appendingPathComponent("project-a")
  let project = directory.appendingPathComponent("project-b")
  let web = project.appendingPathComponent("apps/web")
  let executable = directory.appendingPathComponent("app-server-daemon/releases/fixture/bin/codex")
  for folder in [host, web, executable.deletingLastPathComponent()] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  defer { try? FileManager.default.removeItem(at: directory) }
  let source = #"""
    #include <arpa/inet.h>
    #include <signal.h>
    #include <stdio.h>
    #include <sys/wait.h>
    #include <unistd.h>
    int main(int argc, char **argv) {
      int fd=socket(AF_INET,SOCK_STREAM,0);
      struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
      if(bind(fd,(struct sockaddr *)&addr,sizeof(addr)) || listen(fd,4)) return 1;
      socklen_t size=sizeof(addr);
      if(getsockname(fd,(struct sockaddr *)&addr,&size)) return 2;
      FILE *out=fopen(argv[1],"w"); if(!out) return 3;
      fprintf(out,"%u",ntohs(addr.sin_port)); fclose(out);
      pid_t child=fork(); if(child<0) return 4;
      if(!child) {
        close(fd); if(chdir(argv[3])) _exit(5);
        execl("/usr/bin/python3","python3","-u","-c",
          "import http.server,sys; s=http.server.ThreadingHTTPServer(('127.0.0.1',0),http.server.SimpleHTTPRequestHandler); open(sys.argv[1],'w').write(str(s.server_port)); s.serve_forever()",
          argv[2],NULL); _exit(6);
      }
      char command; read(STDIN_FILENO,&command,1);
      kill(child,SIGTERM); waitpid(child,NULL,0); close(fd); return 0;
    }
    """#
  let sourceURL = directory.appendingPathComponent("fixture.c")
  try source.write(to: sourceURL, atomically: true, encoding: .utf8)
  let compiler = Process()
  compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
  compiler.arguments = [sourceURL.path, "-o", executable.path]
  try compiler.run()
  defer { if compiler.isRunning { kill(compiler.processIdentifier, SIGKILL) } }
  func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition())
  }
  try await waitFor { !compiler.isRunning }
  try #require(compiler.terminationStatus == 0)
  let transportFile = directory.appendingPathComponent("transport-port")
  let serverFile = directory.appendingPathComponent("server-port")
  let pipe = Pipe()
  let agent = Process()
  agent.executableURL = executable
  agent.arguments = [transportFile.path, serverFile.path, web.path]
  agent.currentDirectoryURL = host
  agent.standardInput = pipe
  try agent.run()
  defer { try? pipe.fileHandleForWriting.close() }
  let client = Process()
  client.executableURL = URL(fileURLWithPath: "/bin/sleep")
  client.arguments = ["60"]
  client.currentDirectoryURL = project
  try client.run()
  defer { if client.isRunning { client.terminate() } }
  try await waitFor {
    (try? String(contentsOf: serverFile, encoding: .utf8)).flatMap(UInt16.init) != nil
  }
  let port = try #require(
    (try? String(contentsOf: serverFile, encoding: .utf8)).flatMap(UInt16.init))
  let transportPort = try #require(
    (try? String(contentsOf: transportFile, encoding: .utf8)).flatMap(UInt16.init))
  let expected = LocalServer(host: "localhost", port: port)
  func scan(_ folder: String, ports: Set<UInt16>) -> [Int32: [LocalServer]] {
    LocalServerDiscovery.scan(targets: [
      .init(rootPID: agent.processIdentifier, workingDirectory: host.path, advertisedPorts: [port]),
      .init(rootPID: client.processIdentifier, workingDirectory: folder, advertisedPorts: ports),
    ])
  }
  let found = scan(project.path, ports: [port, transportPort])
  #expect(
    found[agent.processIdentifier]?.isEmpty == true, "Hosting the daemon does not own every project"
  )
  #expect(found[client.processIdentifier] == [expected], "The transport socket must stay excluded")
  #expect(
    LocalServerDiscovery.scan(targets: [
      .init(
        rootPID: client.processIdentifier, workingDirectory: project.path, advertisedPorts: [port])
    ])[client.processIdentifier] == [expected], "The shared worker can belong to another session")
  #expect(scan(project.path, ports: [transportPort])[client.processIdentifier]?.isEmpty == true)
  #expect(scan(project.path, ports: [])[client.processIdentifier]?.isEmpty == true)
  #expect(scan(project.path + "-other", ports: [port])[client.processIdentifier]?.isEmpty == true)
  let alias = directory.appendingPathComponent("project-alias")
  try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
  #expect(scan(alias.path, ports: [port])[client.processIdentifier] == [expected])
  #expect(
    LocalServerDiscovery.scan(targets: [
      .init(rootPID: getppid(), workingDirectory: project.path, advertisedPorts: [port])
    ]).isEmpty)
  try pipe.fileHandleForWriting.close()
  try await waitFor { !agent.isRunning }
  #expect(scan(project.path, ports: [port])[client.processIdentifier]?.isEmpty == true)
}
