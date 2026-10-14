import Foundation
import Testing

@testable import ChopCore

@Test func fileTreeReadsOneLevelAndSortsFoldersBeforeNaturalFileNames() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let child = root.appendingPathComponent("folder")
  try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
  for name in ["file10.txt", "file2.txt", ".hidden"] {
    try Data().write(to: root.appendingPathComponent(name))
  }
  try Data().write(to: child.appendingPathComponent("nested.txt"))
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent("link"), withDestinationURL: root)
  let entries = try FileTree.entries(at: root)
  #expect(entries.map(\.name) == ["folder", "file2.txt", "file10.txt", "link"])
  #expect(entries.filter(\.isDirectory).map(\.name) == ["folder"])
  #expect(try FileTree.entries(at: child).map(\.name) == ["nested.txt"])
  #expect(throws: FileTreeError.self) {
    try FileTree.entries(at: root.appendingPathComponent("file2.txt"))
  }
  #expect(throws: FileTreeError.self) {
    try FileTree.entries(at: root.appendingPathComponent("missing"))
  }
}

@Test func fileTreePathsHandleRelativeUnicodeAndLiteralShellCharacters() throws {
  let root = URL(fileURLWithPath: "/tmp/프로젝트 폴더")
  #expect(try FileTree.directoryURL(for: "../문서", relativeTo: root).path == "/tmp/문서")
  #expect(
    try FileTree.directoryURL(for: "$(echo name)", relativeTo: root).lastPathComponent
      == "$(echo name)")
  #expect(
    try FileTree.directoryURL(for: "~", relativeTo: root).path
      == FileManager.default.homeDirectoryForCurrentUser.path)
  #expect(throws: FileTreeError.self) { try FileTree.directoryURL(for: "", relativeTo: root) }
  #expect(throws: FileTreeError.self) { try FileTree.directoryURL(for: "a\0b", relativeTo: root) }
}
