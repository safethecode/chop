import AppKit
import ChopCore
import Testing
import UserNotifications

@testable import Chop

@MainActor
@Test func activityNotificationsCancelLateDeliveryAndRouteOnlyCurrentRequests() async throws {
  let suite = "com.safethecode.chop.notification-test.\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(true, forKey: "terminalActivityNotifications")
  var requests: [UNNotificationRequest] = []
  var removed: [String] = []
  var pending: CheckedContinuation<Void, any Error>?
  defer { pending?.resume(throwing: CancellationError()) }
  var opened = 0
  let notifications = TerminalActivityNotifications(
    defaults: defaults,
    delivery: { request in
      requests.append(request)
      if requests.count == 1 {
        try await withCheckedThrowingContinuation { pending = $0 }
      }
    }, removal: { removed.append(contentsOf: $0) })
  let id = UUID()
  let done = try #require(ProgramStatus.parse("state=done"))
  let blocked = try #require(ProgramStatus.parse("state=blocked:kind=permission"))
  func waitFor(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
  }
  notifications.post(id: id, name: "검사 터미널", status: done) { opened += 1 }
  try await waitFor { pending != nil }
  let first = try #require(requests.first)
  #expect(first.content.title == "검사 터미널" && first.content.body == "완료")
  notifications.clear(id)
  removed.removeAll()
  pending?.resume()
  pending = nil
  try await waitFor { removed.contains(first.identifier) }
  notifications.openNotification(first.identifier)
  #expect(opened == 0)
  notifications.post(id: id, name: "검사 터미널", status: blocked) { opened += 10 }
  notifications.post(id: id, name: "검사 터미널", status: done) { opened += 1 }
  try await waitFor { requests.count == 2 }
  let latest = requests[1]
  #expect(latest.identifier != first.identifier && latest.content.body == "완료")
  notifications.openNotification(latest.identifier)
  #expect(opened == 1)
  notifications.clear(id)
  notifications.openNotification(latest.identifier)
  #expect(opened == 1)
  defaults.set(false, forKey: "terminalActivityNotifications")
  notifications.post(id: id, name: "꺼진 알림", status: done) { opened += 100 }
  #expect(requests.count == 2 && !notifications.isEnabled)
}
