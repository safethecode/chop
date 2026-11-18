import Foundation
import Testing

@testable import ChopCore

@Test func outputSearchHandlesUnicodeLiteralTextAndCase() {
  let text = "🙂 실패\n실패한 빌드\n실패\nERROR.log errorXlog"
  let result = TerminalOutputSearch.find(in: text, query: "실패")
  #expect(result.ranges.count == 3)
  #expect(result.ranges.first == NSRange(location: 3, length: 2))
  #expect(result.ranges.allSatisfy { (text as NSString).substring(with: $0) == "실패" })
  let literal = TerminalOutputSearch.find(in: text, query: "error.log")
  #expect(literal.ranges.count == 1)
  #expect((text as NSString).substring(with: literal.ranges[0]) == "ERROR.log")
  let decomposed = "실패".decomposedStringWithCanonicalMapping
  let normalized = TerminalOutputSearch.find(in: "🙂 \(decomposed)", query: "실패")
  #expect(normalized.ranges == [NSRange(location: 3, length: (decomposed as NSString).length)])
}

@Test func outputSearchBoundsLargeResultsAndDistinguishesAnExactLimit() {
  let result = TerminalOutputSearch.find(in: String(repeating: "출력\n", count: 100_000), query: "출력")
  #expect(result.ranges.count == 10_000 && result.isLimited)
  let exact = TerminalOutputSearch.find(in: "a a", query: "a", limit: 2)
  #expect(exact.ranges.count == 2 && !exact.isLimited)
  #expect(TerminalOutputSearch.find(in: "a", query: "").ranges.isEmpty)
  #expect(TerminalOutputSearch.find(in: "a", query: "a", limit: 0).ranges.isEmpty)
}
