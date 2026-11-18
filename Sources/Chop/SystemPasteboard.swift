import AppKit

@MainActor
enum SystemPasteboard {
  /// AppKit's nonnull getter can return nil when the pasteboard service is unavailable.
  /// Preserve the nullable Objective-C result instead of importing a null Swift object.
  static func general() -> NSPasteboard? {
    NSPasteboard.perform(NSSelectorFromString("generalPasteboard"))?.takeUnretainedValue()
      as? NSPasteboard
  }
}
