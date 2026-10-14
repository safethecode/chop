import Foundation
import Testing

@testable import ChopCore

@Test func terminalFileDropPreservesLiteralPathsAsSeparateShellArguments() throws {
  let urls = [
    URL(fileURLWithPath: "/tmp/한글 공백 👩‍💻.txt"),
    URL(fileURLWithPath: "/tmp/a'b\";$HOME`false`\\name.txt"),
  ]
  let text = try #require(TerminalFileDrop.text(for: urls))
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/sh")
  process.arguments = ["-c", "printf '%s\\0' " + text]
  let output = Pipe()
  process.standardOutput = output
  try process.run()
  process.waitUntilExit()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  #expect(process.terminationStatus == 0)
  #expect(
    String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
      == urls.map(\.path))
}

@Test func terminalFileDropRejectsNonFilesAndTerminalControlCharacters() {
  #expect(TerminalFileDrop.text(for: []) == nil)
  #expect(TerminalFileDrop.text(for: [URL(string: "https://example.com/file")!]) == nil)
  for control in ["\n", "\r", "\t", "\u{1B}", "\u{7F}", "\u{85}"] {
    #expect(TerminalFileDrop.text(for: [URL(fileURLWithPath: "/tmp/a\(control)b")]) == nil)
  }
  #expect(
    TerminalFileDrop.text(for: [
      URL(fileURLWithPath: "/tmp/file"), URL(string: "https://example.com/file")!,
    ]) == nil)
}
