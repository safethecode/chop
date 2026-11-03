import AppKit
import Testing

@testable import Chop

@MainActor
@Test func localServerButtonOpensOnlyOnUserActionAndClearsWhenStopped() throws {
  _ = NSApplication.shared
  let button = LocalServerButton()
  let url = try #require(URL(string: "http://localhost:3000"))
  var opened: [URL] = []
  button.openURL = { opened.append($0) }
  button.update([url])
  #expect(!button.isHidden && button.title == "localhost:3000" && opened.isEmpty)
  #expect(button.sendAction(button.action, to: button.target))
  #expect(opened == [url])
  button.update([])
  #expect(button.isHidden)
  #expect(button.sendAction(button.action, to: button.target))
  #expect(opened == [url])
}
