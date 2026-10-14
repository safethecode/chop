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
  private var resizeScheduled = false

  init(canvas: NSView) {
    super.init(frame: .zero)
    documentView = canvas
    hasHorizontalScroller = true
    hasVerticalScroller = true
    autohidesScrollers = true
    scrollerStyle = .overlay
    drawsBackground = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(canvas:).") }

  override func tile() {
    super.tile()
    scheduleDocumentResize()
  }

  override func layout() {
    super.layout()
    scheduleDocumentResize()
  }

  private func scheduleDocumentResize() {
    guard !resizeScheduled else { return }
    resizeScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      resizeScheduled = false
      updateDocumentSize()
    }
  }

  func updateDocumentSize() {
    guard !resizingCanvas, let documentView else { return }
    resizingCanvas = true
    defer { resizingCanvas = false }
    let visible = contentView.bounds.size
    let size = NSSize(
      width: max(visible.width, minimumDocumentSize.width),
      height: max(visible.height, minimumDocumentSize.height))
    guard documentView.frame.size != size else { return }
    documentView.setFrameSize(size)
    // Native tiling can change the other axis when legacy scrollers appear.
    // Let AppKit finish its display cycle before settling the document again.
    reflectScrolledClipView(contentView)
    scheduleDocumentResize()
  }
}
