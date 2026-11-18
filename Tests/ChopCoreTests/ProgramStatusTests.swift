import Foundation
import Testing

@testable import ChopCore

@Test func programStatusReadsReportsWithoutGuessingFromTheirMessages() throws {
  let message = Data("배포를 진행할까요?".utf8).base64EncodedString().replacingOccurrences(
    of: "=", with: "")
  let report = try #require(
    ProgramStatus.parse(
      "state=idle:unknown=ignored:state=blocked:kind=permission:app=codex:progress=42:msg=\(message)"
    ))
  #expect(report.state == .blocked && report.kind == .permission && report.progress == 42)
  #expect(report.message == "배포를 진행할까요?" && report.app == "codex" && report.id.isEmpty)
  #expect(ProgramStatus.parse(" state = working : progress = 101 ")?.progress == nil)
  #expect(ProgramStatus.parse("state=done:kind=auth:progress=99")?.kind == nil)
  #expect(ProgramStatus.parse("state=done:kind=auth:progress=99")?.progress == nil)
  #expect(ProgramStatus.parse("state=future") == nil)
  #expect(ProgramStatus.parse("msg=ZG9uZQ==") == nil)
  #expect(ProgramStatus.parse("?") == nil)
}

@Test func programStatusRejectsInvalidIDsTextAndByteLimits() {
  for id in [
    "", "/a", "a/", "a//b", "a@b", String(repeating: "a", count: 33),
    "a/b/c/d/e/f/g/h/i",
  ] {
    #expect(ProgramStatus.parse("state=done:id=\(id)") == nil, "Invalid id: \(id)")
  }
  #expect(ProgramStatus.parse("state=done:id=a/b/c/d/e/f/g/h") != nil)
  #expect(ProgramStatus.parse("state=done:msg=not_base64") == nil)
  for text in ["줄\n바꿈", "탭\t문자", "\u{0085}", String(repeating: "가", count: 683)] {
    let encoded = Data(text.utf8).base64EncodedString()
    #expect(ProgramStatus.parse("state=done:msg=\(encoded)") == nil)
  }
  let title = Data(String(repeating: "a", count: 193).utf8).base64EncodedString()
  #expect(ProgramStatus.parse("state=done:title=\(title)") == nil)
  #expect(ProgramStatus.parse("state=done:app=" + String(repeating: "a", count: 33)) == nil)
  #expect(ProgramStatus.parse("state=done:unknown=" + String(repeating: "a", count: 4087)) == nil)
}

@Test func programStatusKeepsChildAttentionAndClearsOnlyTheAddressedSubtree() throws {
  var store = ProgramStatusRecords()
  func report(_ body: String) throws -> ProgramStatus { try #require(ProgramStatus.parse(body)) }
  store.apply(try report("state=idle:app=codex"), observed: false)
  store.apply(try report("state=working:id=build:app=cargo"), observed: false)
  store.apply(try report("state=blocked:kind=question:id=build/tests"), observed: false)
  store.apply(try report("state=done:id=builder"), observed: false)
  #expect(store.display?.id == "build/tests" && store.display?.app == "cargo")
  store.apply(try report("state=clear:id=build"), observed: false)
  #expect(store.records.count == 2 && store.records["builder"] != nil)
  #expect(store.display?.state == .done)
  store.acknowledge()
  #expect(store.display?.state == .idle)
  store.apply(try report("state=clear"), observed: false)
  #expect(store.records.isEmpty && store.display == nil)
}

@Test func programStatusPromptLifetimeAndNotificationsStayDistinct() throws {
  var store = ProgramStatusRecords()
  let working = try #require(ProgramStatus.parse("state=working"))
  let blocked = try #require(ProgramStatus.parse("state=blocked:kind=permission"))
  let done = try #require(ProgramStatus.parse("state=done"))
  #expect(store.apply(working, observed: false) == nil)
  #expect(store.apply(blocked, observed: false) != nil)
  #expect(store.apply(blocked, observed: false) == nil)
  store.beginPrompt()
  #expect(store.display == nil)
  #expect(store.apply(done, observed: false) != nil)
  store.beginPrompt()
  #expect(store.display?.state == .done)
  store.acknowledge()
  #expect(store.display == nil && store.records[""]?.state == .done)
  store.apply(working, observed: true)
  #expect(store.apply(done, observed: true) == nil && store.display == nil)
}

@Test func programStatusBoundsTheRecordCountWithoutOverwritingAnotherRecord() throws {
  var store = ProgramStatusRecords()
  for index in 0..<64 {
    store.apply(try #require(ProgramStatus.parse("state=working:id=job\(index)")), observed: false)
  }
  #expect(
    store.apply(try #require(ProgramStatus.parse("state=blocked:id=overflow")), observed: false)
      == nil)
  #expect(store.records.count == 64 && store.records["overflow"] == nil)
  store.apply(try #require(ProgramStatus.parse("state=done:id=job0")), observed: false)
  #expect(store.records["job0"]?.state == .done)
  store.apply(try #require(ProgramStatus.parse("state=clear")), observed: false)
  #expect(store.records.isEmpty)
}
