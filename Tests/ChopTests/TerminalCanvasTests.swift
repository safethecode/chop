import AppKit
import Testing

@testable import Chop

@MainActor
@Test func canvasOverflowDoesNotCreateAnUnnecessaryScrollAxis() async throws {
  _ = NSApplication.shared
  let canvas = TerminalCanvasView()
  let scroll = TerminalCanvasScrollView(canvas: canvas)
  scroll.scrollerStyle = .legacy
  scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
  scroll.minimumDocumentSize = NSSize(width: 1123, height: 180)
  scroll.tile()
  try await Task.sleep(for: .milliseconds(50))
  #expect(canvas.frame.width >= 1123)
  #expect(abs(canvas.frame.height - scroll.contentView.bounds.height) < 0.5)
  #expect(scroll.verticalScroller?.isHidden != false)
  scroll.minimumDocumentSize = NSSize(width: 280, height: 1085)
  scroll.tile()
  try await Task.sleep(for: .milliseconds(50))
  #expect(canvas.frame.height >= 1085)
  #expect(abs(canvas.frame.width - scroll.contentView.bounds.width) < 0.5)
  #expect(scroll.horizontalScroller?.isHidden != false)
}
