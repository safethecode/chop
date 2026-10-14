import CoreGraphics
import Foundation

public enum SplitAxis: String, Codable, Sendable {
  case horizontal
  case vertical
}

public enum FocusDirection: Sendable {
  case left, right, up, down
}

public enum LayoutPreset: Int, CaseIterable, Sendable {
  case single, columns, rows, grid
  public var capacity: Int { self == .single ? 1 : self == .grid ? 4 : 2 }
}

/// A layout contains identities, never terminal processes or views.
public indirect enum LayoutNode: Codable, Equatable, Sendable {
  case pane(UUID)
  case split(id: UUID, axis: SplitAxis, ratio: Double, first: LayoutNode, second: LayoutNode)

  public static let paneMinimum = CGSize(width: 280, height: 180)
  public static let divider: CGFloat = 1

  public var paneIDs: [UUID] {
    switch self {
    case .pane(let id): return [id]
    case .split(_, _, _, let first, let second): return first.paneIDs + second.paneIDs
    }
  }

  public var minimumSize: CGSize {
    switch self {
    case .pane: return Self.paneMinimum
    case .split(_, let axis, _, let first, let second):
      let a = first.minimumSize
      let b = second.minimumSize
      return axis == .horizontal
        ? CGSize(width: a.width + b.width + Self.divider, height: max(a.height, b.height))
        : CGSize(width: max(a.width, b.width), height: a.height + b.height + Self.divider)
    }
  }

  public static func preset(_ preset: LayoutPreset, ids: [UUID]) -> LayoutNode {
    precondition(ids.count == preset.capacity)
    func pair(_ a: LayoutNode, _ b: LayoutNode, _ axis: SplitAxis) -> LayoutNode {
      .split(id: UUID(), axis: axis, ratio: 0.5, first: a, second: b)
    }
    let leaves = ids.map { LayoutNode.pane($0) }
    switch preset {
    case .single: return leaves[0]
    case .columns: return pair(leaves[0], leaves[1], .horizontal)
    case .rows: return pair(leaves[0], leaves[1], .vertical)
    case .grid:
      return pair(
        pair(leaves[0], leaves[1], .horizontal), pair(leaves[2], leaves[3], .horizontal), .vertical)
    }
  }

  public func splitting(_ target: UUID, axis: SplitAxis, adding id: UUID) -> LayoutNode {
    switch self {
    case .pane(let existing):
      return existing == target
        ? .split(id: UUID(), axis: axis, ratio: 0.5, first: self, second: .pane(id)) : self
    case .split(let splitID, let direction, let ratio, let first, let second):
      return .split(
        id: splitID, axis: direction, ratio: ratio,
        first: first.splitting(target, axis: axis, adding: id),
        second: second.splitting(target, axis: axis, adding: id))
    }
  }

  public func removing(_ target: UUID) -> LayoutNode? {
    switch self {
    case .pane(let id): return id == target ? nil : self
    case .split(let id, let axis, let ratio, let first, let second):
      let a = first.removing(target)
      let b = second.removing(target)
      if let a, let b { return .split(id: id, axis: axis, ratio: ratio, first: a, second: b) }
      return a ?? b
    }
  }

  /// Exchange leaf positions without changing split geometry or pane identity.
  public func swapping(_ firstID: UUID, with secondID: UUID) -> LayoutNode {
    guard firstID != secondID, paneIDs.contains(firstID), paneIDs.contains(secondID) else {
      return self
    }
    func exchange(_ node: LayoutNode) -> LayoutNode {
      switch node {
      case .pane(let id):
        return .pane(id == firstID ? secondID : id == secondID ? firstID : id)
      case .split(let id, let axis, let ratio, let first, let second):
        return .split(
          id: id, axis: axis, ratio: ratio, first: exchange(first), second: exchange(second))
      }
    }
    return exchange(self)
  }

  public func updatingRatio(_ target: UUID, to value: Double) -> LayoutNode {
    guard value.isFinite else { return self }
    switch self {
    case .pane: return self
    case .split(let id, let axis, let ratio, let first, let second):
      return .split(
        id: id, axis: axis, ratio: id == target ? min(0.95, max(0.05, value)) : ratio,
        first: first.updatingRatio(target, to: value),
        second: second.updatingRatio(target, to: value))
    }
  }

  /// Flipped coordinates: the first child is left or above the second child.
  public func frames(in bounds: CGRect) -> [UUID: CGRect] {
    switch self {
    case .pane(let id): return [id: bounds]
    case .split(_, let axis, let ratio, let first, let second):
      let horizontal = axis == .horizontal
      let total = max(0, (horizontal ? bounds.width : bounds.height) - Self.divider)
      let firstMin = horizontal ? first.minimumSize.width : first.minimumSize.height
      let secondMin = horizontal ? second.minimumSize.width : second.minimumSize.height
      let length = min(max(total * ratio, firstMin), max(firstMin, total - secondMin))
      let a = CGRect(
        x: bounds.minX, y: bounds.minY,
        width: horizontal ? length : bounds.width, height: horizontal ? bounds.height : length)
      let b = CGRect(
        x: horizontal ? bounds.minX + length + Self.divider : bounds.minX,
        y: horizontal ? bounds.minY : bounds.minY + length + Self.divider,
        width: horizontal ? max(0, total - length) : bounds.width,
        height: horizontal ? bounds.height : max(0, total - length))
      return first.frames(in: a).merging(second.frames(in: b)) { a, _ in a }
    }
  }

  public func neighbor(of id: UUID, toward direction: FocusDirection, in bounds: CGRect) -> UUID? {
    let frames = frames(in: bounds)
    guard let origin = frames[id] else { return nil }
    let horizontal = direction == .left || direction == .right
    let positive = direction == .right || direction == .down
    let axisCenter = horizontal ? origin.midX : origin.midY
    let otherCenter = horizontal ? origin.midY : origin.midX
    let candidates = paneIDs.compactMap { candidate -> (UUID, Int, CGFloat)? in
      guard candidate != id, let frame = frames[candidate] else { return nil }
      let delta = (horizontal ? frame.midX : frame.midY) - axisCenter
      guard positive ? delta > 0 : delta < 0 else { return nil }
      let overlap =
        horizontal
        ? min(origin.maxY, frame.maxY) > max(origin.minY, frame.minY)
        : min(origin.maxX, frame.maxX) > max(origin.minX, frame.minX)
      let perpendicular = abs((horizontal ? frame.midY : frame.midX) - otherCenter)
      return (candidate, overlap ? 0 : 1, abs(delta) + perpendicular * 2)
    }
    return candidates.min { a, b in a.1 == b.1 ? a.2 < b.2 : a.1 < b.1 }?.0
  }
}
