import AppKit

@MainActor
final class TerminalCanvasView: NSView {
  override var isFlipped: Bool { true }
}

/// Keep pane minimums in the document while the workspace stays within the display.
@MainActor
final class TerminalCanvasScrollView: NSScrollView {
  var minimumDocumentSize = NSSize.zero { didSet { updateDocumentSize() } }
  private var resizingCanvas = false

  init(canvas: NSView) {
    super.init(frame: .zero)
    documentView = canvas
    autohidesScrollers = false
    scrollerStyle = .overlay
    drawsBackground = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(canvas:).") }

  override func tile() {
    updateDocumentSize()
    super.tile()
  }

  func updateDocumentSize() {
    guard !resizingCanvas, let documentView else { return }
    resizingCanvas = true
    defer { resizingCanvas = false }
    // Start without gutters on every pass. Using the previous clip size feeds a
    // disappearing legacy scroller back into the next document measurement.
    var horizontal = false
    var vertical = false
    var visible = availableContentSize(horizontal: horizontal, vertical: vertical)
    for _ in 0..<3 {
      let nextHorizontal = minimumDocumentSize.width > visible.width
      let nextVertical = minimumDocumentSize.height > visible.height
      if horizontal == nextHorizontal && vertical == nextVertical { break }
      horizontal = nextHorizontal
      vertical = nextVertical
      visible = availableContentSize(horizontal: horizontal, vertical: vertical)
    }
    if hasHorizontalScroller != horizontal { hasHorizontalScroller = horizontal }
    if hasVerticalScroller != vertical { hasVerticalScroller = vertical }
    let size = NSSize(
      width: max(visible.width, minimumDocumentSize.width),
      height: max(visible.height, minimumDocumentSize.height))
    guard documentView.frame.size != size else { return }
    documentView.setFrameSize(size)
    reflectScrolledClipView(contentView)
  }

  private func availableContentSize(horizontal: Bool, vertical: Bool) -> NSSize {
    NSScrollView.contentSize(
      forFrameSize: bounds.size,
      horizontalScrollerClass: horizontal ? NSScroller.self : nil,
      verticalScrollerClass: vertical ? NSScroller.self : nil,
      borderType: borderType, controlSize: .regular, scrollerStyle: scrollerStyle)
  }
}
