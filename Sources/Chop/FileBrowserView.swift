import AppKit
import ChopCore

@MainActor
private final class FileBrowserNode {
  let entry: FileTreeEntry?
  let message: String
  var children: [FileBrowserNode]?
  var task: Task<Void, Never>?
  lazy var placeholder = FileBrowserNode(message: "불러오는 중…")

  init(entry: FileTreeEntry) {
    self.entry = entry
    message = entry.name
  }

  init(message: String) {
    entry = nil
    self.message = message
    children = []
  }

  func cancelLoads() {
    task?.cancel()
    for child in children ?? [] { child.cancelLoads() }
  }
}

@MainActor
private final class FileOutlineView: NSOutlineView {
  var onCopyPath: (() -> Void)?
  @objc func copy(_ sender: Any?) { onCopyPath?() }
}

@MainActor
final class FileBrowserView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate,
  NSMenuDelegate, NSMenuItemValidation
{
  typealias Loader = @Sendable (URL) async throws -> [FileTreeEntry]
  private(set) var rootURL: URL
  private(set) var isLoading = false
  private(set) var loadError: String?
  private let defaults: UserDefaults
  private let loader: Loader
  private var generation = UUID()
  private var rootTask: Task<Void, Never>?
  private var roots: [FileBrowserNode] = []
  private let header = NSView()
  private let pathField = NSTextField()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let outline = FileOutlineView()
  private let scrollView = NSScrollView()
  private let quickLocations: [URL] = [
    FileManager.default.homeDirectoryForCurrentUser,
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
  ]

  init(
    initialURL: URL, defaults: UserDefaults = .standard,
    loader: @escaping Loader = { directory in
      try await Task.detached(priority: .userInitiated) {
        try FileTree.entries(at: directory)
      }.value
    }
  ) {
    self.defaults = defaults
    self.loader = loader
    rootURL =
      defaults.string(forKey: "fileTreeRootPath")
      .map { URL(fileURLWithPath: $0) } ?? initialURL
    super.init(frame: .zero)
    wantsLayer = true
    configureViews()
    navigate(to: rootURL)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(initialURL:defaults:loader:).") }

  func applyAppearance(_ mode: AppearanceMode) {
    appearance = mode.appearance
    layer?.backgroundColor = mode.background.cgColor
    header.layer?.backgroundColor = mode.headerBackground.cgColor
    statusLabel.textColor = mode.secondaryForeground
    outline.reloadData()
  }

  /// Each navigation replaces its generation so delayed reads cannot overwrite a newer folder.
  func navigate(to directory: URL) {
    rootTask?.cancel()
    for node in roots { node.cancelLoads() }
    generation = UUID()
    let request = generation
    rootURL = directory.standardizedFileURL
    pathField.stringValue = rootURL.path
    pathField.toolTip = rootURL.path
    roots = []
    loadError = nil
    isLoading = true
    showStatus("불러오는 중…")
    outline.reloadData()
    let loader = loader
    let location = rootURL
    rootTask = Task { [weak self] in
      do {
        let entries = try await loader(location)
        guard let self, generation == request, !Task.isCancelled else { return }
        roots = entries.map(FileBrowserNode.init(entry:))
        isLoading = false
        defaults.set(location.path, forKey: "fileTreeRootPath")
        outline.reloadData()
        showStatus(entries.isEmpty ? "빈 폴더예요" : nil)
      } catch {
        guard let self, generation == request, !Task.isCancelled else { return }
        isLoading = false
        loadError = error.localizedDescription
        showStatus("폴더를 열 수 없어요.\n\(error.localizedDescription)")
      }
    }
  }

  private func showStatus(_ text: String?) {
    statusLabel.stringValue = text ?? ""
    statusLabel.isHidden = text == nil
  }

  @objc private func goToPath() {
    do {
      navigate(to: try FileTree.directoryURL(for: pathField.stringValue, relativeTo: rootURL))
    } catch {
      showStatus(error.localizedDescription)
    }
  }

  @objc private func refresh() { goToPath() }

  @objc private func visitShortcut(_ sender: NSButton) {
    guard quickLocations.indices.contains(sender.tag) else { return }
    navigate(to: quickLocations[sender.tag])
  }

  @objc func chooseFolder() {
    guard let window, window.attachedSheet == nil else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.directoryURL = rootURL
    panel.prompt = "폴더 선택"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.navigate(to: url)
    }
  }

  private var selectedEntry: FileTreeEntry? {
    guard outline.selectedRow >= 0 else { return nil }
    return (outline.item(atRow: outline.selectedRow) as? FileBrowserNode)?.entry
  }

  @objc private func activateItem() {
    guard let entry = selectedEntry,
      let node = outline.item(atRow: outline.selectedRow) as? FileBrowserNode
    else { return }
    if entry.isDirectory {
      if outline.isItemExpanded(node) {
        outline.collapseItem(node)
      } else {
        outline.expandItem(node)
      }
    } else {
      revealInFinder()
    }
  }

  @objc private func revealInFinder() {
    guard let entry = selectedEntry else { return }
    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
  }

  @objc private func copyPath() {
    guard let entry = selectedEntry else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(entry.url.path, forType: .string)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if outline.clickedRow >= 0,
      (outline.item(atRow: outline.clickedRow) as? FileBrowserNode)?.entry != nil
    {
      outline.selectRowIndexes(IndexSet(integer: outline.clickedRow), byExtendingSelection: false)
    } else {
      outline.deselectAll(nil)
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { selectedEntry != nil }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    guard let node = item as? FileBrowserNode else { return roots.count }
    return node.children?.count ?? 1
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    guard let node = item as? FileBrowserNode else { return roots[index] }
    return node.children?[index] ?? node.placeholder
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    guard let node = item as? FileBrowserNode, node.entry?.isDirectory == true else { return false }
    return node.children?.isEmpty != true
  }

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    (item as? FileBrowserNode)?.entry != nil
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    guard let node = notification.userInfo?["NSObject"] as? FileBrowserNode,
      let entry = node.entry, node.children == nil, node.task == nil
    else { return }
    let request = generation
    let loader = loader
    node.task = Task { [weak self, weak node] in
      do {
        let entries = try await loader(entry.url)
        guard let self, let node, generation == request, !Task.isCancelled else { return }
        node.children = entries.map(FileBrowserNode.init(entry:))
        outline.reloadItem(node, reloadChildren: true)
      } catch {
        guard let self, let node, generation == request, !Task.isCancelled else { return }
        node.children = [FileBrowserNode(message: "폴더를 읽을 수 없어요")]
        outline.reloadItem(node, reloadChildren: true)
      }
    }
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
    -> NSView?
  {
    guard let node = item as? FileBrowserNode else { return nil }
    let cell = NSTableCellView()
    cell.toolTip = node.entry?.url.path ?? node.message
    let label = NSTextField(labelWithString: node.message)
    label.font = ChopStyle.font
    label.lineBreakMode = .byTruncatingMiddle
    label.textColor = node.entry == nil ? .secondaryLabelColor : .labelColor
    cell.textField = label
    let icon = NSImageView()
    if let entry = node.entry {
      icon.image = NSImage(
        systemSymbolName: entry.isDirectory ? "folder" : "doc",
        accessibilityDescription: entry.isDirectory ? "폴더" : "파일")
      icon.contentTintColor = .secondaryLabelColor
    }
    cell.imageView = icon
    for view in [icon, label] {
      view.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(view)
    }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
      icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 16),
      icon.heightAnchor.constraint(equalToConstant: 16),
      label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func configureViews() {
    header.wantsLayer = true
    let title = NSTextField(labelWithString: "파일")
    title.font = ChopStyle.font
    let refreshButton = ChopStyle.iconButton(
      "arrow.clockwise", label: "새로고침", target: self, action: #selector(refresh))
    let folderButton = ChopStyle.iconButton(
      "folder", label: "폴더 선택…", target: self, action: #selector(chooseFolder))
    let headerRow = NSStackView(views: [title, NSView(), refreshButton, folderButton])
    headerRow.spacing = 8
    headerRow.alignment = .centerY
    header.addSubview(headerRow)
    pathField.font = ChopStyle.font
    pathField.maximumNumberOfLines = 1
    pathField.cell?.usesSingleLineMode = true
    pathField.cell?.isScrollable = true
    pathField.lineBreakMode = .byTruncatingMiddle
    pathField.bezelStyle = .roundedBezel
    pathField.focusRingType = .none
    pathField.placeholderString = "폴더 경로"
    pathField.setAccessibilityLabel("파일 트리 폴더 경로")
    pathField.target = self
    pathField.action = #selector(goToPath)
    let shortcuts = NSStackView()
    shortcuts.spacing = 8
    shortcuts.distribution = .fillEqually
    for (index, name) in ["홈", "다운로드", "문서"].enumerated() {
      let button = NSButton(title: name, target: self, action: #selector(visitShortcut(_:)))
      button.font = ChopStyle.font
      button.bezelStyle = .rounded
      button.tag = index
      button.toolTip = quickLocations[index].path
      shortcuts.addArrangedSubview(button)
    }
    statusLabel.font = ChopStyle.font
    statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    outline.addTableColumn(NSTableColumn(identifier: .init("file")))
    outline.outlineTableColumn = outline.tableColumns.first
    outline.headerView = nil
    outline.rowHeight = 28
    outline.indentationPerLevel = 16
    outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    outline.focusRingType = .none
    outline.backgroundColor = .clear
    outline.setAccessibilityLabel("파일 트리")
    outline.dataSource = self
    outline.delegate = self
    outline.target = self
    outline.doubleAction = #selector(activateItem)
    outline.onCopyPath = { [weak self] in self?.copyPath() }
    let menu = NSMenu()
    menu.delegate = self
    for (title, action) in [
      ("Finder에서 보기", #selector(revealInFinder)), ("경로 복사", #selector(copyPath)),
    ] {
      menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }
    outline.menu = menu
    scrollView.documentView = outline
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    let content = NSStackView(views: [pathField, shortcuts, statusLabel, scrollView])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 8
    for view in [header, headerRow, content, pathField, shortcuts, statusLabel, scrollView] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    addSubview(header)
    addSubview(content)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: leadingAnchor),
      header.trailingAnchor.constraint(equalTo: trailingAnchor),
      header.topAnchor.constraint(equalTo: topAnchor),
      header.heightAnchor.constraint(equalToConstant: ChopStyle.headerHeight),
      headerRow.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: ChopStyle.inset),
      headerRow.trailingAnchor.constraint(
        equalTo: header.trailingAnchor, constant: -ChopStyle.inset),
      headerRow.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChopStyle.inset),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChopStyle.inset),
      content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
      pathField.widthAnchor.constraint(equalTo: content.widthAnchor),
      pathField.heightAnchor.constraint(equalToConstant: 28),
      shortcuts.widthAnchor.constraint(equalTo: content.widthAnchor),
      statusLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
      scrollView.widthAnchor.constraint(equalTo: content.widthAnchor),
      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
    ])
  }
}
