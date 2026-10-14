import AppKit

/// A horizontal list keeps every terminal reachable while one pane fills the canvas.
@MainActor
final class TerminalTabBar: NSView {
  private let scroll = NSScrollView()
  private let tabs = NSStackView()
  private let ids: [UUID]
  private var selectedID: UUID
  private var lastViewportSize = NSSize.zero
  private let onSelect: (UUID) -> Void
  private var buttons: [NSButton] = []
  private let addButton: NSButton
  private let closeButton: NSButton

  init(
    panes: [TerminalPaneView], selectedID: UUID, mode: AppearanceMode,
    onSelect: @escaping (UUID) -> Void, onAdd: @escaping () -> Void, onClose: @escaping () -> Void
  ) {
    ids = panes.map(\.id)
    self.selectedID = selectedID
    self.onSelect = onSelect
    addButton = ChopStyle.iconButton(
      "plus", label: "터미널 탭 추가", target: nil, action: #selector(addTab))
    closeButton = ChopStyle.iconButton(
      "xmark", label: "선택한 터미널 닫기", target: nil, action: #selector(closeTab))
    self.onAdd = onAdd
    self.onClose = onClose
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityLabel("터미널 탭")
    tabs.orientation = .horizontal
    tabs.alignment = .centerY
    tabs.spacing = 4
    for (index, pane) in panes.enumerated() {
      let button = NSButton(title: pane.name, target: self, action: #selector(selectTab(_:)))
      button.tag = index
      button.font = ChopStyle.font
      button.bezelStyle = .rounded
      button.setButtonType(.pushOnPushOff)
      button.cell?.lineBreakMode = .byTruncatingTail
      button.translatesAutoresizingMaskIntoConstraints = false
      button.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true
      button.heightAnchor.constraint(equalToConstant: 28).isActive = true
      tabs.addArrangedSubview(button)
      buttons.append(button)
    }
    scroll.documentView = tabs
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    addSubview(scroll)
    for button in [addButton, closeButton] {
      button.target = self
      addSubview(button)
    }
    NSLayoutConstraint.activate([
      addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      closeButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),
      closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    update(panes: panes, selectedID: selectedID)
    applyAppearance(mode)
  }

  private let onAdd: () -> Void
  private let onClose: () -> Void

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Use init(panes:selectedID:mode:onSelect:onAdd:onClose:).")
  }

  func update(panes: [TerminalPaneView], selectedID: UUID) {
    self.selectedID = selectedID
    for (button, id) in zip(buttons, ids) {
      guard let pane = panes.first(where: { $0.id == id }) else { continue }
      button.title = pane.name
      button.toolTip = "\(pane.name) — \(pane.workingDirectory)"
      button.setAccessibilityLabel(pane.name)
      button.state = id == selectedID ? .on : .off
    }
    addButton.isEnabled = panes.count < 16
    closeButton.isEnabled =
      panes.first { $0.id == selectedID }.map { $0.isRunning || panes.count > 1 } ?? false
    needsLayout = true
  }

  func applyAppearance(_ mode: AppearanceMode) {
    appearance = mode.appearance
    layer?.backgroundColor = mode.headerBackground.cgColor
  }

  override func layout() {
    super.layout()
    scroll.frame = NSRect(x: 8, y: 0, width: max(0, bounds.width - 84), height: bounds.height)
    tabs.frame = NSRect(
      origin: .zero, size: NSSize(width: tabs.fittingSize.width, height: bounds.height))
    if lastViewportSize != scroll.contentSize {
      lastViewportSize = scroll.contentSize
      tabs.layoutSubtreeIfNeeded()
      if let index = ids.firstIndex(of: selectedID) {
        tabs.scrollToVisible(buttons[index].frame.insetBy(dx: -4, dy: 0))
      }
    }
  }

  func revealSelection(_ id: UUID) {
    layoutSubtreeIfNeeded()
    guard let index = ids.firstIndex(of: id) else { return }
    tabs.scrollToVisible(buttons[index].frame.insetBy(dx: -4, dy: 0))
  }

  @objc private func selectTab(_ sender: NSButton) { onSelect(ids[sender.tag]) }
  @objc private func addTab() { onAdd() }
  @objc private func closeTab() { onClose() }
}
