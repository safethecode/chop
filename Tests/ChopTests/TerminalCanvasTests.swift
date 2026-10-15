import AppKit
import Testing

@testable import Chop

@MainActor
@Test func canvasReclaimsLegacyGuttersWhenTheWorkspaceFitsAgain() async throws {
  _ = NSApplication.shared
  let canvas = TerminalCanvasView()
  let scroll = TerminalCanvasScrollView(canvas: canvas)
  scroll.scrollerStyle = .legacy
  scroll.minimumDocumentSize = NSSize(width: 561, height: 361)
  scroll.frame = NSRect(x: 0, y: 0, width: 550, height: 350)
  scroll.tile()
  try await Task.sleep(for: .milliseconds(50))
  for size in [NSSize(width: 570, height: 370), NSSize(width: 561, height: 361)] {
    scroll.setFrameSize(size)
    scroll.tile()
    #expect(abs(scroll.contentView.bounds.width - size.width) < 0.5)
    #expect(abs(scroll.contentView.bounds.height - size.height) < 0.5)
    #expect(canvas.frame.size == size)
    #expect(scroll.horizontalScroller?.isHidden != false)
    #expect(scroll.verticalScroller?.isHidden != false)
    try await Task.sleep(for: .milliseconds(50))
  }
}

@MainActor
@Test func canvasResizeKeepsOnlyRequiredAxesWithoutDeferredLayout() {
  _ = NSApplication.shared
  for style in [NSScroller.Style.legacy, .overlay] {
    let canvas = TerminalCanvasView()
    let scroll = TerminalCanvasScrollView(canvas: canvas)
    scroll.scrollerStyle = style
    scroll.minimumDocumentSize = NSSize(width: 561, height: 361)
    let cases: [(NSSize, Bool, Bool)] = [
      (NSSize(width: 800, height: 600), false, false),
      (NSSize(width: 500, height: 600), true, false),
      (NSSize(width: 800, height: 300), false, true),
      (NSSize(width: 500, height: 300), true, true),
      (NSSize(width: 570, height: 350), style == .legacy, true),
      (NSSize(width: 570, height: 370), false, false),
      (NSSize(width: 561, height: 361), false, false),
    ]
    for _ in 0..<5 {
      for (size, horizontal, vertical) in cases {
        scroll.setFrameSize(size)
        scroll.tile()
        #expect(scroll.hasHorizontalScroller == horizontal)
        #expect(scroll.hasVerticalScroller == vertical)
        #expect(canvas.frame.width == max(561, scroll.contentView.bounds.width))
        #expect(canvas.frame.height == max(361, scroll.contentView.bounds.height))
        if !horizontal && !vertical {
          #expect(scroll.contentView.bounds.size == size)
        }
      }
    }
  }
}

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
