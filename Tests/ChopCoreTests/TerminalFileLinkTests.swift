import Foundation
import Testing

@testable import ChopCore

@Test func terminalFileLinksResolveExistingLocalPathsWithoutRunningShellSyntax() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let folder = root.appendingPathComponent("한글 폴더")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let image = folder.appendingPathComponent("그림 (2) 👩‍💻.png")
  let punctuation = folder.appendingPathComponent("a.png)")
  let backslash = folder.appendingPathComponent("a\\b.png")
  for file in [image, punctuation, backslash] { try Data().write(to: file) }
  func resolve(_ text: String) -> URL? {
    TerminalFileLink.localURL(for: text, workingDirectory: folder, homeDirectory: root)
  }
  for text in [
    image.path, "\"\(image.path)\"", "(\(image.path))", "`\(image.path)`",
    image.absoluteString, "file://localhost" + image.absoluteString.dropFirst(7),
    "./" + image.lastPathComponent, "../한글 폴더/" + image.lastPathComponent,
    "~/한글 폴더/" + image.lastPathComponent,
    image.path.replacingOccurrences(of: " ", with: "\\ "), image.path + ").",
  ] {
    #expect(resolve(String(text))?.path == image.path, "\(text)")
  }
  #expect(resolve(punctuation.path)?.path == punctuation.path)
  #expect(resolve("\"\(backslash.path)\"")?.path == backslash.path)
  #expect(resolve(folder.path)?.path == folder.path)
  #expect(resolve("\"\(image.path)).\"") == nil, "Quoted paths must use the exact filename")
  #expect(resolve("(\(image.path)).)") == nil, "Delimited paths must not open a different file")
}

@Test func terminalFileLinksRejectMissingRemoteAndControlCharacterPaths() throws {
  let root = FileManager.default.temporaryDirectory
  for text in [
    "/chop-path-that-does-not-exist/image.png", "https://example.com/tmp/image.png",
    "file://remote.example/tmp/image.png", "file://user@localhost/tmp/image.png",
    "file:///tmp/image.png?query", "file:///tmp/image.png#fragment", "file:///tmp/%00",
    "/tmp/a\u{1B}b.png", "/tmp/a\nb.png", "$(touch /tmp/chop-file-link-test)",
    "$HOME/image.png", "~other/image.png", "image.png", "'", "\"", "`", "()", "",
    String(repeating: "/", count: 16_385),
  ] {
    #expect(
      TerminalFileLink.localURL(for: text, workingDirectory: root) == nil, "\(text.prefix(100))")
  }
}

@Test func terminalFileLinkPatternsSeparateAdjacentPathsAndPreserveUnicode() throws {
  func matches(_ line: String) throws -> [String] {
    let source = line as NSString
    var ranges: [NSRange] = []
    for pattern in TerminalFileLink.patterns {
      let regex = try NSRegularExpression(pattern: pattern)
      for match in regex.matches(in: line, range: NSRange(location: 0, length: source.length)) {
        if !ranges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
          ranges.append(match.range)
        }
      }
    }
    return ranges.sorted { $0.location < $1.location }.map { source.substring(with: $0) }
  }
  #expect(
    try matches("PNG 다운로드 (/tmp/noci-og-preview/noci-og.png) · SVG 원본 (/tmp/noci-og.svg)")
      == ["(/tmp/noci-og-preview/noci-og.png)", "(/tmp/noci-og.svg)"])
  #expect(
    try matches("\"/tmp/한글 공백/그림 (2).png\" '/tmp/a\"b.png' `~/a'b.png` ./그림.png ../a.png")
      == ["\"/tmp/한글 공백/그림 (2).png\"", "'/tmp/a\"b.png'", "`~/a'b.png`", "./그림.png", "../a.png"])
  #expect(try matches("(/tmp/그림 (2).png)") == ["(/tmp/그림 (2).png)"])
  #expect(try matches("/tmp/한글\\ 공백.png") == ["/tmp/한글\\ 공백.png"])
  #expect(try matches("https://example.com/image.png text/plain a/b") == [])
}
