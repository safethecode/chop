import Foundation

public struct ProgramStatus: Equatable, Sendable {
  public enum State: String, Sendable {
    case idle, working, done, blocked, error, clear

    var priority: Int {
      switch self {
      case .blocked: 5
      case .error: 4
      case .working: 3
      case .done: 2
      case .idle: 1
      case .clear: 0
      }
    }
  }

  public enum Kind: String, Sendable { case permission, question, auth }
  public let id: String
  public let state: State
  public let kind: Kind?
  public internal(set) var app: String?
  public let title: String?
  public let message: String?
  public let progress: Int?

  /// Program Status Protocol 0.4. Invalid reports never alter an existing record.
  public static func parse(_ body: String) -> Self? {
    guard body.utf8.count <= 4087 else { return nil }
    var values: [String: String] = [:]
    var decoded: [String: String] = [:]
    for pair in body.split(separator: ":", omittingEmptySubsequences: false) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let first = parts.first else { continue }
      let key = first.trimmingCharacters(in: .whitespacesAndNewlines)
      guard parts.count == 2 else {
        if key == "id" { return nil }
        continue
      }
      let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
      if key == "id", !validID(value) { return nil }
      guard !key.isEmpty, key.utf8.allSatisfy({ (97...122).contains($0) }),
        value.utf8.allSatisfy({
          (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
            || "_.,+/=-".utf8.contains($0)
        })
      else { continue }
      switch key {
      case "msg", "title":
        let limit = key == "msg" ? 2048 : 192
        guard let text = decode(value, limit: limit) else { return nil }
        decoded[key] = text
      case "app":
        guard value.utf8.count <= 32 else { return nil }
        values[key] = validSegment(value) ? value : nil
      case "id", "state", "kind", "progress": values[key] = value
      default: continue
      }
    }
    guard let raw = values["state"], let state = State(rawValue: raw) else { return nil }
    let progress = values["progress"].flatMap { value -> Int? in
      guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(value), (0...100).contains(number)
      else { return nil }
      return number
    }
    return Self(
      id: values["id"] ?? "", state: state,
      kind: state == .blocked ? values["kind"].flatMap(Kind.init(rawValue:)) : nil,
      app: values["app"], title: decoded["title"], message: decoded["msg"],
      progress: state == .working || state == .blocked ? progress : nil)
  }

  private static func validSegment(_ value: String) -> Bool {
    (1...32).contains(value.utf8.count)
      && value.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
          || "_.+-".utf8.contains($0)
      }
  }

  private static func validID(_ value: String) -> Bool {
    let segments = value.split(separator: "/", omittingEmptySubsequences: false)
    return value.utf8.count <= 128 && (1...8).contains(segments.count)
      && segments.allSatisfy { validSegment(String($0)) }
  }

  private static func decode(_ encoded: String, limit: Int) -> String? {
    guard encoded.utf8.count <= ((limit + 2) / 3) * 4 else { return nil }
    let padded = encoded + String(repeating: "=", count: (4 - encoded.utf8.count % 4) % 4)
    guard let data = Data(base64Encoded: padded), data.count <= limit,
      let text = String(data: data, encoding: .utf8),
      !text.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
    else { return nil }
    return text
  }
}

public struct ProgramStatusRecords: Sendable {
  public private(set) var records: [String: ProgramStatus] = [:]
  private var seen: Set<String> = []

  public init() {}

  public var display: ProgramStatus? {
    var result = records.values.filter {
      !(($0.state == .done || $0.state == .error) && seen.contains($0.id))
    }.sorted {
      $0.state.priority == $1.state.priority ? $0.id < $1.id : $0.state.priority > $1.state.priority
    }.first
    if let record = result, record.app == nil {
      var path = record.id
      while !path.isEmpty {
        path = path.split(separator: "/").dropLast().joined(separator: "/")
        if let app = records[path]?.app {
          result?.app = app
          break
        }
      }
    }
    return result
  }

  /// Returns an unseen transition that may warrant attention, never an input action.
  @discardableResult
  public mutating func apply(_ report: ProgramStatus, observed: Bool) -> ProgramStatus? {
    if report.state == .clear {
      if report.id.isEmpty {
        self = Self()
        return nil
      }
      records = records.filter { $0.key != report.id && !$0.key.hasPrefix(report.id + "/") }
      seen.formIntersection(records.keys)
      return nil
    }
    let previous = records[report.id]
    guard previous != report, previous != nil || records.count < 64 else { return nil }
    records[report.id] = report
    seen.remove(report.id)
    if observed, report.state == .done || report.state == .error { seen.insert(report.id) }
    guard !observed else { return nil }
    switch report.state {
    case .blocked:
      return previous?.state != .blocked || previous?.kind != report.kind ? report : nil
    case .done, .error:
      return previous?.state != report.state ? report : nil
    default: return nil
    }
  }

  public mutating func acknowledge() {
    seen.formUnion(records.values.filter { $0.state == .done || $0.state == .error }.map(\.id))
  }

  public mutating func beginPrompt() {
    records = records.filter { $0.value.state == .done || $0.value.state == .error }
    seen.formIntersection(records.keys)
  }
}
