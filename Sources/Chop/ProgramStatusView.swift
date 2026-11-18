import AppKit
import ChopCore

extension ProgramStatus {
  var statusLabel: String {
    switch state {
    case .idle: "대기 중"
    case .working: progress.map { "작업 중 \($0)%" } ?? "작업 중"
    case .done: "완료"
    case .error: "실패"
    case .blocked:
      switch kind {
      case .permission: "승인 필요"
      case .question: "답변 필요"
      case .auth: "로그인 필요"
      case nil: "확인 필요"
      }
    case .clear: ""
    }
  }

  var statusSymbol: String {
    switch state {
    case .working: "hourglass"
    case .blocked: "hand.raised"
    case .done: "checkmark.circle"
    case .error: "exclamationmark.circle"
    case .idle, .clear: "circle"
    }
  }

  var statusColor: NSColor {
    switch state {
    case .working: .systemBlue
    case .blocked: .systemOrange
    case .done: .systemGreen
    case .error: .systemRed
    case .idle, .clear: .secondaryLabelColor
    }
  }

  var statusDescription: String {
    [app, statusLabel, title, message].compactMap { $0 }.filter { !$0.isEmpty }
      .map { String($0.unicodeScalars.filter { $0.properties.generalCategory != .format }) }
      .joined(separator: " · ")
  }
}

@MainActor
final class ProgramStatusView: NSView {
  private let icon = NSImageView()
  private let label = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    icon.setAccessibilityElement(false)
    icon.setAccessibilityHidden(true)
    label.setAccessibilityElement(false)
    label.setAccessibilityHidden(true)
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.lineBreakMode = .byTruncatingTail
    let row = NSStackView(views: [icon, label])
    row.spacing = 4
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor),
      row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: topAnchor),
      row.bottomAnchor.constraint(equalTo: bottomAnchor),
      icon.widthAnchor.constraint(equalToConstant: 14),
      icon.heightAnchor.constraint(equalToConstant: 14),
    ])
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(frame:).") }

  func update(_ status: ProgramStatus?, mode: AppearanceMode) {
    isHidden = status == nil
    label.stringValue = status?.statusLabel ?? ""
    label.textColor = mode.secondaryForeground
    icon.image = status.flatMap {
      NSImage(systemSymbolName: $0.statusSymbol, accessibilityDescription: nil)
    }
    icon.contentTintColor = status?.statusColor
    toolTip = status?.statusDescription
    setAccessibilityLabel(status?.statusDescription)
  }
}
