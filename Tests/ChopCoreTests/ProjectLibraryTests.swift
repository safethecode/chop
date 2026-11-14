import Foundation
import Testing

@testable import ChopCore

private func mixedProjectWorkspace(_ path: String) -> WorkspaceSnapshot {
  let terminal = UUID()
  let web = UUID()
  return WorkspaceSnapshot(
    layout: .split(
      id: UUID(), axis: .horizontal, ratio: 0.4, first: .pane(terminal), second: .pane(web)),
    panes: [
      PaneSnapshot(id: terminal, name: "서버 작업", workingDirectory: path, wasRunning: true),
      PaneSnapshot(
        id: web, name: "로컬 화면", workingDirectory: path, wasRunning: false,
        contentKind: .web, webURL: "http://localhost:3000/?name=test"),
    ], focusedID: web, tabbed: true)
}

@Test func projectLibraryScopesConfigurationsAndKeepsThemWhenRecentsAreCleared() throws {
  var library = ProjectLibrary()
  for index in 0..<15 { try library.visit("/projects/\(index)") }
  try library.visit("/projects/3/../2/")
  #expect(library.recentProjects.count == 12 && library.recentProjects.first == "/projects/2")
  #expect(Set(library.recentProjects).count == 12)
  let workspace = mixedProjectWorkspace("/projects/알파/소스")
  let settings = ProjectFileBrowserSettings(directory: "/projects/알파", isVisible: false, width: 360)
  let first = try library.saveConfiguration(
    name: " 개발 A ", projectDirectory: "/projects/알파", workspace: workspace, fileBrowser: settings)
  let other = try library.saveConfiguration(
    name: "개발 A", projectDirectory: "/projects/베타", workspace: workspace)
  #expect(library.configurations(for: "/projects/알파").map(\.id) == [first])
  #expect(throws: ProjectLibraryError.duplicateName) {
    try library.saveConfiguration(
      name: "개발 a", projectDirectory: "/projects/알파", workspace: workspace)
  }
  #expect(throws: ProjectLibraryError.missingConfiguration) {
    try library.removeConfiguration(other, in: "/projects/알파")
  }
  library.clearRecentProjects()
  #expect(library.recentProjects.isEmpty && library.configurations.count == 2)
  let replacement = mixedProjectWorkspace("/projects/알파/새 폴더")
  #expect(
    try library.saveConfiguration(
      name: "개발 A", projectDirectory: "/projects/알파", workspace: replacement,
      fileBrowser: settings, replacing: first) == first)
  let restored = try JSONDecoder().decode(ProjectLibrary.self, from: JSONEncoder().encode(library))
  try restored.validate()
  #expect(restored == library)
  #expect(restored.configurations(for: "/projects/알파").first?.workspace == replacement)
  #expect(restored.configurations(for: "/projects/알파").first?.fileBrowser == settings)
  try library.removeConfiguration(first, in: "/projects/알파")
  #expect(library.configurations.map(\.id) == [other])
}

@Test func projectLibraryRejectsInvalidUpdatesAndHonorsLimits() throws {
  var library = ProjectLibrary()
  let workspace = mixedProjectWorkspace("/project")
  for name in ["", "\n", "줄\n바꿈", String(repeating: "가", count: 65)] {
    #expect(throws: ProjectLibraryError.invalidName) {
      try library.saveConfiguration(name: name, projectDirectory: "/project", workspace: workspace)
    }
  }
  #expect(throws: ProjectLibraryError.invalid) { try library.visit("relative") }
  #expect(throws: ProjectLibraryError.invalid) {
    try library.saveConfiguration(
      name: "잘못된 폭", projectDirectory: "/project", workspace: workspace,
      fileBrowser: ProjectFileBrowserSettings(directory: "/project", isVisible: true, width: .nan))
  }
  for index in 0..<20 {
    try library.saveConfiguration(
      name: "구성 \(index)", projectDirectory: "/project", workspace: workspace)
  }
  let before = library
  #expect(throws: ProjectLibraryError.limitReached) {
    try library.saveConfiguration(name: "초과", projectDirectory: "/project", workspace: workspace)
  }
  #expect(library == before)
  let existing = try #require(library.configurations.first)
  try library.saveConfiguration(
    name: "한도에서 갱신", projectDirectory: "/project", workspace: workspace, replacing: existing.id)
  try library.validate()
  #expect(library.configurations.count == 20)
  for project in 1..<5 {
    for index in 0..<20 {
      try library.saveConfiguration(
        name: "구성 \(index)", projectDirectory: "/project-\(project)", workspace: workspace)
    }
  }
  #expect(library.configurations.count == 100)
  #expect(throws: ProjectLibraryError.limitReached) {
    try library.saveConfiguration(name: "전체 한도 초과", projectDirectory: "/new", workspace: workspace)
  }
}

@Test func projectLibraryStorePreservesUnreadableFilesAndFailedMutations() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = ProjectLibraryStore(fileURL: directory.appendingPathComponent("projects.json"))
  let workspace = mixedProjectWorkspace("/project")
  let good = try store.update {
    try $0.visit("/project")
    try $0.saveConfiguration(name: "개발", projectDirectory: "/project", workspace: workspace)
  }
  #expect(try store.load() == good)
  let original = try Data(contentsOf: store.fileURL)
  #expect(throws: ProjectLibraryError.invalidName) {
    try store.update {
      $0.clearRecentProjects()
      try $0.saveConfiguration(name: "", projectDirectory: "/project", workspace: workspace)
    }
  }
  #expect(try Data(contentsOf: store.fileURL) == original)
  var invalidWorkspace = workspace
  invalidWorkspace.version = 999
  #expect(throws: SnapshotError.unsupportedVersion) {
    try store.update {
      $0.clearRecentProjects()
      try $0.saveConfiguration(
        name: "잘못된 배치", projectDirectory: "/project", workspace: invalidWorkspace)
    }
  }
  #expect(try Data(contentsOf: store.fileURL) == original)
  let unreadable = [
    Data("{broken".utf8),
    Data("{\"version\":999,\"recentProjects\":[],\"configurations\":[]}".utf8),
    Data(repeating: 0x20, count: ProjectLibraryStore.maximumBytes + 1),
  ]
  for bytes in unreadable {
    try bytes.write(to: store.fileURL)
    #expect(throws: ProjectLibraryError.self) { try store.update { try $0.visit("/other") } }
    #expect(try Data(contentsOf: store.fileURL) == bytes)
  }
  let blocker = directory.appendingPathComponent("regular-file")
  try original.write(to: blocker)
  let blocked = ProjectLibraryStore(fileURL: blocker.appendingPathComponent("projects.json"))
  #expect(throws: ProjectLibraryError.writeFailed) {
    try blocked.update { try $0.visit("/project") }
  }
  #expect(try Data(contentsOf: blocker) == original)
  try original.write(to: store.fileURL)
  #expect(try store.load() == good)
}
