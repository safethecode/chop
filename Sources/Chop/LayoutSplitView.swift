import AppKit
import ChopCore

@MainActor
final class LayoutSplitView: NSSplitView, NSSplitViewDelegate {
  let splitID: UUID
  private var ratio: Double
  private let firstMinimum: CGSize
  private let secondMinimum: CGSize
  private var applying = false
  var onRatioChange: ((UUID, Double) -> Void)?

  override var isFlipped: Bool { true }
  override var dividerThickness: CGFloat { LayoutNode.divider }

  init(
    id: UUID, axis: SplitAxis, ratio: Double, first: NSView, second: NSView,
    firstMinimum: CGSize, secondMinimum: CGSize
  ) {
    self.splitID = id
    self.ratio = ratio
    self.firstMinimum = firstMinimum
    self.secondMinimum = secondMinimum
    super.init(frame: .zero)
    isVertical = axis == .horizontal
    dividerStyle = .thin
    delegate = self
    addSubview(first)
    addSubview(second)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(id:axis:ratio:first:second:).") }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    guard subviews.count == 2 else { return }
    applying = true
    defer { applying = false }
    let total = max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness)
    let minA = isVertical ? firstMinimum.width : firstMinimum.height
    let minB = isVertical ? secondMinimum.width : secondMinimum.height
    let length = min(max(total * ratio, minA), max(minA, total - minB))
    subviews[0].frame = NSRect(
      x: 0, y: 0, width: isVertical ? length : bounds.width,
      height: isVertical ? bounds.height : length)
    subviews[1].frame = NSRect(
      x: isVertical ? length + dividerThickness : 0,
      y: isVertical ? 0 : length + dividerThickness,
      width: isVertical ? max(0, total - length) : bounds.width,
      height: isVertical ? bounds.height : max(0, total - length))
  }

  func splitView(
    _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat {
    isVertical ? firstMinimum.width : firstMinimum.height
  }

  func splitView(
    _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat {
    (isVertical ? bounds.width - secondMinimum.width : bounds.height - secondMinimum.height)
      - dividerThickness
  }

  func splitViewDidResizeSubviews(_ notification: Notification) {
    guard !applying, subviews.count == 2 else { return }
    let total = (isVertical ? bounds.width : bounds.height) - dividerThickness
    guard total > 0 else { return }
    ratio = (isVertical ? subviews[0].frame.width : subviews[0].frame.height) / total
    onRatioChange?(splitID, ratio)
  }
}
