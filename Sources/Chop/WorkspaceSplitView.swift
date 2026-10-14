import AppKit
import ChopCore

@MainActor
final class WorkspaceSplitView: NSSplitView, NSSplitViewDelegate {
  static let fileTreeMinimumWidth: CGFloat = 280
  private weak var workspace: WorkspaceView?
  private let canvas: NSView
  let fileBrowser: FileBrowserView
  var onMinimumSizeChange: ((CGSize) -> Void)?
  private let defaults: UserDefaults
  private var workspaceMinimum: CGSize
  private var browserWidth: CGFloat
  private var applying = false
  private var userResizing = false
  private var background = NSColor.white
  private var headerBackground = NSColor.white
  private(set) var isFileTreeVisible: Bool

  override var dividerThickness: CGFloat { isFileTreeVisible ? 1 : 0 }

  var minimumContentSize: CGSize {
    CGSize(
      width: max(
        640,
        isFileTreeVisible
          ? max(400, workspaceMinimum.width) + Self.fileTreeMinimumWidth + 1
          : workspaceMinimum.width),
      height: max(400, workspaceMinimum.height + 48))
  }

  init(workspace: WorkspaceView, canvas: NSView, defaults: UserDefaults = .standard) {
    self.workspace = workspace
    self.canvas = canvas
    self.defaults = defaults
    workspaceMinimum = workspace.displayMinimumSize
    let savedWidth = defaults.double(forKey: "fileTreeWidth")
    browserWidth =
      savedWidth.isFinite && savedWidth >= Self.fileTreeMinimumWidth
      ? min(600, savedWidth) : 300
    isFileTreeVisible =
      defaults.object(forKey: "fileTreeVisible") == nil
      ? true : defaults.bool(forKey: "fileTreeVisible")
    fileBrowser = FileBrowserView(
      initialURL: URL(fileURLWithPath: workspace.focusedPane.workingDirectory), defaults: defaults)
    super.init(frame: .zero)
    clipsToBounds = true
    isVertical = true
    dividerStyle = .thin
    delegate = self
    addArrangedSubview(canvas)
    addArrangedSubview(fileBrowser)
    applyAppearance(workspace.engine.appearanceMode)
    workspace.onMinimumSizeChange = { [weak self] size in
      guard let self else { return }
      workspaceMinimum = size
      refreshMinimumSize()
    }
    workspace.onFileTreeToggleRequested = { [weak self] in self?.toggleFileTree() }
    applyVisibility()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(workspace:canvas:defaults:).") }

  func refreshMinimumSize() {
    onMinimumSizeChange?(minimumContentSize)
    resizeSubviews(withOldSize: bounds.size)
    needsDisplay = true
  }

  func toggleFileTree() {
    if !isFileTreeVisible, !canFitFileTree {
      let alert = NSAlert()
      alert.messageText = "파일 트리를 열 공간이 부족해요"
      alert.informativeText = "터미널 칸을 줄이거나 더 넓은 디스플레이에서 열어 주세요."
      alert.addButton(withTitle: "확인")
      alert.runModal()
      workspace?.setFileTreeVisible(false)
      return
    }
    isFileTreeVisible.toggle()
    defaults.set(isFileTreeVisible, forKey: "fileTreeVisible")
    applyVisibility()
    workspace?.focusedPane.focus()
  }

  func showFileTree() {
    if !isFileTreeVisible { toggleFileTree() }
  }

  private var canFitFileTree: Bool {
    guard let screen = window?.screen else { return true }
    return max(400, workspaceMinimum.width) + Self.fileTreeMinimumWidth + 1
      <= screen.visibleFrame.width
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if isFileTreeVisible, !canFitFileTree {
      isFileTreeVisible = false
      applyVisibility()
    }
  }

  func applyAppearance(_ mode: AppearanceMode) {
    background = mode.background
    headerBackground = mode.headerBackground
    appearance = mode.appearance
    fileBrowser.applyAppearance(mode)
    needsDisplay = true
  }

  override var isOpaque: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    background.setFill()
    let clipped = dirtyRect.intersection(bounds)
    clipped.fill()
    super.draw(clipped)
  }

  override func drawDivider(in rect: NSRect) {
    guard isFileTreeVisible else { return }
    super.drawDivider(in: rect)
    // Continue the shared header surface across the functional resize divider.
    let height = min(ChopStyle.headerHeight, bounds.height)
    let header = NSRect(
      x: rect.minX, y: isFlipped ? bounds.minY : bounds.maxY - height,
      width: rect.width, height: height)
    headerBackground.setFill()
    header.intersection(rect).fill()
  }

  private func applyVisibility() {
    fileBrowser.isHidden = !isFileTreeVisible
    workspace?.setFileTreeVisible(isFileTreeVisible)
    workspace?.sidePanelMinimumWidth = isFileTreeVisible ? Self.fileTreeMinimumWidth + 1 : 0
    refreshMinimumSize()
    needsDisplay = true
  }

  override func resizeSubviews(withOldSize oldSize: NSSize) {
    guard subviews.count == 2 else { return }
    applying = true
    defer { applying = false }
    guard isFileTreeVisible else {
      canvas.frame = bounds
      fileBrowser.frame = .zero
      return
    }
    let gap = min(dividerThickness, bounds.width)
    let available = max(0, bounds.width - gap)
    let minimumLeft = max(400, workspaceMinimum.width)
    let width =
      available >= minimumLeft + Self.fileTreeMinimumWidth
      ? min(max(Self.fileTreeMinimumWidth, browserWidth), available - minimumLeft)
      : min(browserWidth, available * 0.4)
    canvas.frame = NSRect(x: 0, y: 0, width: available - width, height: bounds.height)
    fileBrowser.frame = NSRect(
      x: available - width + gap, y: 0, width: width, height: bounds.height)
  }

  override func mouseDown(with event: NSEvent) {
    userResizing = true
    super.mouseDown(with: event)
    userResizing = false
    if isFileTreeVisible { defaults.set(browserWidth, forKey: "fileTreeWidth") }
  }

  func splitViewDidResizeSubviews(_ notification: Notification) {
    guard userResizing, !applying, isFileTreeVisible else { return }
    browserWidth = fileBrowser.frame.width
  }

  func splitView(
    _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat { max(400, workspaceMinimum.width) }

  func splitView(
    _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat { bounds.width - Self.fileTreeMinimumWidth - dividerThickness }

  func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
}
