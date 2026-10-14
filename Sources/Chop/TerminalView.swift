// Input integration follows Ghostty's MIT-licensed AppKit embedder.
// See Resources/Ghostty-LICENSE and Dependencies/README.md.
import AppKit
import GhosttyKit

@MainActor
final class TerminalView: NSView, @preconcurrency NSTextInputClient {
  private(set) var surface: ghostty_surface_t?
  var onExit: (() -> Void)?
  var onFocus: (() -> Void)?
  var onMetadataChange: (() -> Void)?
  var terminalTitle = "" { didSet { onMetadataChange?() } }
  var workingDirectory: String { didSet { onMetadataChange?() } }
  private var markedText = ""
  private var textAccumulator: [String]?
  private var lastPixelSize: CGSize = .zero
  private var lastScale: CGFloat = 0

  override var acceptsFirstResponder: Bool { true }

  init(
    engine: TerminalEngine, workingDirectory: String,
    frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 600)
  ) throws {
    self.workingDirectory = workingDirectory
    super.init(
      frame: NSRect(
        origin: .zero, size: NSSize(width: max(1, frame.width), height: max(1, frame.height))))
    // Ghostty installs its IOSurface layer before enabling wantsLayer.
    // Enabling layer backing here would prevent that layer-hosting setup.
    setAccessibilityElement(true)
    setAccessibilityRole(.textArea)
    setAccessibilityLabel("터미널")
    guard let app = engine.app else { throw TerminalError.initialization }
    var config = ghostty_surface_config_new()
    config.platform_tag = GHOSTTY_PLATFORM_MACOS
    config.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
    config.userdata = Unmanaged.passUnretained(self).toOpaque()
    config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
    surface = workingDirectory.withCString {
      config.working_directory = $0
      if let command = engine.command {
        return command.withCString {
          config.command = $0
          return ghostty_surface_new(app, &config)
        }
      }
      return ghostty_surface_new(app, &config)
    }
    guard let surface else { throw TerminalError.surface }
    ghostty_surface_set_color_scheme(surface, GHOSTTY_COLOR_SCHEME_LIGHT)
    updateTrackingAreas()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(engine:workingDirectory:).") }

  func close() {
    if let surface { ghostty_surface_free(surface) }
    surface = nil
  }

  var needsConfirmClose: Bool {
    surface.map { ghostty_surface_needs_confirm_quit($0) } ?? false
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    setVisible(window != nil)
    updateSize()
  }

  func setVisible(_ visible: Bool) {
    guard let surface else { return }
    ghostty_surface_set_occlusion(surface, visible)
    if visible { ghostty_surface_refresh(surface) }
  }

  override func layout() {
    super.layout()
    updateSize()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateSize()
  }

  private func updateSize() {
    guard let surface, bounds.width > 0, bounds.height > 0 else { return }
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    guard pixels != lastPixelSize || scale != lastScale else { return }
    lastPixelSize = pixels
    lastScale = scale
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.contentsScale = scale
    CATransaction.commit()
    ghostty_surface_set_content_scale(surface, scale, scale)
    ghostty_surface_set_size(surface, UInt32(bounds.width * scale), UInt32(bounds.height * scale))
    ghostty_surface_refresh(surface)
  }

  override func becomeFirstResponder() -> Bool {
    if let surface { ghostty_surface_set_focus(surface, true) }
    onFocus?()
    return true
  }

  override func resignFirstResponder() -> Bool {
    if let surface { ghostty_surface_set_focus(surface, false) }
    return true
  }

  override func keyDown(with event: NSEvent) {
    let wasComposing = hasMarkedText()
    textAccumulator = []
    interpretKeyEvents([event])
    let text = textAccumulator ?? []
    textAccumulator = nil
    syncPreedit()
    if text.isEmpty {
      sendKey(
        event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
        text: event.characters, composing: wasComposing || hasMarkedText())
    } else {
      for item in text {
        sendKey(
          event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
          text: item, composing: false)
      }
    }
  }

  override func keyUp(with event: NSEvent) {
    sendKey(event, action: GHOSTTY_ACTION_RELEASE, text: nil, composing: hasMarkedText())
  }

  private func sendKey(
    _ event: NSEvent, action: ghostty_input_action_e, text: String?, composing: Bool
  ) {
    guard let surface else { return }
    var key = ghostty_input_key_s()
    key.action = action
    key.keycode = UInt32(event.keyCode)
    key.mods = Self.modifiers(event.modifierFlags)
    key.consumed_mods = Self.modifiers(event.modifierFlags.subtracting([.command, .control]))
    key.unshifted_codepoint =
      event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
    key.composing = composing
    // Control and function keys must be encoded by Ghostty, never as text.
    if let text, let first = text.unicodeScalars.first,
      first.value >= 0x20, !(0xF700...0xF8FF).contains(first.value)
    {
      text.withCString {
        key.text = $0
        _ = ghostty_surface_key(surface, key)
      }
    } else {
      _ = ghostty_surface_key(surface, key)
    }
  }

  static func modifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var value: UInt32 = 0
    if flags.contains(.shift) { value |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { value |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { value |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { value |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { value |= GHOSTTY_MODS_CAPS.rawValue }
    return ghostty_input_mods_e(value)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
  }

  override func mouseMoved(with event: NSEvent) {
    guard let surface else { return }
    let point = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(
      surface, point.x, bounds.height - point.y, Self.modifiers(event.modifierFlags))
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    mouseMoved(with: event)
    if let surface {
      _ = ghostty_surface_mouse_button(
        surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, Self.modifiers(event.modifierFlags))
    }
  }

  override func mouseUp(with event: NSEvent) {
    mouseMoved(with: event)
    if let surface {
      _ = ghostty_surface_mouse_button(
        surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, Self.modifiers(event.modifierFlags))
    }
  }

  override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }

  override func scrollWheel(with event: NSEvent) {
    guard let surface else { return }
    let momentum: Int32
    switch event.momentumPhase {
    case .began: momentum = 1
    case .stationary: momentum = 2
    case .changed: momentum = 3
    case .ended: momentum = 4
    case .cancelled: momentum = 5
    case .mayBegin: momentum = 6
    default: momentum = 0
    }
    let mods = (event.hasPreciseScrollingDeltas ? 1 : 0) | (momentum << 1)
    ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, mods)
  }

  @objc func copy(_ sender: Any?) { performBinding("copy_to_clipboard") }
  @objc func paste(_ sender: Any?) { performBinding("paste_from_clipboard") }
  override func selectAll(_ sender: Any?) { performBinding("select_all") }
  override func scrollPageUp(_ sender: Any?) { performBinding("scroll_page_up") }
  override func scrollPageDown(_ sender: Any?) { performBinding("scroll_page_down") }
  @objc func scrollToTop(_ sender: Any?) { performBinding("scroll_to_top") }
  @objc func scrollToBottom(_ sender: Any?) { performBinding("scroll_to_bottom") }

  private func performBinding(_ action: String) {
    if let surface {
      action.withCString {
        _ = ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count))
      }
    }
  }

  func hasMarkedText() -> Bool { !markedText.isEmpty }
  func markedRange() -> NSRange {
    hasMarkedText()
      ? NSRange(location: 0, length: (markedText as NSString).length)
      : NSRange(location: NSNotFound, length: 0)
  }
  func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    markedText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    if textAccumulator == nil { syncPreedit() }
  }

  func unmarkText() {
    markedText = ""
    syncPreedit()
  }

  func insertText(_ string: Any, replacementRange: NSRange) {
    let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    unmarkText()
    if textAccumulator != nil {
      textAccumulator?.append(value)
    } else if let surface {
      value.withCString { ghostty_surface_text(surface, $0, UInt(value.utf8.count)) }
    }
  }

  override func doCommand(by selector: Selector) {}

  private func syncPreedit() {
    guard let surface else { return }
    if markedText.isEmpty {
      ghostty_surface_preedit(surface, nil, 0)
    } else {
      markedText.withCString { ghostty_surface_preedit(surface, $0, UInt(markedText.utf8.count)) }
    }
  }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  { nil }
  func characterIndex(for point: NSPoint) -> Int { 0 }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    guard let surface, let window else { return .zero }
    var x = 0.0
    var y = 0.0
    var width = 0.0
    var height = 0.0
    ghostty_surface_ime_point(surface, &x, &y, &width, &height)
    let rect = NSRect(x: x, y: bounds.height - y, width: max(width, 1), height: max(height, 1))
    return window.convertToScreen(convert(rect, to: nil))
  }

  override func accessibilityValue() -> Any? {
    guard let surface else { return "" }
    let selection = ghostty_selection_s(
      top_left: ghostty_point_s(
        tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
      bottom_right: ghostty_point_s(
        tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
      rectangle: false)
    var text = ghostty_text_s()
    guard ghostty_surface_read_text(surface, selection, &text), let contents = text.text else {
      return ""
    }
    defer { ghostty_surface_free_text(surface, &text) }
    return String(cString: contents)
  }
}
