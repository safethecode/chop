import Foundation

public enum TerminalFileLink {
  // Ghostty maps logical lines back to cells, including soft wraps and wide characters.
  // Quoted and parenthesized paths may contain spaces; bare paths use shell escaping.
  public static let patterns = [
    #"(["'`])(?:/|~/|\.{1,2}/)(?:(?!\1)[^\x00-\x1F\x7F])+\1"#,
    #"\((?:/|~/|\.{1,2}/)(?:[^()\x00-\x1F\x7F<>]|\([^()\x00-\x1F\x7F<>]*\))+\)"#,
    #"(?<![\p{L}\p{N}_./~:%])(?:/|~/|\.{1,2}/)(?:\\[^\r\n]|[^\s<>"'`|])+"#,
  ]

  public static func localURL(
    for text: String, workingDirectory: URL,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL? {
    guard !text.isEmpty, text.utf8.count <= 16_384,
      !text.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
    else { return nil }
    var path = text
    let isQuoted =
      path.count > 1 && (path.first.map { "\"'`".contains($0) && path.last == $0 } ?? false)
    let isDelimited = isQuoted || (path.first == "(" && path.last == ")")
    if isDelimited {
      path.removeFirst()
      path.removeLast()
    }
    // Try the exact filename first so punctuation in real filenames is preserved.
    for _ in 0..<8 {
      let versions = isQuoted ? [path] : [path, unescaped(path)]
      for version in versions {
        if let url = candidate(
          version, workingDirectory: workingDirectory, homeDirectory: homeDirectory),
          FileManager.default.fileExists(atPath: url.path)
        {
          return url
        }
      }
      if !isDelimited, let last = path.last, ")]}>.,;:!?".contains(last) {
        path.removeLast()
      } else {
        break
      }
    }
    return nil
  }

  private static func candidate(_ text: String, workingDirectory: URL, homeDirectory: URL) -> URL? {
    if text.lowercased().hasPrefix("file:") {
      guard let parts = URLComponents(string: text), parts.scheme?.lowercased() == "file",
        parts.host == nil || parts.host == "" || parts.host?.lowercased() == "localhost",
        parts.user == nil, parts.password == nil, parts.port == nil,
        parts.query == nil, parts.fragment == nil, let url = parts.url, url.isFileURL,
        !url.path.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }
        )
      else { return nil }
      return url.standardizedFileURL
    }
    if text.hasPrefix("~/") {
      return homeDirectory.appendingPathComponent(String(text.dropFirst(2))).standardizedFileURL
    }
    guard text.hasPrefix("/") || text.hasPrefix("./") || text.hasPrefix("../") else { return nil }
    let directory = URL(fileURLWithPath: workingDirectory.path, isDirectory: true)
    return URL(fileURLWithPath: text, relativeTo: directory).standardizedFileURL
  }

  // Shell escapes are decoded as characters only; no shell or variable expansion is used.
  private static func unescaped(_ text: String) -> String {
    var path = ""
    var escaped = false
    for character in text {
      if escaped {
        path.append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else {
        path.append(character)
      }
    }
    if escaped { path.append("\\") }
    return path
  }
}
