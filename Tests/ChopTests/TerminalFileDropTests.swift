import AppKit
import ChopCore
import Testing

@testable import Chop

@MainActor
@Test func terminalFileDropReadsNativeFileURLsWithoutAcceptingPlainText() throws {
  _ = NSApplication.shared
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  let urls = [URL(fileURLWithPath: "/tmp/폴더 경로"), URL(fileURLWithPath: "/tmp/a'b.txt")]
  #expect(pasteboard.writeObjects(urls.map { $0 as NSURL }))
  #expect(TerminalView.fileDropText(from: pasteboard) == TerminalFileDrop.text(for: urls))
  pasteboard.clearContents()
  pasteboard.setString("plain command text", forType: .string)
  #expect(TerminalView.fileDropText(from: pasteboard) == nil)
  pasteboard.clearContents()
  #expect(pasteboard.writeObjects([URL(string: "https://example.com")! as NSURL]))
  #expect(TerminalView.fileDropText(from: pasteboard) == nil)
}
