import Foundation

public struct ProjectFileBrowserSettings: Codable, Equatable, Sendable {
  public let directory: String
  public let isVisible: Bool
  public let width: Double

  public init(directory: String, isVisible: Bool, width: Double) {
    self.directory = directory
    self.isVisible = isVisible
    self.width = width
  }

  fileprivate func validate() throws {
    _ = try ProjectLibrary.projectPath(directory)
    guard width.isFinite, (280...600).contains(width) else { throw ProjectLibraryError.invalid }
  }
}

public struct ProjectConfiguration: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let projectDirectory: String
  public let name: String
  public let workspace: WorkspaceSnapshot
  public let fileBrowser: ProjectFileBrowserSettings?
}

/// Reusable metadata, separate from the session's currently open windows and processes.
public struct ProjectLibrary: Codable, Equatable, Sendable {
  public var version = 1
  public private(set) var recentProjects: [String] = []
  public private(set) var configurations: [ProjectConfiguration] = []
  public static let maximumRecentProjects = 12
  public static let maximumConfigurationsPerProject = 20
  public static let maximumConfigurations = 100

  public init() {}

  public static func projectPath(_ path: String) throws -> String {
    guard path.hasPrefix("/"), path.utf8.count <= 4096, !path.contains("\0") else {
      throw ProjectLibraryError.invalid
    }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
  }

  public static func configurationName(_ value: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 64,
      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else { throw ProjectLibraryError.invalidName }
    return name
  }

  private static func nameKey(_ name: String) -> String {
    name.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }

  public func configurations(for directory: String) -> [ProjectConfiguration] {
    guard let path = try? Self.projectPath(directory) else { return [] }
    return configurations.filter { $0.projectDirectory == path }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public func configuration(named name: String, in directory: String) -> ProjectConfiguration? {
    configurations(for: directory).first { Self.nameKey($0.name) == Self.nameKey(name) }
  }

  public mutating func visit(_ directory: String) throws {
    let path = try Self.projectPath(directory)
    recentProjects.removeAll { $0 == path }
    recentProjects.insert(path, at: 0)
    recentProjects = Array(recentProjects.prefix(Self.maximumRecentProjects))
  }

  public mutating func clearRecentProjects() { recentProjects.removeAll() }

  @discardableResult
  public mutating func saveConfiguration(
    name: String, projectDirectory: String, workspace: WorkspaceSnapshot,
    fileBrowser: ProjectFileBrowserSettings? = nil, replacing id: UUID? = nil
  ) throws -> UUID {
    let path = try Self.projectPath(projectDirectory)
    let name = try Self.configurationName(name)
    try workspace.validate()
    try fileBrowser?.validate()
    if configurations.contains(where: {
      $0.projectDirectory == path && Self.nameKey($0.name) == Self.nameKey(name) && $0.id != id
    }) {
      throw ProjectLibraryError.duplicateName
    }
    let index = id.flatMap { id in
      configurations.firstIndex { $0.id == id && $0.projectDirectory == path }
    }
    if id != nil, index == nil { throw ProjectLibraryError.missingConfiguration }
    if index == nil {
      guard configurations.count < Self.maximumConfigurations,
        configurations(for: path).count < Self.maximumConfigurationsPerProject
      else { throw ProjectLibraryError.limitReached }
    }
    let entry = ProjectConfiguration(
      id: id ?? UUID(), projectDirectory: path, name: name, workspace: workspace,
      fileBrowser: fileBrowser)
    if let index { configurations[index] = entry } else { configurations.append(entry) }
    return entry.id
  }

  public mutating func removeConfiguration(_ id: UUID, in directory: String) throws {
    let path = try Self.projectPath(directory)
    guard
      let index = configurations.firstIndex(where: {
        $0.id == id && $0.projectDirectory == path
      })
    else { throw ProjectLibraryError.missingConfiguration }
    configurations.remove(at: index)
  }

  public func validate() throws {
    guard version == 1 else { throw ProjectLibraryError.unsupportedVersion }
    guard recentProjects.count <= Self.maximumRecentProjects,
      Set(recentProjects).count == recentProjects.count,
      configurations.count <= Self.maximumConfigurations,
      Set(configurations.map(\.id)).count == configurations.count
    else { throw ProjectLibraryError.invalid }
    for path in recentProjects {
      guard try Self.projectPath(path) == path else { throw ProjectLibraryError.invalid }
    }
    var names: [String: Set<String>] = [:]
    for entry in configurations {
      guard try Self.projectPath(entry.projectDirectory) == entry.projectDirectory,
        try Self.configurationName(entry.name) == entry.name,
        names[entry.projectDirectory, default: []].insert(Self.nameKey(entry.name)).inserted,
        names[entry.projectDirectory]!.count <= Self.maximumConfigurationsPerProject
      else { throw ProjectLibraryError.invalid }
      try entry.workspace.validate()
      try entry.fileBrowser?.validate()
    }
  }
}

public enum ProjectLibraryError: LocalizedError {
  case invalid, invalidName, unsupportedVersion, duplicateName, missingConfiguration, limitReached
  case tooLarge, readFailed, writeFailed

  public var errorDescription: String? {
    switch self {
    case .invalid: return "프로젝트 기록의 형식이 올바르지 않아요. 기존 파일은 유지합니다."
    case .invalidName: return "이름을 줄바꿈 없이 1~64자로 입력해 주세요."
    case .unsupportedVersion: return "이 버전에서 읽을 수 없는 프로젝트 기록이에요. 기존 파일은 유지합니다."
    case .duplicateName: return "같은 이름의 작업 구성이 있어요."
    case .missingConfiguration: return "저장한 작업 구성을 찾지 못했어요. 목록을 다시 불러와 주세요."
    case .limitReached: return "작업 구성은 프로젝트마다 20개, 전체 100개까지 저장할 수 있어요. 사용하지 않는 구성을 삭제해 주세요."
    case .tooLarge: return "프로젝트 기록 파일이 너무 커요. 기존 파일은 유지합니다."
    case .readFailed: return "프로젝트 기록 파일을 읽지 못했어요. 기존 파일은 유지합니다."
    case .writeFailed: return "프로젝트 기록을 저장하지 못했어요. 저장 위치를 확인한 뒤 다시 시도해 주세요."
    }
  }
}
