import AppKit
import ChopCore
import QuartzCore

@MainActor
final class WorkspaceView: NSView {
  let engine: TerminalEngine
  private(set) var layout: LayoutNode
  private(set) var panes: [UUID: TerminalPaneView] = [:]
  private(set) var focusedID: UUID
  private(set) var maximizedID: UUID?
  private(set) var isTabbed = false
  private var tabBar: TerminalTabBar?
  var displayMinimumSize: CGSize {
    if isTabbed {
      return CGSize(
        width: LayoutNode.paneMinimum.width,
        height: LayoutNode.paneMinimum.height + ChopStyle.headerHeight)
    }
    let minimum = layout.minimumSize
    return CGSize(
      width: min(minimum.width, LayoutNode.paneMinimum.width * 2 + LayoutNode.divider),
      height: min(minimum.height, LayoutNode.paneMinimum.height * 2 + LayoutNode.divider))
  }
  var focusedPane: TerminalPaneView { panes[focusedID]! }
  var needsConfirmClose: Bool { panes.values.contains { $0.needsConfirmClose } }
  var onChange: (() -> Void)?
  var onMinimumSizeChange: ((CGSize) -> Void)?
  var onMissingDirectories: (([String]) -> Void)?
  var onAppearanceChangeRequested: ((AppearanceMode) -> Void)?
  var onFileTreeToggleRequested: (() -> Void)?
  private var nextName = 1
  private let canvas = TerminalCanvasView()
  private lazy var canvasScroll = TerminalCanvasScrollView(canvas: canvas)
  private let bodyHost = NSView()
  private(set) var fileSplit: WorkspaceSplitView?
  private var root: NSView?
  private let presets = NSSegmentedControl()
  private let editButton = NSButton(title: "레이아웃 편집", target: nil, action: nil)
  private lazy var appearanceButton = ChopStyle.iconButton(
    "moon", label: "다크 모드로 전환", target: self, action: #selector(toggleAppearance))
  private lazy var fileTreeButton = ChopStyle.iconButton(
    "sidebar.right", label: "파일 트리 보기", target: self, action: #selector(toggleFileTree))
  private(set) var isEditing = false
  private var restoredRunningIDs: [UUID] = []
  private let dragGroupID = UUID()

  init(engine: TerminalEngine, snapshot: WorkspaceSnapshot? = nil) {
    self.engine = engine
    let valid = snapshot.flatMap { (try? $0.validate()) != nil ? $0 : nil }
    var ids = valid?.layout.paneIDs ?? (0..<4).map { _ in UUID() }
    // Upgrade the old blank single-pane start while retaining its name and cwd.
    let useDefaultGrid =
      valid == nil
      || (valid?.panes.count == 1 && valid?.panes.first?.wasRunning == false
        && valid?.tabbed != true)
    if useDefaultGrid {
      while ids.count < 4 { ids.append(UUID()) }
      layout = .preset(.grid, ids: ids)
    } else {
      layout = valid!.layout
    }
    isTabbed = !useDefaultGrid && valid?.tabbed == true
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
    fileSplit?.applyAppearance(mode)
    tabBar?.applyAppearance(mode)
    updateAppearanceButton()
  }

  @objc private func toggleAppearance() {
    onAppearanceChangeRequested?(engine.appearanceMode == .light ? .dark : .light)
  }

  private func updateAppearanceButton() {
    let isLight = engine.appearanceMode == .light
    let label = isLight ? "다크 모드로 전환" : "라이트 모드로 전환"
    appearanceButton.image = NSImage(
      systemSymbolName: isLight ? "moon" : "sun.max", accessibilityDescription: label)
    appearanceButton.toolTip = label
    appearanceButton.setAccessibilityLabel(label)
  }

  func setFileTreeVisible(_ visible: Bool) {
    let label = visible ? "파일 트리 숨기기" : "파일 트리 보기"
    fileTreeButton.toolTip = label
    fileTreeButton.setAccessibilityLabel(label)
    fileTreeButton.state = visible ? .on : .off
  }

  @objc private func toggleFileTree() { onFileTreeToggleRequested?() }

  /// File browsing shares the canvas level; the global toolbar remains above both regions.
  @discardableResult
  func installFileBrowser(defaults: UserDefaults = .standard) -> WorkspaceSplitView {
    if let fileSplit { return fileSplit }
    canvasScroll.removeFromSuperview()
    let split = WorkspaceSplitView(workspace: self, canvas: canvasScroll, defaults: defaults)
    fileSplit = split
    bodyHost.addSubview(split)
    split.frame = bodyHost.bounds
    split.autoresizingMask = [.width, .height]
    return split
  }

  private func addPane(_ id: UUID, directory: String? = nil, name: String? = nil) {
    while panes.values.contains(where: { $0.name == "터미널 \(nextName)" }) { nextName += 1 }
    let pane = TerminalPaneView(
      engine: engine, id: id, name: name ?? "터미널 \(nextName)", workspaceID: dragGroupID,
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
    pane.canMovePane = { [weak self] source in self?.canSwapPanes(source, with: id) ?? false }
    pane.onMoveRequested = { [weak self] source, previewFrame in
      self?.swapPanes(source, with: id, previewFrame: previewFrame) ?? false
    }
    pane.onDragEnded = { [weak self] in
      guard let self else { return }
      for pane in panes.values {
        pane.clearDropHighlight()
        pane.alphaValue = 1
      }
    }
    pane.isEditing = isEditing
    panes[id] = pane
  }

  @discardableResult
  func applyPreset(_ preset: LayoutPreset) -> Bool {
    if preset == .single {
      isTabbed = true
      maximizedID = nil
      rebuild()
      return true
    }
    if preset == .columns || preset == .grid {
      isTabbed = false
      maximizedID = nil
      var ids = layout.paneIDs
      while ids.count < preset.defaultPaneCount {
        let id = UUID()
        ids.append(id)
        addPane(id)
      }
      layout = .preset(preset, ids: ids)
      rebuild()
      return true
    }
    let existing = layout.paneIDs
    let running = existing.filter { panes[$0]?.isRunning == true }
    guard running.count <= preset.defaultPaneCount else {
      refreshControls()
      return false
    }
    isTabbed = false
    maximizedID = nil
    var retained = Set(running)
    for id in existing where retained.count < preset.defaultPaneCount { retained.insert(id) }
    var ids = existing.filter { retained.contains($0) }
    while ids.count < preset.defaultPaneCount {
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
    isTabbed = false
    maximizedID = nil
    focusedID = newID
    rebuild()
    panes[newID]?.openTerminal()
  }

  func canSplit(_ id: UUID, axis _: SplitAxis) -> Bool {
    panes[id] != nil && layout.paneIDs.count < 16
  }

  @objc func splitRight() { split(focusedID, axis: .horizontal) }
  @objc func splitDown() { split(focusedID, axis: .vertical) }

  func canSwapPanes(_ source: UUID, with destination: UUID) -> Bool {
    isEditing && !isTabbed && maximizedID == nil && source != destination
      && panes[source] != nil && panes[destination] != nil
  }

  @discardableResult
  func swapPanes(_ source: UUID, with destination: UUID, previewFrame: NSRect? = nil) -> Bool {
    guard canSwapPanes(source, with: destination) else { return false }
    var previousFrames: [UUID: NSRect] = [:]
    for id in [source, destination] {
      guard let pane = panes[id], let parent = pane.superview else { continue }
      previousFrames[id] = parent.convert(pane.layer?.presentation()?.frame ?? pane.frame, to: nil)
      pane.layer?.removeAnimation(forKey: "pane-reorder")
      pane.alphaValue = 1
    }
    if let previewFrame { previousFrames[source] = previewFrame }
    layout = layout.swapping(source, with: destination)
    focusedID = source
    rebuild()
    animateReorder(from: previousFrames)
    return true
  }

  private func animateReorder(from previousFrames: [UUID: NSRect]) {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    for (id, previous) in previousFrames {
      guard let pane = panes[id], let parent = pane.superview,
        pane.bounds.width > 0, pane.bounds.height > 0
      else { continue }
      let old = parent.convert(previous, from: nil)
      let translation = CATransform3DMakeTranslation(
        old.midX - pane.frame.midX, old.midY - pane.frame.midY, 0)
      let animation = CABasicAnimation(keyPath: "transform")
      animation.fromValue = NSValue(
        caTransform3D: CATransform3DScale(
          translation, old.width / pane.bounds.width, old.height / pane.bounds.height, 1))
      animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
      animation.duration = 0.18
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      pane.layer?.add(animation, forKey: "pane-reorder")
    }
  }

  func canSwapFocusedPane(_ direction: FocusDirection) -> Bool {
    guard let other = layout.neighbor(of: focusedID, toward: direction, in: canvas.bounds) else {
      return false
    }
    return canSwapPanes(focusedID, with: other)
  }

  func swapFocusedPane(_ direction: FocusDirection) {
    guard let other = layout.neighbor(of: focusedID, toward: direction, in: canvas.bounds) else {
      return
    }
    swapPanes(focusedID, with: other)
  }

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
      }, focusedID: focusedID, tabbed: isTabbed ? true : nil)
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

  func refreshMinimumSize() { onMinimumSizeChange?(displayMinimumSize) }

  private func didFocus(_ id: UUID) {
    guard panes[id] != nil else { return }
    if isTabbed, id != focusedID {
      selectTab(id)
      return
    }
    focusedID = id
    revealFocusedPane()
    onChange?()
  }

  private func revealFocusedPane() {
    guard !isTabbed, focusedPane.superview != nil else { return }
    canvasScroll.updateDocumentSize()
    canvasScroll.layoutSubtreeIfNeeded()
    canvas.scrollToVisible(focusedPane.convert(focusedPane.bounds, to: canvas))
  }

  func moveFocus(_ direction: FocusDirection) {
    if isTabbed {
      let ids = layout.paneIDs
      guard let index = ids.firstIndex(of: focusedID) else { return }
      let next = index + (direction == .left || direction == .up ? -1 : 1)
      if ids.indices.contains(next) { selectTab(ids[next]) }
      return
    }
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
    guard !isTabbed, panes[target] != nil, layout.paneIDs.count > 1 else { return }
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
      pane.showsHeader = !isTabbed
      pane.canZoom = panes.count > 1 && !isTabbed
      pane.isZoomed = maximizedID == pane.id
    }
    tabBar = nil
    let view: NSView
    if isTabbed {
      let container = NSView()
      let bar = TerminalTabBar(
        panes: layout.paneIDs.compactMap { panes[$0] }, selectedID: focusedID,
        mode: engine.appearanceMode,
        onSelect: { [weak self] in self?.selectTab($0) }, onAdd: { [weak self] in self?.addTab() },
        onClose: { [weak self] in self?.requestCloseFocused() })
      tabBar = bar
      let pane = focusedPane
      for child in [bar, pane] {
        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)
      }
      NSLayoutConstraint.activate([
        bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        bar.topAnchor.constraint(equalTo: container.topAnchor),
        bar.heightAnchor.constraint(equalToConstant: ChopStyle.headerHeight),
        pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        pane.topAnchor.constraint(equalTo: bar.bottomAnchor),
        pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
      view = container
    } else {
      for pane in panes.values { pane.translatesAutoresizingMaskIntoConstraints = true }
      view = makeView(maximizedID.map { .pane($0) } ?? layout)
    }
    canvas.addSubview(view)
    view.frame = canvas.bounds
    view.autoresizingMask = [.width, .height]
    root = view
    canvasScroll.minimumDocumentSize =
      isTabbed
      ? displayMinimumSize : maximizedID != nil ? LayoutNode.paneMinimum : layout.minimumSize
    onMinimumSizeChange?(displayMinimumSize)
    layoutSubtreeIfNeeded()
    focusedPane.focus()
    for pane in panes.values {
      pane.terminal?.setVisible(
        isTabbed ? focusedID == pane.id : maximizedID == nil || maximizedID == pane.id)
    }
    refreshControls()
    tabBar?.revealSelection(focusedID)
    onChange?()
  }

  func selectTab(_ id: UUID) {
    guard isTabbed, panes[id] != nil, id != focusedID else { return }
    focusedID = id
    rebuild()
  }

  func requestCloseFocused() {
    let id = focusedID
    focusedPane.requestClose()
    if isTabbed, panes[id]?.isRunning == false { removeEmptyPane(id) }
  }

  func addTab() {
    guard isTabbed, panes.count < 16, let last = layout.paneIDs.last else { return }
    let id = UUID()
    addPane(id, directory: focusedPane.workingDirectory)
    layout = layout.splitting(last, axis: .horizontal, adding: id)
    focusedID = id
    rebuild()
    focusedPane.openTerminal()
  }

  private func configureToolbar() {
    bodyHost.clipsToBounds = true
    presets.target = self
    presets.font = ChopStyle.font
    presets.action = #selector(selectPreset(_:))
    presets.setAccessibilityLabel("레이아웃 프리셋")
    presets.trackingMode = .selectOne
    presets.segmentCount = LayoutPreset.allCases.count
    for (preset, symbol, label) in [
      (LayoutPreset.single, "rectangle", "탭으로 보기"),
      (.columns, "rectangle.split.2x1", "좌우로 나란히"),
      (.rows, "rectangle.split.1x2", "상하 2칸"),
      (.grid, "rectangle.split.2x2", "격자로 보기"),
    ] {
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
        .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))!
      presets.setImage(image, forSegment: preset.rawValue)
      presets.setToolTip(label, forSegment: preset.rawValue)
      presets.setWidth(32, forSegment: preset.rawValue)
    }
    editButton.target = self
    editButton.action = #selector(toggleEditing)
    editButton.setButtonType(.pushOnPushOff)
    editButton.bezelStyle = .rounded
    editButton.font = ChopStyle.font
    let spacer = NSView()
    fileTreeButton.setButtonType(.pushOnPushOff)
    let toolbar = NSStackView(views: [
      presets, spacer, editButton, fileTreeButton, appearanceButton,
    ])
    toolbar.orientation = .horizontal
    toolbar.distribution = .fill
    toolbar.spacing = 12
    toolbar.alignment = .centerY
    for view in [toolbar, bodyHost] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    bodyHost.addSubview(canvasScroll)
    canvasScroll.frame = bodyHost.bounds
    canvasScroll.autoresizingMask = [.width, .height]
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      toolbar.topAnchor.constraint(equalTo: topAnchor),
      toolbar.heightAnchor.constraint(equalToConstant: 48),
      bodyHost.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
      bodyHost.leadingAnchor.constraint(equalTo: leadingAnchor),
      bodyHost.trailingAnchor.constraint(equalTo: trailingAnchor),
      bodyHost.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @objc private func selectPreset(_ sender: NSSegmentedControl) {
    guard let preset = LayoutPreset(rawValue: sender.selectedSegment) else { return }
    applyPreset(preset)
  }

  private func refreshControls() {
    let running = panes.values.filter { $0.isRunning }.count
    for preset in LayoutPreset.allCases {
      presets.setEnabled(
        preset != .rows || running <= preset.defaultPaneCount, forSegment: preset.rawValue)
    }
    presets.selectedSegment = -1
    // Selection is derived from structure, not just pane count (free splits can have any shape).
    for preset in LayoutPreset.allCases where matchesPreset(preset) {
      presets.selectedSegment = preset.rawValue
    }
    tabBar?.update(panes: layout.paneIDs.compactMap { panes[$0] }, selectedID: focusedID)
    editButton.state = isEditing ? .on : .off
    editButton.title = isEditing ? "편집 완료" : "레이아웃 편집"
  }

  private func matchesPreset(_ preset: LayoutPreset) -> Bool {
    if isTabbed { return preset == .single }
    func shape(_ node: LayoutNode) -> String {
      switch node {
      case .pane: return "p"
      case .split(_, let axis, _, let a, let b): return "\(axis.rawValue)(\(shape(a)),\(shape(b)))"
      }
    }
    let count = layout.paneIDs.count
    guard
      preset == .single || preset == .rows
        ? count == preset.defaultPaneCount : count >= preset.defaultPaneCount
    else { return false }
    return shape(layout) == shape(.preset(preset, ids: layout.paneIDs))
  }
}
