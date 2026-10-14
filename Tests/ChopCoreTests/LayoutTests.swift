import CoreGraphics
import Foundation
import Testing

@testable import ChopCore

@Test func splitAndCollapsePreserveOtherIdentities() throws {
  let a = UUID()
  let b = UUID()
  let c = UUID()
  let tree = LayoutNode.pane(a).splitting(a, axis: .horizontal, adding: b)
    .splitting(b, axis: .vertical, adding: c)
  #expect(tree.paneIDs == [a, b, c])
  let collapsed = try #require(tree.removing(b))
  #expect(collapsed.paneIDs == [a, c])
  #expect(collapsed.minimumSize == CGSize(width: 561, height: 180))
  #expect(LayoutNode.pane(a).removing(a) == nil)
}

@Test func presetsHaveUsableNonoverlappingFrames() {
  for preset in LayoutPreset.allCases {
    let ids = (0..<preset.capacity).map { _ in UUID() }
    let tree = LayoutNode.preset(preset, ids: ids)
    let frames = tree.frames(in: CGRect(origin: .zero, size: tree.minimumSize))
    #expect(tree.paneIDs == ids)
    #expect(frames.count == preset.capacity)
    for frame in frames.values {
      #expect(frame.width >= 280)
      #expect(frame.height >= 180)
    }
    for a in ids { for b in ids where a != b { #expect(!frames[a]!.intersects(frames[b]!)) } }
  }
}

@Test func resizeRatioIsBoundedAndRoundTrips() throws {
  let id = UUID()
  let tree = LayoutNode.split(
    id: id, axis: .horizontal, ratio: 0.5,
    first: .pane(UUID()), second: .pane(UUID()))
  #expect(tree.updatingRatio(id, to: .nan) == tree)
  let resized = tree.updatingRatio(id, to: 0.7)
  let restored = try JSONDecoder().decode(LayoutNode.self, from: JSONEncoder().encode(resized))
  #expect(restored == resized)
  let frames = resized.frames(in: CGRect(x: 0, y: 0, width: 1001, height: 600))
  #expect(frames[tree.paneIDs[0]]?.width == 700)
}
