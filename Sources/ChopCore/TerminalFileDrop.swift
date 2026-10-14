import Foundation

public enum TerminalFileDrop {
  /// Format local file URLs as separate shell arguments, without typing terminal control keys.
  public static func text(for urls: [URL]) -> String? {
    guard !urls.isEmpty,
      urls.allSatisfy({ url in
        url.isFileURL && url.path.hasPrefix("/")
          && url.path.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && !(0x7F...0x9F).contains($0.value)
          }
      })
    else { return nil }
    return urls.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
      .joined(separator: " ") + " "
  }
}
