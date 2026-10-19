import AppKit
import QuartzCore
import Testing

@testable import Chop

@MainActor
@Test func insetInputTransitionsPreserveGeometryAndRespectReducedMotion() throws {
  _ = NSApplication.shared
  let field = InsetTextField(frame: NSRect(x: 0, y: 0, width: 256, height: 28))
  let border = field.inputBorder
  border.reducesMotion = { false }
  let originalFrame = field.frame
  let originalImage = try #require(border.borderLayer.contents)
  let enter = try #require(
    NSEvent.enterExitEvent(
      with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
  border.mouseEntered(with: enter)
  #expect(border.isHovered && !border.isFocused)
  let hover = try #require(
    border.borderLayer.animation(forKey: "input-emphasis") as? CABasicAnimation)
  #expect(hover.keyPath == "opacity" && hover.duration > 0 && hover.duration < 0.3)
  border.setInteraction(hovered: true, focused: true)
  let focus = try #require(
    border.borderLayer.animation(forKey: "input-emphasis") as? CABasicAnimation)
  #expect((focus.toValue as? Float ?? 0) > (hover.toValue as? Float ?? 0))
  border.reducesMotion = { true }
  border.setInteraction(hovered: false, focused: false)
  #expect(border.borderLayer.animation(forKey: "input-emphasis") == nil)
  #expect(border.borderLayer.opacity == hover.fromValue as? Float)
  #expect(field.frame == originalFrame && border.frame == field.bounds)
  #expect(border.borderLayer.contents as AnyObject === originalImage as AnyObject)
  #expect(border.hitTest(NSPoint(x: 10, y: 10)) == nil)
  field.setFrameSize(NSSize(width: 300, height: 28))
  #expect(border.frame == field.bounds && border.borderLayer.frame == border.bounds)
  #expect(border.borderLayer.contents as AnyObject !== originalImage as AnyObject)
}

@MainActor
@Test func insetInputsKeepNativeEditorCompositionAndFocusHandoff() throws {
  _ = NSApplication.shared
  let path = InsetTextField(frame: NSRect(x: 12, y: 60, width: 256, height: 28))
  let search = InsetSearchField(frame: NSRect(x: 12, y: 12, width: 256, height: 28))
  let window = InputTestWindow(
    contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
    styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  window.contentView?.addSubview(path)
  window.contentView?.addSubview(search)
  for field in [path, search] {
    field.selectText(nil)
    let editor = try #require(field.currentEditor() as? NSTextView)
    editor.setMarkedText(
      "한", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 0, length: 0))
    #expect(editor.hasMarkedText())
    let border = field === path ? path.inputBorder : search.inputBorder
    border.setInteraction(hovered: true, focused: true)
    #expect(field.currentEditor() === editor && editor.hasMarkedText())
    editor.insertText("한글", replacementRange: NSRange(location: 0, length: 1))
    #expect(!editor.hasMarkedText() && editor.string == "한글")
    NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
    #expect(border.isFocused)
    window.makeFirstResponder(nil)
    NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
    #expect(!border.isFocused && field.stringValue == "한글")
  }
  let cell = try #require(search.cell as? NSSearchFieldCell)
  #expect(cell.searchButtonRect(forBounds: search.bounds).width > 0)
  #expect(cell.cancelButtonRect(forBounds: search.bounds).width > 0)
  search.selectText(nil)
  window.reportsKey = false
  NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
  #expect(!search.inputBorder.isFocused && !search.inputBorder.isHovered)
}

@MainActor
private final class InputTestWindow: NSWindow {
  // Test key/inactive states without depending on the test runner becoming the frontmost app.
  var reportsKey = true
  override var isKeyWindow: Bool { reportsKey }
}
