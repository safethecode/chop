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

@Test func focusUsesSpatialNeighborsAndStopsAtEdges() {
  let ids = (0..<4).map { _ in UUID() }
  let tree = LayoutNode.preset(.grid, ids: ids)
  let bounds = CGRect(x: 0, y: 0, width: 1100, height: 720)
  #expect(tree.neighbor(of: ids[0], toward: .right, in: bounds) == ids[1])
  #expect(tree.neighbor(of: ids[0], toward: .down, in: bounds) == ids[2])
  #expect(tree.neighbor(of: ids[3], toward: .up, in: bounds) == ids[1])
  #expect(tree.neighbor(of: ids[0], toward: .left, in: bounds) == nil)
  #expect(tree.neighbor(of: ids[3], toward: .down, in: bounds) == nil)
}

@Test func swappingLeavesPreservesGeometryAndRoundTrips() throws {
  let ids = (0..<3).map { _ in UUID() }
  let rootID = UUID()
  let tree = LayoutNode.split(
    id: rootID, axis: .horizontal, ratio: 0.63, first: .pane(ids[0]),
    second: .pane(ids[1]).splitting(ids[1], axis: .vertical, adding: ids[2]))
  let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
  let before = tree.frames(in: bounds)
  let moved = tree.swapping(ids[0], with: ids[2])
  #expect(moved.paneIDs == [ids[2], ids[1], ids[0]])
  #expect(moved.minimumSize == tree.minimumSize)
  #expect(moved.frames(in: bounds)[ids[0]] == before[ids[2]])
  #expect(moved.frames(in: bounds)[ids[2]] == before[ids[0]])
  #expect(moved.frames(in: bounds)[ids[1]] == before[ids[1]])
  #expect(moved.swapping(ids[2], with: ids[0]) == tree)
  #expect(tree.swapping(ids[0], with: UUID()) == tree)
  #expect(tree.swapping(ids[0], with: ids[0]) == tree)
  let restored = try JSONDecoder().decode(LayoutNode.self, from: JSONEncoder().encode(moved))
  #expect(restored == moved)
}
