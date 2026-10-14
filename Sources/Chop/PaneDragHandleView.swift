import AppKit

struct PaneDragPreview {
  let frame: NSRect
  let components: [NSDraggingImageComponent]
}

@MainActor
final class PaneDragHandleView: NSImageView, NSDraggingSource {
  static let pasteboardType = NSPasteboard.PasteboardType("com.safethecode.chop.pane")
  let paneID: UUID
  let workspaceID: UUID
  var onFocus: (() -> Void)?
  var onPrepareDrag: ((NSView) -> PaneDragPreview?)?
  var onDragBegan: (() -> Void)?
  var onDragEnded: (() -> Void)?
  private(set) var previewSize: NSSize?
  private var isDragging = false

  init(paneID: UUID, workspaceID: UUID) {
    self.paneID = paneID
    self.workspaceID = workspaceID
    super.init(frame: .zero)
    image = NSImage(
      systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
      accessibilityDescription: "칸 이동"
    )?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    contentTintColor = .secondaryLabelColor
    imageScaling = .scaleProportionallyDown
    toolTip = "다른 칸으로 드래그해 자리 바꾸기"
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 28),
      heightAnchor.constraint(equalToConstant: 28),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(paneID:workspaceID:).") }

  override func resetCursorRects() {
    super.resetCursorRects()
    if !isHidden { addCursorRect(bounds, cursor: .openHand) }
  }

  override func mouseDown(with event: NSEvent) { onFocus?() }

  override func mouseDragged(with event: NSEvent) {
    guard !isHidden, !isDragging, let preview = onPrepareDrag?(self) else { return }
    isDragging = true
    previewSize = preview.frame.size
    let pasteboard = NSPasteboardItem()
    pasteboard.setString(paneID.uuidString, forType: Self.pasteboardType)
    let item = NSDraggingItem(pasteboardWriter: pasteboard)
    item.draggingFrame = preview.frame
    item.imageComponentsProvider = { preview.components }
    onDragBegan?()
    let session = beginDraggingSession(with: [item], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail =
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .withinApplication ? .move : []
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    isDragging = false
    previewSize = nil
    onDragEnded?()
  }
}
