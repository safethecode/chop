import AppKit
import ChopCore

@MainActor
final class TerminalPaneView: NSView {
  let id: UUID
  let engine: TerminalEngine
  let workspaceID: UUID
  private(set) var terminal: TerminalView?
  var workingDirectory: String
  var name: String {
    didSet {
      updateHeader()
      onChange?()
    }
  }
  var onChange: (() -> Void)?
  var onFocus: (() -> Void)?
  var onSplitRequested: ((SplitAxis) -> Void)?
  var canSplit: ((SplitAxis) -> Bool)?
  var onRemoveRequested: (() -> Void)?
  var onZoomRequested: (() -> Void)?
  var onRenameRequested: (() -> Void)?
  var onDirectoryFallback: ((String) -> Void)?
  var canMovePane: ((UUID) -> Bool)?
  var onMoveRequested: ((UUID, NSRect) -> Bool)?
  var onDragEnded: (() -> Void)?
  var canRemove = false { didSet { updateHeader() } }
  var canZoom = false { didSet { updateHeader() } }
  var isZoomed = false { didSet { updateHeader() } }
  var isEditing = false {
    didSet {
      updateAddButton()
      updateMoveHandle()
      if !isEditing {
        clearDropHighlight()
        alphaValue = 1
      }
    }
  }
  private var isDropTarget = false { didSet { updateDropHighlight() } }
  private lazy var moveHandle = PaneDragHandleView(paneID: id, workspaceID: workspaceID)
  var showsHeader = true {
    didSet {
      header.isHidden = !showsHeader
      headerHeight?.constant = showsHeader ? ChopStyle.headerHeight : 0
    }
  }
  private var headerHeight: NSLayoutConstraint?
  private let header = NSView()
  private let body = NSView()
  private let titleButton = NSButton()
  private let pathLabel = NSTextField(labelWithString: "")
  private let errorLabel = NSTextField(wrappingLabelWithString: "")
  private var openButton: NSButton!
  private var closeButton: NSButton!
  private var zoomButton: NSButton!

  init(
    engine: TerminalEngine, id: UUID = UUID(), name: String = "터미널 1",
    workspaceID: UUID = UUID(),
    workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) {
    self.engine = engine
    self.workspaceID = workspaceID
    self.id = id
    self.name = name
    self.workingDirectory = workingDirectory
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityIdentifier("pane-\(id.uuidString)")
    registerForDraggedTypes([PaneDragHandleView.pasteboardType])
    configureViews()
    applyAppearance()
    updateHeader()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(engine:).") }

  var isRunning: Bool { terminal != nil }
  var needsConfirmClose: Bool { terminal?.needsConfirmClose ?? false }

  /// Refreshes pane chrome, including hidden panes, without recreating the terminal surface.
  func applyAppearance() {
    let mode = engine.appearanceMode
    appearance = mode.appearance
    layer?.backgroundColor = mode.background.cgColor
    header.layer?.backgroundColor = mode.headerBackground.cgColor
    updateNameButton()
    pathLabel.textColor = mode.secondaryForeground
    errorLabel.textColor = mode.secondaryForeground
    updateDropHighlight()
  }

  private func updateDropHighlight() {
    layer?.borderWidth = isDropTarget ? 2 : 0
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
    }
  }

  func clearDropHighlight() { isDropTarget = false }

  func dragPreview(in source: NSView) -> PaneDragPreview? {
    layoutSubtreeIfNeeded()
    guard bounds.width > 0, bounds.height > 0,
      let bitmap = bitmapImageRepForCachingDisplay(in: bounds)
    else { return nil }
    cacheDisplay(in: bounds, to: bitmap)
    let snapshot = NSImage(size: bounds.size)
    snapshot.addRepresentation(bitmap)
    let background = engine.appearanceMode.background
    let chrome = NSDraggingImageComponent(key: .icon)
    chrome.frame = NSRect(origin: .zero, size: bounds.size)
    chrome.contents = NSImage(size: bounds.size, flipped: false) { rect in
      background.setFill()
      rect.fill()
      snapshot.draw(in: rect)
      return true
    }
    var components = [chrome]
    // AppKit's bitmap cache does not reliably include a layer-hosted GPU view.
    // Drag components accept CALayer contents, so retain the current IOSurface
    // directly instead of substituting text or moving/recreating the PTY view.
    if let terminal, let contents = terminal.layer?.contents {
      let rendered = NSDraggingImageComponent(key: .init(rawValue: "chop.terminal"))
      rendered.contents = contents
      rendered.frame = convert(terminal.bounds, from: terminal)
      components.append(rendered)
    }
    return PaneDragPreview(frame: source.convert(bounds, from: self), components: components)
  }

  private func draggedPane(_ sender: any NSDraggingInfo) -> UUID? {
    guard isEditing, let source = sender.draggingSource as? PaneDragHandleView,
      source.workspaceID == workspaceID, source.paneID != id,
      sender.draggingPasteboard.string(forType: PaneDragHandleView.pasteboardType)
        == source.paneID.uuidString,
      canMovePane?(source.paneID) == true
    else { return nil }
    return source.paneID
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    isDropTarget = draggedPane(sender) != nil
    return isDropTarget ? .move : []
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingEntered(sender)
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) { clearDropHighlight() }

  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    draggedPane(sender) != nil
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    clearDropHighlight()
    guard let source = draggedPane(sender),
      let handle = sender.draggingSource as? PaneDragHandleView,
      let size = handle.previewSize
    else { return false }
    let previewFrame = NSRect(origin: sender.draggedImageLocation, size: size)
    return onMoveRequested?(source, previewFrame) ?? false
  }

  override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { clearDropHighlight() }

  private func updateMoveHandle() {
    moveHandle.isHidden = !isEditing || !canZoom
    window?.invalidateCursorRects(for: moveHandle)
  }

  @objc func openTerminal() {
    guard terminal == nil else {
      focus()
      return
    }
    do {
      if let missing = resolveWorkingDirectory() { onDirectoryFallback?(missing) }
      layoutSubtreeIfNeeded()
      let view = try TerminalView(
        engine: engine, workingDirectory: workingDirectory, frame: body.bounds)
      terminal = view
      view.onExit = { [weak self, weak view] in
        guard let self, let view, self.terminal === view else { return }
        self.closeTerminal()
      }
      view.onFocus = { [weak self] in self?.onFocus?() }
      view.onMetadataChange = { [weak self] in
        guard let self, let terminal = self.terminal else { return }
        self.workingDirectory = terminal.workingDirectory
        self.updateHeader()
        self.onChange?()
      }
      body.addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: body.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        view.topAnchor.constraint(equalTo: body.topAnchor),
        view.bottomAnchor.constraint(equalTo: body.bottomAnchor),
      ])
      body.addSubview(openButton, positioned: .above, relativeTo: view)
      updateAddButton()
      errorLabel.isHidden = true
      updateHeader()
      focus()
      onChange?()
    } catch {
      errorLabel.stringValue = error.localizedDescription
      errorLabel.isHidden = false
      openButton.setAccessibilityLabel("다시 열기")
      openButton.toolTip = "다시 열기"
    }
  }

  func closeTerminal() {
    guard let terminal else { return }
    workingDirectory = terminal.workingDirectory
    terminal.close()
    terminal.removeFromSuperview()
    self.terminal = nil
    openButton.isHidden = false
    errorLabel.isHidden = true
    openButton.setAccessibilityLabel("터미널 열기")
    openButton.toolTip = "터미널 열기"
    updateHeader()
    focus()
    onChange?()
  }

  /// Resolve every saved path before restore; no path is interpreted as a command.
  func resolveWorkingDirectory() -> String? {
    var isDirectory: ObjCBool = false
    guard
      !FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory)
        || !isDirectory.boolValue || !FileManager.default.isReadableFile(atPath: workingDirectory)
        || !FileManager.default.isExecutableFile(atPath: workingDirectory)
    else { return nil }
    let missing = workingDirectory
    workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    updateHeader()
    onChange?()
    return missing
  }

  func focus() {
    window?.makeFirstResponder(terminal ?? openButton)
    onFocus?()
  }

  @objc func requestClose() {
    guard isRunning else {
      onRemoveRequested?()
      return
    }
    if needsConfirmClose {
      let alert = NSAlert()
      alert.messageText = "이 터미널을 닫을까요?"
      alert.informativeText = "이 칸에서 실행 중인 작업이 종료됩니다."
      alert.addButton(withTitle: "취소")
      alert.addButton(withTitle: "터미널 닫기")
      guard alert.runModal() == .alertSecondButtonReturn else { return }
    }
    closeTerminal()
  }

  override func mouseDown(with event: NSEvent) { focus() }

  @objc private func toggleZoom() { onZoomRequested?() }
  @objc private func renamePane() { onRenameRequested?() }

  @objc private func addFromCenter() {
    guard isRunning else {
      openTerminal()
      return
    }
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (title, action, axis) in [
      ("오른쪽에 추가", #selector(addRight), SplitAxis.horizontal),
      ("아래에 추가", #selector(addDown), .vertical),
    ] {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
      item.isEnabled = canSplit?(axis) ?? false
    }
    menu.popUp(
      positioning: nil, at: NSPoint(x: openButton.frame.minX, y: openButton.frame.minY), in: body)
  }

  @objc private func addRight() { onSplitRequested?(.horizontal) }
  @objc private func addDown() { onSplitRequested?(.vertical) }

  private func updateAddButton() {
    openButton.isHidden = isRunning && !isEditing
    let label = isRunning ? "터미널 추가" : "터미널 열기"
    openButton.setAccessibilityLabel(label)
    openButton.toolTip = label
  }

  /// Builds header and body controls before the initial appearance is applied.
  private func configureViews() {
    header.wantsLayer = true
    for view in [header, body] {
      addSubview(view)
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    titleButton.target = self
    titleButton.action = #selector(renamePane)
    titleButton.setButtonType(.momentaryPushIn)
    titleButton.bezelStyle = .inline
    titleButton.isBordered = false
    titleButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    titleButton.imagePosition = .imageTrailing
    titleButton.imageScaling = .scaleProportionallyDown
    titleButton.alignment = .left
    titleButton.font = ChopStyle.font
    titleButton.cell?.lineBreakMode = .byTruncatingTail
    titleButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let nameMenu = NSMenu()
    nameMenu.addItem(withTitle: "이름 바꾸기…", action: #selector(renamePane), keyEquivalent: "")
      .target = self
    header.menu = nameMenu
    titleButton.menu = nameMenu
    pathLabel.font = ChopStyle.font
    pathLabel.lineBreakMode = .byTruncatingMiddle
    pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let close = ChopStyle.iconButton(
      "xmark", label: "터미널 닫기", target: self, action: #selector(requestClose))
    closeButton = close
    zoomButton = ChopStyle.iconButton(
      "arrow.up.left.and.arrow.down.right", label: "칸 확대", target: self,
      action: #selector(toggleZoom))
    moveHandle.onFocus = { [weak self] in self?.focus() }
    moveHandle.onPrepareDrag = { [weak self] source in self?.dragPreview(in: source) }
    moveHandle.onDragBegan = { [weak self] in self?.alphaValue = 0.35 }
    moveHandle.onDragEnded = { [weak self] in
      self?.alphaValue = 1
      self?.onDragEnded?()
    }
    moveHandle.isHidden = true
    let row = ChopStyle.headerRow(views: [moveHandle, titleButton, pathLabel, zoomButton, close])
    header.addSubview(row)
    openButton = NSButton(
      image: NSImage(systemSymbolName: "plus", accessibilityDescription: "터미널 열기")!, target: self,
      action: #selector(addFromCenter))
    openButton.bezelStyle = .circular
    openButton.controlSize = .large
    openButton.toolTip = "터미널 열기"
    openButton.setAccessibilityLabel("터미널 열기")
    openButton.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(openButton)
    errorLabel.font = ChopStyle.font
    errorLabel.alignment = .center
    errorLabel.isHidden = true
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(errorLabel)
    let headerHeightConstraint = header.heightAnchor.constraint(
      equalToConstant: ChopStyle.headerHeight)
    headerHeight = headerHeightConstraint
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: leadingAnchor),
      header.trailingAnchor.constraint(equalTo: trailingAnchor),
      header.topAnchor.constraint(equalTo: topAnchor),
      headerHeightConstraint,
      row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: ChopStyle.inset),
      row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -ChopStyle.inset),
      row.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      body.leadingAnchor.constraint(equalTo: leadingAnchor),
      body.trailingAnchor.constraint(equalTo: trailingAnchor),
      body.topAnchor.constraint(equalTo: header.bottomAnchor),
      body.bottomAnchor.constraint(equalTo: bottomAnchor),
      openButton.centerXAnchor.constraint(equalTo: body.centerXAnchor),
      openButton.centerYAnchor.constraint(equalTo: body.centerYAnchor),
      openButton.widthAnchor.constraint(equalToConstant: 56),
      openButton.heightAnchor.constraint(equalToConstant: 56),
      errorLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 16),
      errorLabel.centerXAnchor.constraint(equalTo: body.centerXAnchor),
      errorLabel.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor, constant: -32),
    ])
  }

  private func updateHeader() {
    updateMoveHandle()
    moveHandle.setAccessibilityLabel("\(name) 이동")
    updateNameButton()
    pathLabel.stringValue = (workingDirectory as NSString).abbreviatingWithTildeInPath
    pathLabel.toolTip = workingDirectory
    terminal?.setAccessibilityLabel("\(name) 터미널")
    closeButton.isEnabled = isRunning || canRemove
    let closeLabel = isRunning ? "터미널 닫기" : "빈 칸 제거"
    closeButton.setAccessibilityLabel(closeLabel)
    closeButton.toolTip = closeLabel
    let zoomLabel = isZoomed ? "전체 레이아웃으로 돌아가기" : "칸 확대"
    zoomButton.setAccessibilityLabel(zoomLabel)
    zoomButton.isEnabled = canZoom
    zoomButton.toolTip = zoomLabel
    zoomButton.image = NSImage(
      systemSymbolName: isZoomed
        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
      accessibilityDescription: zoomLabel)
  }

  private func updateNameButton() {
    titleButton.contentTintColor = engine.appearanceMode.secondaryForeground
    titleButton.attributedTitle = NSAttributedString(
      string: name,
      attributes: [.font: ChopStyle.font, .foregroundColor: engine.appearanceMode.foreground])
    titleButton.toolTip = "이름 바꾸기 (⌘⇧R)"
    titleButton.setAccessibilityLabel("\(name) 이름 바꾸기")
  }
}
