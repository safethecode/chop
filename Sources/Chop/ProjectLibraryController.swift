import AppKit
import ChopCore

@MainActor
final class ProjectLibraryController: NSObject, NSMenuDelegate, NSMenuItemValidation {
  let recentMenu = NSMenu(title: "최근 프로젝트")
  let configurationMenu = NSMenu(title: "작업 구성")
  private let manager: WorkspaceWindowManager
  private let store: ProjectLibraryStore
  private(set) var library = ProjectLibrary()
  private var loadFailed = false
  private var reportedVisitFailure = false

  init(manager: WorkspaceWindowManager, store: ProjectLibraryStore) {
    self.manager = manager
    self.store = store
    super.init()
    recentMenu.delegate = self
    configurationMenu.delegate = self
    manager.onProjectOpened = { [weak self] path in self?.recordVisit(path) }
  }

  func install(in menu: NSMenu) {
    for submenu in [recentMenu, configurationMenu] {
      let item = menu.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "")
      item.submenu = submenu
      menuNeedsUpdate(submenu)
    }
  }

  func load(reportFailure: Bool = true) {
    do {
      library = try store.load()
      loadFailed = false
      reportedVisitFailure = false
    } catch {
      loadFailed = true
      if reportFailure { show(error, title: "프로젝트 기록을 불러오지 못했어요") }
    }
  }

  private func recordVisit(_ path: String) {
    do {
      library = try store.update { try $0.visit(path) }
      reportedVisitFailure = false
    } catch {
      guard !reportedVisitFailure else { return }
      reportedVisitFailure = true
      show(error, title: "최근 프로젝트를 저장하지 못했어요")
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    if menu === recentMenu {
      for path in library.recentProjects {
        let item = add(
          recentTitle(path), to: menu,
          action: #selector(openRecent(_:)))
        item.representedObject = path
        item.toolTip = path
      }
      if library.recentProjects.isEmpty {
        placeholder(loadFailed ? "프로젝트 기록을 읽지 못했어요" : "최근 프로젝트가 없어요", in: menu)
      }
      menu.addItem(.separator())
      add("목록 지우기", to: menu, action: #selector(clearRecent))
    } else {
      let save = add("현재 구성 저장…", to: menu, action: #selector(saveCurrent))
      save.keyEquivalent = "s"
      save.keyEquivalentModifierMask = [.command, .shift]
      menu.addItem(.separator())
      let entries = manager.active.map { library.configurations(for: $0.projectDirectory) } ?? []
      if entries.isEmpty { placeholder("저장한 구성이 없어요", in: menu) }
      for entry in entries {
        let item = add(entry.name, to: menu, action: #selector(openConfiguration(_:)))
        item.representedObject = entry.id.uuidString
        item.toolTip = "새 윈도우에서 열기 — \(entry.projectDirectory)"
      }
      menu.addItem(.separator())
      add("구성 삭제…", to: menu, action: #selector(deleteConfiguration))
    }
    if loadFailed {
      menu.addItem(.separator())
      add("프로젝트 기록 다시 불러오기", to: menu, action: #selector(reloadLibrary))
    }
  }

  private func recentTitle(_ path: String) -> String {
    let abbreviated = (path as NSString).abbreviatingWithTildeInPath
    let title = String(
      abbreviated.map { character in
        character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
          ? Character(" ") : character
      })
    return title.count > 100 ? String(title.prefix(24)) + "…" + String(title.suffix(75)) : title
  }

  @discardableResult
  private func add(_ title: String, to menu: NSMenu, action: Selector) -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func placeholder(_ title: String, in menu: NSMenu) {
    let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
  }

  @objc private func reloadLibrary() { load() }

  @objc private func clearRecent() {
    do { library = try store.update { $0.clearRecentProjects() } } catch {
      show(error, title: "최근 목록을 지우지 못했어요")
    }
  }

  @objc private func openRecent(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String, directoryExists(path) else { return }
    manager.open(directory: path)
  }

  @objc private func openConfiguration(_ sender: NSMenuItem) {
    guard let value = sender.representedObject as? String,
      let entry = library.configurations.first(where: { $0.id.uuidString == value }),
      directoryExists(entry.projectDirectory)
    else { return }
    manager.open(configuration: entry)
  }

  private func directoryExists(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      let alert = NSAlert()
      alert.messageText = "프로젝트 폴더를 찾지 못했어요"
      alert.informativeText = "\(path)\n폴더 위치를 확인한 뒤 다시 열어 주세요."
      alert.addButton(withTitle: "확인")
      alert.runModal()
      return false
    }
    return true
  }

  @objc private func saveCurrent() {
    guard let controller = manager.active, controller.window?.attachedSheet == nil else { return }
    let field = InsetTextField(string: "")
    field.frame = NSRect(x: 0, y: 0, width: 300, height: 28)
    field.font = ChopStyle.font
    field.placeholderString = "구성 이름"
    field.setAccessibilityLabel("작업 구성 이름")
    let alert = NSAlert()
    alert.messageText = "작업 구성 저장"
    alert.informativeText = "배치와 폴더, 웹 주소를 저장해요. 실행 중인 명령은 저장하지 않아요."
    alert.accessoryView = field
    alert.addButton(withTitle: "취소").keyEquivalent = "\u{1b}"
    alert.addButton(withTitle: "저장").keyEquivalent = "\r"
    alert.window.initialFirstResponder = field
    while alert.runModal() == .alertSecondButtonReturn {
      do {
        let name = try ProjectLibrary.configurationName(field.stringValue)
        let current = try store.load()
        let existing = current.configuration(named: name, in: controller.projectDirectory)
        if let existing, !confirmReplacement(existing.name) { continue }
        library = try store.update {
          try $0.saveConfiguration(
            name: name, projectDirectory: controller.projectDirectory,
            workspace: controller.workspace.snapshot(),
            fileBrowser: controller.content.projectSettings,
            replacing: existing?.id)
        }
        break
      } catch { alert.informativeText = error.localizedDescription }
    }
    controller.workspace.focusedPane.focus()
  }

  private func confirmReplacement(_ name: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "‘\(name)’ 구성을 덮어쓸까요?"
    alert.informativeText = "저장한 배치와 폴더, 웹 주소가 현재 구성으로 바뀝니다."
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "덮어쓰기")
    return alert.runModal() == .alertSecondButtonReturn
  }

  @objc private func deleteConfiguration() {
    guard let controller = manager.active else { return }
    defer { controller.workspace.focusedPane.focus() }
    let entries = library.configurations(for: controller.projectDirectory)
    guard !entries.isEmpty else { return }
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
    picker.font = ChopStyle.font
    picker.setAccessibilityLabel("삭제할 작업 구성")
    picker.addItems(withTitles: entries.map(\.name))
    let alert = NSAlert()
    alert.messageText = "작업 구성 삭제"
    alert.informativeText = "저장한 구성만 삭제해요. 열린 창과 프로젝트 파일은 유지됩니다."
    alert.accessoryView = picker
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "삭제")
    guard alert.runModal() == .alertSecondButtonReturn,
      entries.indices.contains(picker.indexOfSelectedItem)
    else { return }
    do {
      let entry = entries[picker.indexOfSelectedItem]
      library = try store.update {
        try $0.removeConfiguration(entry.id, in: controller.projectDirectory)
      }
    } catch { show(error, title: "작업 구성을 삭제하지 못했어요") }
  }

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if item.action == #selector(clearRecent) { return !library.recentProjects.isEmpty }
    if item.action == #selector(saveCurrent) {
      return manager.active?.window?.isVisible == true
        && manager.active?.window?.attachedSheet == nil
    }
    if item.action == #selector(deleteConfiguration) {
      return manager.active.map { !library.configurations(for: $0.projectDirectory).isEmpty }
        ?? false
    }
    return true
  }

  private func show(_ error: Error, title: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "\(error.localizedDescription)\n\(store.fileURL.path)"
    alert.addButton(withTitle: "확인")
    alert.runModal()
  }
}
