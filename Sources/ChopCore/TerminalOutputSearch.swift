import Foundation

public enum TerminalOutputSearch {
  public struct Result: Sendable {
    public let ranges: [NSRange]
    public let isLimited: Bool
  }

  public static func find(in text: String, query: String, limit: Int = 10_000) -> Result {
    guard !query.isEmpty, limit > 0 else { return Result(ranges: [], isLimited: false) }
    let source = text as NSString
    var ranges: [NSRange] = []
    var offset = 0
    while offset < source.length, !Task.isCancelled {
      let range = source.range(
        of: query, options: [.caseInsensitive],
        range: NSRange(location: offset, length: source.length - offset))
      guard range.location != NSNotFound else { break }
      if ranges.count == limit { return Result(ranges: ranges, isLimited: true) }
      ranges.append(range)
      offset = NSMaxRange(range)
    }
    return Result(ranges: ranges, isLimited: false)
  }
}
