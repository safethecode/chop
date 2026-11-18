import AppKit
import Testing

@testable import Chop

@MainActor
@Test func unavailableClipboardDoesNotCrashEngineOrRequestItDuringInitialization() {
  var requests = 0
  let engine = TerminalEngine(clipboard: {
    requests += 1
    return nil
  })
  #expect(requests == 0)
  #expect(engine.readClipboardText().isEmpty)
  #expect(!engine.writeClipboardText("클립보드 서비스 없음"))
  #expect(requests == 2)
}
