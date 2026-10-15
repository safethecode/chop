import AppKit
import GhosttyKit

enum AppearanceMode: String, CaseIterable {
  case light, dark

  static func load(from defaults: UserDefaults = .standard) -> Self {
    defaults.string(forKey: "appearanceMode").flatMap(Self.init(rawValue:)) ?? .light
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: "appearanceMode")
  }

  var title: String { self == .light ? "라이트 모드" : "다크 모드" }

  var ghosttyScheme: ghostty_color_scheme_e {
    self == .light ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
  }

  @MainActor var appearance: NSAppearance {
    NSAppearance(named: self == .light ? .aqua : .darkAqua)!
  }

  var background: NSColor {
    self == .light ? .white : NSColor(srgbRed: 30 / 255, green: 32 / 255, blue: 38 / 255, alpha: 1)
  }

  /// Separates pane metadata and controls from the terminal surface in either mode.
  var headerBackground: NSColor {
    self == .light
      ? NSColor(srgbRed: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1)
      : NSColor(srgbRed: 41 / 255, green: 45 / 255, blue: 53 / 255, alpha: 1)
  }

  /// Reuses the secondary surface to distinguish file contents from navigation controls.
  var fileListBackground: NSColor { headerBackground }

  var foreground: NSColor {
    self == .light ? NSColor(srgbRed: 36 / 255, green: 38 / 255, blue: 43 / 255, alpha: 1) : .white
  }

  var secondaryForeground: NSColor {
    self == .light
      ? NSColor(srgbRed: 98 / 255, green: 105 / 255, blue: 117 / 255, alpha: 1)
      : NSColor(srgbRed: 209 / 255, green: 213 / 255, blue: 219 / 255, alpha: 1)
  }
}
