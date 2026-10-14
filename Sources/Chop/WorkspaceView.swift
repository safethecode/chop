import AppKit
import ChopCore

@MainActor
final class WorkspaceView: NSView {
  let engine: TerminalEngine
  private(set) var layout: LayoutNode
  private(set) var panes: [UUID: TerminalPaneView] = [:]
  private(set) var focusedID: UUID
  private(set) var maximizedID: UUID?
  var focusedPane: TerminalPaneView { panes[focusedID]! }
  var needsConfirmClose: Bool { panes.values.contains { $0.needsConfirmClose } }
  var onChange: (() -> Void)?
  var onMinimumSizeChange: ((CGSize) -> Void)?
  var onMissingDirectories: (([String]) -> Void)?
  private var nextName = 1
  private let canvas = NSView()
  private var root: NSView?
  private let presets = NSSegmentedControl(
    labels: ["1", "좌우", "상하", "4"],
    trackingMode: .selectOne, target: nil, action: nil)
  private let editButton = NSButton(title: "레이아웃 편집", target: nil, action: nil)
  private(set) var isEditing = false
  private var restoredRunningIDs: [UUID] = []

  init(engine: TerminalEngine, snapshot: WorkspaceSnapshot? = nil) {
    self.engine = engine
    let valid = snapshot.flatMap { (try? $0.validate()) != nil ? $0 : nil }
    var ids = valid?.layout.paneIDs ?? (0..<4).map { _ in UUID() }
    // Upgrade the old blank single-pane start while retaining its name and cwd.
    let useDefaultGrid =
      valid == nil || (valid?.panes.count == 1 && valid?.panes.first?.wasRunning == false)
    if useDefaultGrid {
      while ids.count < 4 { ids.append(UUID()) }
      layout = .preset(.grid, ids: ids)
    } else {
      layout = valid!.layout
    }
    focusedID = valid?.focusedID ?? ids[0]
    super.init(frame: .zero)
    wantsLayer = true
    applyAppearance(engine.appearanceMode)
    configureToolbar()
    for id in ids {
      let saved = valid?.panes.first { $0.id == id }
      addPane(id, directory: saved?.workingDirectory, name: saved?.name)
      if saved?.wasRunning == true { restoredRunningIDs.append(id) }
    }
    rebuild()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(engine:).") }

  func applyAppearance(_ mode: AppearanceMode) {
    engine.applyAppearance(mode)
    appearance = mode.appearance
    layer?.backgroundColor = mode.background.cgColor
    // Hidden panes are retained in this dictionary during zoom.
    for pane in panes.values { pane.applyAppearance() }
  }

  private func addPane(_ id: UUID, directory: String? = nil, name: String? = nil) {
    while panes.values.contains(where: { $0.name == "터미널 \(nextName)" }) { nextName += 1 }
    let pane = TerminalPaneView(
      engine: engine, id: id, name: name ?? "터미널 \(nextName)",
      workingDirectory: directory ?? FileManager.default.homeDirectoryForCurrentUser.path)
    nextName += 1
    pane.onFocus = { [weak self] in self?.didFocus(id) }
    pane.onChange = { [weak self] in
      self?.refreshControls()
      self?.onChange?()
    }
    pane.onSplitRequested = { [weak self] axis in self?.split(id, axis: axis) }
    pane.canSplit = { [weak self] axis in self?.canSplit(id, axis: axis) ?? false }
    pane.onRemoveRequested = { [weak self] in self?.removeEmptyPane(id) }
    pane.onZoomRequested = { [weak self] in self?.toggleZoom(id) }
    pane.onDirectoryFallback = { [weak self] path in self?.reportMissingDirectories([path]) }
    pane.isEditing = isEditing
    panes[id] = pane
  }

  @discardableResult
  func applyPreset(_ preset: LayoutPreset) -> Bool {
    let existing = layout.paneIDs
    let running = existing.filter { panes[$0]?.isRunning == true }
    guard running.count <= preset.capacity else {
      refreshControls()
      return false
    }
    maximizedID = nil
    var retained = Set(running)
    for id in existing where retained.count < preset.capacity { retained.insert(id) }
    var ids = existing.filter { retained.contains($0) }
    while ids.count < preset.capacity {
      let id = UUID()
      ids.append(id)
      addPane(id)
    }
    for id in existing where !ids.contains(id) {
      panes[id]?.removeFromSuperview()
      panes.removeValue(forKey: id)
    }
    layout = .preset(preset, ids: ids)
    if !ids.contains(focusedID) { focusedID = ids[0] }
    rebuild()
    return true
  }

  func split(_ id: UUID, axis: SplitAxis) {
    guard let source = panes[id], canSplit(id, axis: axis) else { return }
    let newID = UUID()
    let proposed = layout.splitting(id, axis: axis, adding: newID)
    addPane(newID, directory: source.workingDirectory)
    layout = proposed
    maximizedID = nil
    focusedID = newID
    rebuild()
    panes[newID]?.openTerminal()
  }

  func canSplit(_ id: UUID, axis: SplitAxis) -> Bool {
    guard panes[id] != nil, layout.paneIDs.count < 16 else { return false }
    let minimum = layout.splitting(id, axis: axis, adding: UUID()).minimumSize
    guard let screen = window?.screen else { return true }
    return minimum.width <= screen.visibleFrame.width
      && minimum.height + 80 <= screen.visibleFrame.height
  }

  @objc func splitRight() { split(focusedID, axis: .horizontal) }
  @objc func splitDown() { split(focusedID, axis: .vertical) }

  @objc func toggleEditing() {
    if maximizedID != nil {
      maximizedID = nil
      rebuild()
    }
    isEditing.toggle()
    for pane in panes.values { pane.isEditing = isEditing }
    refreshControls()
  }

  func closeAll() {
    for pane in panes.values { pane.closeTerminal() }
  }

  func snapshot() -> WorkspaceSnapshot {
    WorkspaceSnapshot(
      layout: layout,
      panes: layout.paneIDs.compactMap { id in
        guard let pane = panes[id] else { return nil }
        return PaneSnapshot(
          id: id, name: pane.name, workingDirectory: pane.workingDirectory,
          wasRunning: pane.isRunning)
      }, focusedID: focusedID)
  }

  func startRestoredTerminals() {
    var ids = restoredRunningIDs
    restoredRunningIDs.removeAll()
    var selected = focusedID
    // A newly opened workspace is immediately usable, including an all-empty save.
    if ids.isEmpty, !panes.values.contains(where: { $0.isRunning }),
      let first = layout.paneIDs.first
    {
      ids = [first]
      selected = first
    }
    let missing = layout.paneIDs.compactMap { panes[$0]?.resolveWorkingDirectory() }
    if !missing.isEmpty { reportMissingDirectories(missing) }
    for id in ids { panes[id]?.openTerminal() }
    panes[selected]?.focus()
  }

  private func reportMissingDirectories(_ paths: [String]) {
    if let onMissingDirectories {
      onMissingDirectories(paths)
      return
    }
    let alert = NSAlert()
    alert.messageText = "이전 작업 폴더를 열 수 없어요"
    alert.informativeText =
      "해당 칸은 홈 폴더에서 엽니다.\n\n" + Array(Set(paths)).sorted().joined(separator: "\n")
    alert.addButton(withTitle: "확인")
    alert.runModal()
  }

  func refreshMinimumSize() { onMinimumSizeChange?(layout.minimumSize) }

  private func didFocus(_ id: UUID) {
    guard panes[id] != nil else { return }
    focusedID = id
    for pane in panes.values { pane.isFocused = pane.id == id }
    onChange?()
  }

  func moveFocus(_ direction: FocusDirection) {
    guard let id = layout.neighbor(of: focusedID, toward: direction, in: canvas.bounds) else {
      return
    }
    focusedID = id
    if maximizedID != nil {
      maximizedID = id
      rebuild()
    }
    focusedPane.focus()
  }

  func toggleZoom(_ id: UUID? = nil) {
    let target = id ?? focusedID
    guard panes[target] != nil, layout.paneIDs.count > 1 else { return }
    maximizedID = maximizedID == target ? nil : target
    focusedID = target
    rebuild()
  }

  func removeEmptyPane(_ id: UUID) {
    guard let pane = panes[id], !pane.isRunning, layout.paneIDs.count > 1,
      let replacement = layout.removing(id)
    else { return }
    pane.removeFromSuperview()
    panes.removeValue(forKey: id)
    layout = replacement
    if maximizedID == id { maximizedID = nil }
    if focusedID == id { focusedID = replacement.paneIDs[0] }
    rebuild()
  }

  @discardableResult
  func renameFocused(to name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 64,
      !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return false }
    focusedPane.name = trimmed
    return true
  }

  @objc func requestRename() {
    let field = NSTextField(string: focusedPane.name)
    field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
    field.font = ChopStyle.font
    field.setAccessibilityLabel("칸 이름")
    let alert = NSAlert()
    alert.messageText = "칸 이름 바꾸기"
    alert.informativeText = "최대 64자로 입력해 주세요."
    alert.accessoryView = field
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "변경")
    alert.buttons[0].keyEquivalent = "\u{1b}"
    alert.buttons[1].keyEquivalent = "\r"
    alert.window.initialFirstResponder = field
    while alert.runModal() == .alertSecondButtonReturn {
      if renameFocused(to: field.stringValue) { break }
      alert.informativeText = "이름을 줄바꿈 없이 1~64자로 입력해 주세요."
    }
    focusedPane.focus()
  }

  private func rebuild() {
    // Reparent existing pane objects; their Ghostty surfaces and PTYs remain alive.
    for pane in panes.values { pane.removeFromSuperview() }
    root?.removeFromSuperview()
    func makeView(_ node: LayoutNode) -> NSView {
      switch node {
      case .pane(let id): return panes[id]!
      case .split(let id, let axis, let ratio, let first, let second):
        let split = LayoutSplitView(
          id: id, axis: axis, ratio: ratio,
          first: makeView(first), second: makeView(second),
          firstMinimum: first.minimumSize, secondMinimum: second.minimumSize)
        split.onRatioChange = { [weak self] id, ratio in
          guard let self else { return }
          self.layout = self.layout.updatingRatio(id, to: ratio)
          self.onChange?()
        }
        return split
      }
    }
    for pane in panes.values {
      pane.canRemove = panes.count > 1
      pane.canZoom = panes.count > 1
      pane.isZoomed = maximizedID == pane.id
    }
    let view = makeView(maximizedID.map { .pane($0) } ?? layout)
    canvas.addSubview(view)
    view.frame = canvas.bounds
    view.autoresizingMask = [.width, .height]
    root = view
    onMinimumSizeChange?(layout.minimumSize)
    layoutSubtreeIfNeeded()
    focusedPane.focus()
    for pane in panes.values {
      pane.terminal?.setVisible(maximizedID == nil || maximizedID == pane.id)
    }
    refreshControls()
    onChange?()
  }

  private func configureToolbar() {
    presets.target = self
    presets.font = ChopStyle.font
    presets.action = #selector(selectPreset(_:))
    presets.setAccessibilityLabel("레이아웃 프리셋")
    editButton.target = self
    editButton.action = #selector(toggleEditing)
    editButton.setButtonType(.pushOnPushOff)
    editButton.bezelStyle = .rounded
    editButton.font = ChopStyle.font
    let spacer = NSView()
    let toolbar = NSStackView(views: [presets, spacer, editButton])
    toolbar.orientation = .horizontal
    toolbar.distribution = .fill
    toolbar.spacing = 12
    toolbar.alignment = .centerY
    for view in [toolbar, canvas] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      toolbar.topAnchor.constraint(equalTo: topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 48),
      canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
      canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
      canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @objc private func selectPreset(_ sender: NSSegmentedControl) {
    guard let preset = LayoutPreset(rawValue: sender.selectedSegment) else { return }
    applyPreset(preset)
  }

  private func refreshControls() {
    let running = panes.values.filter { $0.isRunning }.count
    for preset in LayoutPreset.allCases {
      presets.setEnabled(running <= preset.capacity, forSegment: preset.rawValue)
    }
    presets.selectedSegment = -1
    // Selection is derived from structure, not just pane count (free splits can have any shape).
    for preset in LayoutPreset.allCases where matchesPreset(preset) {
      presets.selectedSegment = preset.rawValue
    }
    editButton.state = isEditing ? .on : .off
    editButton.title = isEditing ? "편집 완료" : "레이아웃 편집"
  }

  private func matchesPreset(_ preset: LayoutPreset) -> Bool {
    func shape(_ node: LayoutNode) -> String {
      switch node {
      case .pane: return "p"
      case .split(_, let axis, _, let a, let b): return "\(axis.rawValue)(\(shape(a)),\(shape(b)))"
      }
    }
    guard layout.paneIDs.count == preset.capacity else { return false }
    return shape(layout) == shape(.preset(preset, ids: layout.paneIDs))
  }
}
