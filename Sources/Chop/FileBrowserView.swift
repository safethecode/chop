import AppKit
import ChopCore

@MainActor
private final class FileBrowserNode {
  let entry: FileTreeEntry?
  let message: String
  var children: [FileBrowserNode]?
  var task: Task<Void, Never>?
  lazy var placeholder = FileBrowserNode(message: "불러오는 중…")

  init(entry: FileTreeEntry, message: String? = nil) {
    self.entry = entry
    self.message = message ?? entry.name
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

  override func keyDown(with event: NSEvent) {
    // Return and keypad Enter activate the selected result just like a double-click.
    if [36, 76].contains(event.keyCode),
      event.modifierFlags.intersection([.command, .option, .control]).isEmpty
    {
      sendAction(doubleAction, to: target)
    } else {
      super.keyDown(with: event)
    }
  }
}

@MainActor
final class FileBrowserView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate,
  NSMenuDelegate, NSMenuItemValidation, NSSearchFieldDelegate
{
  typealias Loader = @Sendable (URL) async throws -> [FileTreeEntry]
  private(set) var rootURL: URL
  private(set) var isLoading = false
  private(set) var loadError: String?
  private(set) var searchQuery = ""
  private let defaults: UserDefaults
  private let loader: Loader
  private var generation = UUID()
  private var rootTask: Task<Void, Never>?
  private var roots: [FileBrowserNode] = []
  private let header = NSView()
  private let titleLabel = NSTextField(labelWithString: "파일")
  private let pathField = NSTextField()
  private let searchField = NSSearchField()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  private let outline = FileOutlineView()
  private let scrollView = NSScrollView()
  private let listSection = NSView()
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

  deinit { rootTask?.cancel() }

  func applyAppearance(_ mode: AppearanceMode) {
    appearance = mode.appearance
    layer?.backgroundColor = mode.background.cgColor
    header.layer?.backgroundColor = mode.headerBackground.cgColor
    listSection.layer?.backgroundColor = mode.fileListBackground.cgColor
    titleLabel.textColor = mode.foreground
    statusLabel.textColor = mode.secondaryForeground
    outline.reloadData()
  }

  /// Each navigation replaces its generation so delayed reads cannot overwrite a newer folder.
  func navigate(to directory: URL) {
    rootURL = directory.standardizedFileURL
    pathField.stringValue = rootURL.path
    pathField.toolTip = rootURL.path
    searchField.stringValue = ""
    searchQuery = ""
    reloadContents()
  }

  func search(for query: String) {
    // Native edits already own the text; avoid resetting the field editor during IME composition.
    if searchField.stringValue != query { searchField.stringValue = query }
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized != searchQuery else { return }
    searchQuery = normalized
    reloadContents(debounce: true)
  }

  private func reloadContents(debounce: Bool = false) {
    rootTask?.cancel()
    for node in roots { node.cancelLoads() }
    generation = UUID()
    let request = generation
    let query = searchQuery
    roots = []
    loadError = nil
    isLoading = true
    showStatus(query.isEmpty ? "불러오는 중…" : "검색 중…")
    outline.setAccessibilityLabel(query.isEmpty ? "파일 트리" : "파일 검색 결과")
    outline.reloadData()
    let loader = loader
    let location = rootURL
    rootTask = Task { [weak self] in
      do {
        if debounce && !query.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
        let rows: [(entry: FileTreeEntry, message: String)]
        let status: String?
        if query.isEmpty {
          let entries = try await loader(location)
          rows = entries.map { ($0, $0.name) }
          status = entries.isEmpty ? "빈 폴더예요" : nil
        } else {
          let result = try await FileTreeSearch.search(
            at: location, matching: query, reader: loader)
          rows = result.matches.map { ($0.entry, $0.relativePath) }
          status = Self.searchStatus(for: result)
        }
        guard let self, generation == request, !Task.isCancelled else { return }
        roots = rows.map { FileBrowserNode(entry: $0.entry, message: $0.message) }
        isLoading = false
        defaults.set(location.path, forKey: "fileTreeRootPath")
        outline.reloadData()
        showStatus(status)
      } catch {
        guard let self, generation == request, !Task.isCancelled else { return }
        isLoading = false
        loadError = error.localizedDescription
        let message = query.isEmpty ? "폴더를 열 수 없어요." : "검색할 수 없어요."
        showStatus("\(message)\n\(error.localizedDescription)")
      }
    }
  }

  private static func searchStatus(for result: FileTreeSearchResult) -> String {
    let count = result.matches.count
    var status = count == 0 ? "검색 결과가 없어요" : "\(count)개 결과"
    if result.isTruncated { status = "처음 \(count)개 결과 · 검색어를 좁혀 주세요." }
    if result.skippedDirectories > 0 { status += "\n일부 폴더를 읽지 못했어요." }
    return status
  }

  func controlTextDidChange(_ notification: Notification) {
    guard notification.object as? NSSearchField === searchField else { return }
    search(for: searchField.stringValue)
  }

  @objc private func searchChanged() { search(for: searchField.stringValue) }

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

  @objc private func refresh() {
    do {
      let directory = try FileTree.directoryURL(for: pathField.stringValue, relativeTo: rootURL)
      if directory.path == rootURL.path {
        reloadContents()
      } else {
        navigate(to: directory)
      }
    } catch {
      showStatus(error.localizedDescription)
    }
  }

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
      if !searchQuery.isEmpty {
        navigate(to: entry.url)
      } else if outline.isItemExpanded(node) {
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
    guard searchQuery.isEmpty, let node = item as? FileBrowserNode,
      node.entry?.isDirectory == true
    else { return false }
    return node.children?.isEmpty != true
  }

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    (item as? FileBrowserNode)?.entry != nil
  }

  func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any)
    -> (any NSPasteboardWriting)?
  {
    guard let entry = (item as? FileBrowserNode)?.entry else { return nil }
    return entry.url as NSURL
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
        node.children = entries.map { FileBrowserNode(entry: $0) }
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
    titleLabel.font = ChopStyle.font
    let refreshButton = ChopStyle.iconButton(
      "arrow.clockwise", label: "새로고침", target: self, action: #selector(refresh))
    let folderButton = ChopStyle.iconButton(
      "folder", label: "폴더 선택…", target: self, action: #selector(chooseFolder))
    let headerRow = ChopStyle.headerRow(views: [titleLabel, NSView(), refreshButton, folderButton])
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
    searchField.font = ChopStyle.font
    searchField.placeholderString = "파일·폴더 이름 검색"
    searchField.setAccessibilityLabel("파일 트리 검색")
    searchField.toolTip = "현재 폴더와 하위 폴더에서 이름으로 검색"
    searchField.focusRingType = .none
    searchField.sendsSearchStringImmediately = true
    searchField.delegate = self
    searchField.target = self
    searchField.action = #selector(searchChanged)
    let shortcuts = NSStackView()
    shortcuts.orientation = .horizontal
    shortcuts.alignment = .centerY
    shortcuts.spacing = 8
    let locations = [("홈", "house"), ("다운로드", "arrow.down.circle"), ("문서", "doc")]
    for (index, location) in locations.enumerated() {
      let (name, symbol) = location
      let button = NSButton(title: name, target: self, action: #selector(visitShortcut(_:)))
      button.bezelStyle = .rounded
      button.font = ChopStyle.font
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
      button.imagePosition = .imageLeading
      button.imageScaling = .scaleProportionallyDown
      button.setAccessibilityLabel(name)
      button.tag = index
      button.toolTip = quickLocations[index].path
      shortcuts.addArrangedSubview(button)
      button.translatesAutoresizingMaskIntoConstraints = false
      button.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
    outline.setDraggingSourceOperationMask(.copy, forLocal: true)
    outline.setDraggingSourceOperationMask(.copy, forLocal: false)
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
    let listContent = NSStackView(views: [statusLabel, scrollView])
    listContent.orientation = .vertical
    listContent.alignment = .leading
    listContent.spacing = 8
    listSection.wantsLayer = true
    listSection.layer?.cornerRadius = 8
    listSection.layer?.masksToBounds = true
    listSection.addSubview(listContent)
    let content = NSStackView(views: [pathField, shortcuts, searchField, listSection])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 8
    for view in [
      header, headerRow, content, pathField, shortcuts, searchField, listSection, listContent,
      statusLabel,
      scrollView,
    ] {
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
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -ChopStyle.inset),
      pathField.widthAnchor.constraint(equalTo: content.widthAnchor),
      pathField.heightAnchor.constraint(equalToConstant: 28),
      shortcuts.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
      searchField.widthAnchor.constraint(equalTo: content.widthAnchor),
      searchField.heightAnchor.constraint(equalToConstant: 28),
      listSection.widthAnchor.constraint(equalTo: content.widthAnchor),
      listContent.leadingAnchor.constraint(equalTo: listSection.leadingAnchor, constant: 8),
      listContent.trailingAnchor.constraint(equalTo: listSection.trailingAnchor, constant: -8),
      listContent.topAnchor.constraint(equalTo: listSection.topAnchor, constant: 8),
      listContent.bottomAnchor.constraint(equalTo: listSection.bottomAnchor, constant: -8),
      statusLabel.widthAnchor.constraint(equalTo: listContent.widthAnchor),
      scrollView.widthAnchor.constraint(equalTo: listContent.widthAnchor),
      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
    ])
  }
}
