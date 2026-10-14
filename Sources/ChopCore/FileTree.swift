import Foundation

public struct FileTreeEntry: Equatable, Sendable {
  public let url: URL
  public let name: String
  public let isDirectory: Bool

  public init(url: URL, name: String, isDirectory: Bool) {
    self.url = url
    self.name = name
    self.isDirectory = isDirectory
  }
}

public enum FileTreeError: LocalizedError {
  case invalidPath, notDirectory

  public var errorDescription: String? {
    switch self {
    case .invalidPath: return "폴더 경로를 입력해 주세요."
    case .notDirectory: return "폴더 경로를 확인해 주세요."
    }
  }
}

public enum FileTree {
  /// Resolve a typed path without interpreting it as a shell command.
  public static func directoryURL(for path: String, relativeTo directory: URL) throws -> URL {
    guard !path.isEmpty, !path.contains("\0") else { throw FileTreeError.invalidPath }
    let expanded = (path as NSString).expandingTildeInPath
    return expanded.hasPrefix("/")
      ? URL(fileURLWithPath: expanded).standardizedFileURL
      : directory.appendingPathComponent(expanded).standardizedFileURL
  }

  /// Read one level only. Symbolic links and app packages are leaves, avoiding recursive cycles.
  public static func entries(at directory: URL) throws -> [FileTreeEntry] {
    var isDirectory: ObjCBool = false
    guard directory.isFileURL,
      FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw FileTreeError.notDirectory }
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .localizedNameKey,
    ]
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
    ).map { url in
      let values = try url.resourceValues(forKeys: keys)
      return FileTreeEntry(
        url: url, name: values.localizedName ?? url.lastPathComponent,
        isDirectory: values.isDirectory == true && values.isSymbolicLink != true
          && values.isPackage != true)
    }.sorted { first, second in
      if first.isDirectory != second.isDirectory { return first.isDirectory }
      return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }
  }
}
