import AppKit
import ChopCore

@MainActor
final class WorkspaceWindowManager {
  private let engine: TerminalEngine
  private let defaultsForWindow: (UUID) -> UserDefaults
  private(set) var windows: [UUID: WorkspaceWindowController] = [:]
  private var order: [UUID] = []
  private var focusedID: UUID?
  var onChange: (() -> Void)?
  var onAppearanceChangeRequested: ((AppearanceMode) -> Void)?

  init(
    engine: TerminalEngine,
    defaultsForWindow: @escaping (UUID) -> UserDefaults = {
      UserDefaults(suiteName: "com.safethecode.chop.window.\($0.uuidString)")!
    }
  ) {
    self.engine = engine
    self.defaultsForWindow = defaultsForWindow
  }

  var active: WorkspaceWindowController? {
    for candidate in [NSApp.keyWindow, NSApp.mainWindow] {
      if let candidate, let controller = windows.values.first(where: { $0.window === candidate }) {
        return controller
      }
    }
    return focusedID.flatMap { windows[$0] } ?? order.last.flatMap { windows[$0] }
  }

  var needsConfirmClose: Bool { windows.values.contains { $0.workspace.needsConfirmClose } }

  @discardableResult
  func open(
    directory: String? = nil, snapshot: WorkspaceWindowSnapshot? = nil,
    legacyDefaults: UserDefaults? = nil
  ) -> WorkspaceWindowController {
    let id = snapshot?.id ?? UUID()
    if let existing = windows[id] {
      activate(id)
      return existing
    }
    let path =
      snapshot?.projectDirectory ?? directory
      ?? FileManager.default.homeDirectoryForCurrentUser.path
    let defaults = defaultsForWindow(id)
    if let legacyDefaults {
      for key in ["fileTreeRootPath", "fileTreeVisible", "fileTreeWidth"] {
        if let value = legacyDefaults.object(forKey: key) { defaults.set(value, forKey: key) }
      }
    } else if snapshot == nil {
      defaults.set(path, forKey: "fileTreeRootPath")
    }
    let controller = WorkspaceWindowController(
      engine: engine, id: id, snapshot: snapshot?.workspace, projectDirectory: path,
      defaults: defaults)
    let previous = active?.window
    windows[id] = controller
    order.append(id)
    controller.workspace.onChange = { [weak self] in self?.onChange?() }
    controller.workspace.onAppearanceChangeRequested = { [weak self] mode in
      self?.onAppearanceChangeRequested?(mode)
    }
    controller.onActivate = { [weak self] in
      self?.focusedID = id
      self?.onChange?()
    }
    controller.onClose = { [weak self] in self?.remove(id) }
    if let frame = previous?.frame {
      controller.window?.cascadeTopLeft(from: NSPoint(x: frame.minX + 24, y: frame.maxY - 24))
    }
    activate(id)
    controller.workspace.layoutSubtreeIfNeeded()
    controller.workspace.startRestoredTerminals()
    onChange?()
    return controller
  }

  func activate(_ id: UUID) {
    guard let controller = windows[id] else { return }
    focusedID = id
    controller.showWindow(nil)
    if controller.window?.isMiniaturized == true { controller.window?.deminiaturize(nil) }
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private func remove(_ id: UUID) {
    windows.removeValue(forKey: id)
    order.removeAll { $0 == id }
    if focusedID == id { focusedID = order.last }
    onChange?()
  }

  func snapshot() -> ApplicationSnapshot {
    ApplicationSnapshot(
      windows: order.compactMap { id in
        guard let controller = windows[id] else { return nil }
        return WorkspaceWindowSnapshot(
          id: id, projectDirectory: controller.projectDirectory,
          workspace: controller.workspace.snapshot())
      }, focusedWindowID: active?.id)
  }

  func applyAppearance(_ mode: AppearanceMode) {
    for controller in windows.values { controller.workspace.applyAppearance(mode) }
  }

  func shutdown() {
    onChange = nil
    for controller in windows.values {
      controller.onClose = nil
      controller.onActivate = nil
      controller.workspace.closeAll()
      controller.window?.delegate = nil
      controller.window?.close()
    }
    windows.removeAll()
    order.removeAll()
    focusedID = nil
  }
}
