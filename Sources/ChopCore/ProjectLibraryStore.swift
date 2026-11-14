import Foundation

public struct ProjectLibraryStore: Sendable {
  public static let maximumBytes = 4 * 1024 * 1024
  public let fileURL: URL

  public init(fileURL: URL) { self.fileURL = fileURL }

  public func load() throws -> ProjectLibrary {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return ProjectLibrary() }
    let data: Data
    do {
      let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
      guard size?.intValue ?? 0 <= Self.maximumBytes else { throw ProjectLibraryError.tooLarge }
      data = try Data(contentsOf: fileURL)
    } catch let error as ProjectLibraryError { throw error } catch {
      throw ProjectLibraryError.readFailed
    }
    guard data.count <= Self.maximumBytes else { throw ProjectLibraryError.tooLarge }
    let library: ProjectLibrary
    do { library = try JSONDecoder().decode(ProjectLibrary.self, from: data) } catch {
      throw ProjectLibraryError.invalid
    }
    do { try library.validate() } catch let error as ProjectLibraryError { throw error } catch {
      throw ProjectLibraryError.invalid
    }
    return library
  }

  /// Read and validate before every mutation: unreadable/newer records are never replaced.
  @discardableResult
  public func update(_ mutation: (inout ProjectLibrary) throws -> Void) throws -> ProjectLibrary {
    var library = try load()
    try mutation(&library)
    try library.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(library)
    guard data.count <= Self.maximumBytes else { throw ProjectLibraryError.tooLarge }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try data.write(to: fileURL, options: .atomic)
    } catch { throw ProjectLibraryError.writeFailed }
    return library
  }
}
