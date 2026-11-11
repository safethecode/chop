import Foundation

/// Addresses entered by a person or restored from a session never become executable URL schemes.
public enum WebAddress {
  public static func parse(_ input: String) -> URL? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.utf8.count <= 4096,
      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    var candidate = text
    if !text.contains("://") {
      let host = text.lowercased().split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
      let local =
        host == "localhost" || host.hasPrefix("localhost:")
        || host == "127.0.0.1" || host.hasPrefix("127.0.0.1:")
        || host == "[::1]" || host.hasPrefix("[::1]:")
        || host == "0.0.0.0" || host.hasPrefix("0.0.0.0:")
      candidate = (local ? "http://" : "https://") + text
    }
    guard var parts = URLComponents(string: candidate),
      let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
      parts.port.map({ (1...65535).contains($0) }) ?? true
    else { return nil }
    parts.scheme = scheme
    if host == "0.0.0.0" || host == "[::]" { parts.host = "localhost" }
    if parts.path.isEmpty { parts.path = "/" }
    guard let url = parts.url, url.host != nil, url.absoluteString.utf8.count <= 4096 else {
      return nil
    }
    return url
  }

  public static func accepts(_ url: URL) -> Bool { parse(url.absoluteString) != nil }
}
