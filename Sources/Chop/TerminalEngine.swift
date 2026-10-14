import AppKit
import GhosttyKit

private func wakeupGhostty(_ userdata: UnsafeMutableRawPointer?) {
  TerminalEngine.wakeup()
}

enum TerminalError: LocalizedError {
  case initialization, configuration, surface

  var errorDescription: String? {
    switch self {
    case .initialization: "터미널을 준비하지 못했어요."
    case .configuration: "터미널 설정을 읽지 못했어요."
    case .surface: "터미널을 열지 못했어요."
    }
  }
}

@MainActor
final class TerminalEngine: NSObject {
  private static weak var shared: TerminalEngine?
  private(set) var app: ghostty_app_t?
  private var config: ghostty_config_t?
  private let clipboard: NSPasteboard
  let command: String?

  init(clipboard: NSPasteboard = .general, command: String? = nil) {
    self.clipboard = clipboard
    self.command = command
    super.init()
  }

  func start(resources: URL? = Bundle.main.resourceURL) throws {
    guard app == nil else { return }
    guard let resources else { throw TerminalError.configuration }
    let configPath = resources.appendingPathComponent("terminal.conf").path
    setenv("GHOSTTY_RESOURCES_DIR", resources.appendingPathComponent("ghostty").path, 1)
    guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
      throw TerminalError.initialization
    }
    guard let config = ghostty_config_new() else { throw TerminalError.configuration }
    self.config = config
    guard configPath.withCString({ chop_ghostty_config_load_file(config, $0) }) else {
      shutdown()
      throw TerminalError.configuration
    }
    ghostty_config_finalize(config)
    guard ghostty_config_diagnostics_count(config) == 0 else {
      shutdown()
      throw TerminalError.configuration
    }

    Self.shared = self
    // The embedder calls actions and clipboard callbacks on the app thread.
    // Only wakeup may run on an IO thread; it queues a tick without retaining
    // any raw userdata pointer across the dispatch boundary.
    var runtime = ghostty_runtime_config_s(
      userdata: nil,
      supports_selection_clipboard: false,
      wakeup_cb: wakeupGhostty,
      action_cb: { _, target, action in
        MainActor.assumeIsolated { TerminalEngine.handle(target: target, action: action) }
      },
      read_clipboard_cb: { userdata, _, state in
        MainActor.assumeIsolated {
          guard let view = TerminalEngine.view(userdata), let surface = view.surface else { return }
          let text = TerminalEngine.shared?.clipboard.string(forType: .string) ?? ""
          text.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
        }
      },
      confirm_read_clipboard_cb: { userdata, text, state, request in
        MainActor.assumeIsolated {
          TerminalEngine.confirmPaste(
            userdata: userdata, text: text, state: state, request: request)
        }
      },
      write_clipboard_cb: { _, text, _, confirm in
        MainActor.assumeIsolated {
          guard !confirm, let text else { return }
          guard let clipboard = TerminalEngine.shared?.clipboard else { return }
          clipboard.clearContents()
          clipboard.setString(String(cString: text), forType: .string)
        }
      },
      close_surface_cb: { userdata, _ in
        MainActor.assumeIsolated {
          guard let view = TerminalEngine.view(userdata) else { return }
          DispatchQueue.main.async { [weak view] in view?.onExit?() }
        }
      }
    )
    guard let app = ghostty_app_new(&runtime, config) else {
      shutdown()
      throw TerminalError.initialization
    }
    self.app = app
    ghostty_app_set_color_scheme(app, GHOSTTY_COLOR_SCHEME_LIGHT)
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(focusChanged), name: NSApplication.didBecomeActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(focusChanged), name: NSApplication.didResignActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(keyboardChanged),
      name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
    focusChanged()
  }

  func shutdown() {
    NotificationCenter.default.removeObserver(self)
    if let app { ghostty_app_free(app) }
    app = nil
    if let config { ghostty_config_free(config) }
    config = nil
    Self.shared = nil
  }

  private func tick() {
    if let app { ghostty_app_tick(app) }
  }

  nonisolated fileprivate static func wakeup() {
    DispatchQueue.main.async { TerminalEngine.shared?.tick() }
  }

  @objc private func focusChanged() {
    if let app { ghostty_app_set_focus(app, NSApp.isActive) }
  }

  @objc private func keyboardChanged() {
    if let app { ghostty_app_keyboard_changed(app) }
  }

  private static func view(_ userdata: UnsafeMutableRawPointer?) -> TerminalView? {
    guard let userdata else { return nil }
    return Unmanaged<TerminalView>.fromOpaque(userdata).takeUnretainedValue()
  }

  private static func handle(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
    guard target.tag == GHOSTTY_TARGET_SURFACE,
      let surface = target.target.surface,
      let view = view(ghostty_surface_userdata(surface))
    else { return false }
    switch action.tag {
    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
      // Ghostty classifies very short macOS sessions as abnormal regardless
      // of exit status. Chop always returns an exited shell to an empty slot.
      DispatchQueue.main.async { [weak view] in view?.onExit?() }
    case GHOSTTY_ACTION_SET_TITLE:
      if let title = action.action.set_title.title { view.terminalTitle = String(cString: title) }
    case GHOSTTY_ACTION_PWD:
      if let path = action.action.pwd.pwd { view.workingDirectory = String(cString: path) }
    case GHOSTTY_ACTION_MOUSE_SHAPE:
      NSCursor.iBeam.set()
    case GHOSTTY_ACTION_RENDER:
      ghostty_surface_draw(surface)
    default:
      return false
    }
    return true
  }

  private static func confirmPaste(
    userdata: UnsafeMutableRawPointer?, text: UnsafePointer<CChar>?,
    state: UnsafeMutableRawPointer?, request: ghostty_clipboard_request_e
  ) {
    guard let view = view(userdata), let surface = view.surface else { return }
    // OSC clipboard reads are denied in terminal.conf. Only explicit paste
    // confirmation requests can expose clipboard contents.
    guard request == GHOSTTY_CLIPBOARD_REQUEST_PASTE, let text else {
      ghostty_surface_complete_clipboard_request(surface, "", state, true)
      return
    }
    let value = String(cString: text)
    let alert = NSAlert()
    alert.messageText = "여러 줄을 붙여넣을까요?"
    alert.informativeText = "줄바꿈이 있는 내용은 명령을 실행할 수 있어요."
    alert.addButton(withTitle: "붙여넣기")
    alert.addButton(withTitle: "취소")
    // Called on the main thread, before returning to Ghostty's read callback.
    let confirmed = alert.runModal() == .alertFirstButtonReturn
    let contents = confirmed ? value : ""
    contents.withCString {
      ghostty_surface_complete_clipboard_request(surface, $0, state, true)
    }
  }
}
