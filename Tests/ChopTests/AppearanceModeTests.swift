import Foundation
import Testing

@testable import Chop

@Test func appearancePreferenceSurvivesReloadAndRejectsUnknownValues() throws {
  let suite = "chop-appearance-test-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  #expect(AppearanceMode.load(from: defaults) == .light)
  AppearanceMode.dark.save(to: defaults)
  #expect(AppearanceMode.load(from: try #require(UserDefaults(suiteName: suite))) == .dark)
  AppearanceMode.light.save(to: defaults)
  #expect(AppearanceMode.load(from: defaults) == .light)
  defaults.set("unknown-mode", forKey: "appearanceMode")
  #expect(AppearanceMode.load(from: defaults) == .light)
}
