import AppKit
import QuartzCore

/// Native editors keep their text, selection, search buttons and accessibility behavior.
@MainActor
final class InsetTextField: NSTextField {
  private(set) lazy var inputBorder = InsetInputBorder(control: self, radius: 6)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = InsetTextCell(textCell: "")
    isEditable = true
    isSelectable = true
    isBezeled = true
    cell?.usesSingleLineMode = true
    cell?.isScrollable = true
    focusRingType = .none
    drawsBackground = false
    addSubview(inputBorder)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(frame:).") }
}

@MainActor
final class InsetSearchField: NSSearchField {
  private(set) lazy var inputBorder = InsetInputBorder(control: self, radius: 14)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    cell = InsetSearchCell(textCell: "")
    isEditable = true
    isSelectable = true
    isBezeled = true
    focusRingType = .none
    drawsBackground = false
    addSubview(inputBorder)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(frame:).") }
}

@MainActor
private final class InsetTextCell: NSTextFieldCell {
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    InsetInputBorder.drawBackground(cellFrame, radius: 6, view: controlView)
    drawInterior(withFrame: cellFrame, in: controlView)
  }
}

@MainActor
private final class InsetSearchCell: NSSearchFieldCell {
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    InsetInputBorder.drawBackground(cellFrame, radius: 14, view: controlView)
    drawInterior(withFrame: cellFrame, in: controlView)
  }
}

/// A clipped inner shadow crossfades without changing the editor's frame or intercepting input.
@MainActor
final class InsetInputBorder: NSView {
  static let transitionDuration: CFTimeInterval = 0.18
  private weak var control: NSTextField?
  private let radius: CGFloat
  let borderLayer = CALayer()
  private var tracking: NSTrackingArea?
  private var renderedSize = NSSize.zero
  private var renderedScale: CGFloat = 0
  private var renderedMode: AppearanceMode?
  private(set) var isHovered = false
  private(set) var isFocused = false
  var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  init(control: NSTextField, radius: CGFloat) {
    self.control = control
    self.radius = radius
    super.init(frame: control.bounds)
    autoresizingMask = [.width, .height]
    setAccessibilityElement(false)
    wantsLayer = true
    borderLayer.opacity = 0.10
    layer?.addSublayer(borderLayer)
    refreshImage()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(control:radius:).") }

  deinit { NotificationCenter.default.removeObserver(self) }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    let center = NotificationCenter.default
    center.removeObserver(self)
    if let control, let window {
      for name in [
        NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification,
      ] {
        center.addObserver(
          self, selector: #selector(refreshInteraction), name: name, object: control)
      }
      for name in [
        NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
        NSWindow.didUpdateNotification,
      ] {
        center.addObserver(
          self, selector: #selector(refreshInteraction), name: name, object: window)
      }
    }
    refreshImage()
    refreshInteraction()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    refreshImage()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    refreshImage()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    control?.needsDisplay = true
    refreshImage()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    tracking = area
    addTrackingArea(area)
    refreshInteraction()
  }

  override func mouseEntered(with event: NSEvent) {
    setInteraction(hovered: true, focused: isFocused)
  }
  override func mouseExited(with event: NSEvent) {
    setInteraction(hovered: false, focused: isFocused)
  }

  @objc private func refreshInteraction() {
    guard let control else { return }
    let active = window?.isKeyWindow == true && control.isEnabled
    let hovered =
      active
      && window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) }
        == true
    let focused = active && (control.currentEditor() != nil || window?.firstResponder === control)
    setInteraction(hovered: hovered, focused: focused)
  }

  func setInteraction(hovered: Bool, focused: Bool) {
    isHovered = hovered
    isFocused = focused
    let opacity: Float = focused ? 0.25 : hovered ? 0.17 : 0.10
    let reduceMotion = reducesMotion()
    // Window updates also arrive while editing; an unchanged state must not schedule another commit.
    guard borderLayer.opacity != opacity else {
      if reduceMotion { borderLayer.removeAnimation(forKey: "input-emphasis") }
      return
    }
    let current = borderLayer.presentation()?.opacity ?? borderLayer.opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    borderLayer.opacity = opacity
    CATransaction.commit()
    if reduceMotion {
      borderLayer.removeAnimation(forKey: "input-emphasis")
    } else {
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = current
      animation.toValue = opacity
      animation.duration = Self.transitionDuration
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      borderLayer.add(animation, forKey: "input-emphasis")
    }
  }

  private static func mode(for view: NSView) -> AppearanceMode {
    view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }

  static func drawBackground(_ rect: NSRect, radius: CGFloat, view: NSView) {
    mode(for: view).background.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
  }

  private func refreshImage() {
    guard layer != nil, bounds.width > 0, bounds.height > 0 else { return }
    let scale = window?.backingScaleFactor ?? 2
    let mode = Self.mode(for: self)
    guard bounds.size != renderedSize || scale != renderedScale || mode != renderedMode else {
      return
    }
    renderedSize = bounds.size
    renderedScale = scale
    renderedMode = mode
    let width = Int(ceil(bounds.width * scale))
    let height = Int(ceil(bounds.height * scale))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    context.scaleBy(x: scale, y: scale)
    let rect = NSRect(origin: .zero, size: bounds.size)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(shape)
    context.clip()
    let color = mode == .light ? NSColor.black.cgColor : NSColor.white.cgColor
    context.setFillColor(color)
    context.setShadow(offset: .zero, blur: 2.5 * scale, color: color)
    context.addRect(rect.insetBy(dx: -10, dy: -10))
    context.addPath(
      CGPath(
        roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: max(0, radius - 0.5),
        cornerHeight: max(0, radius - 0.5), transform: nil))
    context.drawPath(using: .eoFill)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    borderLayer.frame = bounds
    borderLayer.contentsScale = scale
    borderLayer.contents = context.makeImage()
    CATransaction.commit()
  }
}
