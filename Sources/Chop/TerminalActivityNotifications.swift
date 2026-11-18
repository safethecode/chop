import AppKit
import ChopCore
import UserNotifications

@MainActor
final class TerminalActivityNotifications: NSObject, UNUserNotificationCenterDelegate {
  typealias Delivery = @MainActor (UNNotificationRequest) async throws -> Void
  private let defaults: UserDefaults
  private let delivery: Delivery?
  private let removal: (([String]) -> Void)?
  private var notificationCenter: UNUserNotificationCenter?
  private var openActions: [String: () -> Void] = [:]
  private var identifiers: [UUID: String] = [:]
  private var deliveryTasks: [UUID: Task<Void, Never>] = [:]
  private var lastSent: [UUID: Date] = [:]
  private(set) var isRequestingAuthorization = false
  var isEnabled: Bool { defaults.bool(forKey: "terminalActivityNotifications") }

  init(
    defaults: UserDefaults = .standard, delivery: Delivery? = nil,
    removal: (([String]) -> Void)? = nil
  ) {
    self.defaults = defaults
    self.delivery = delivery
    self.removal = removal
  }

  private func removeNotifications(_ identifiers: [String]) {
    notificationCenter?.removePendingNotificationRequests(withIdentifiers: identifiers)
    notificationCenter?.removeDeliveredNotifications(withIdentifiers: identifiers)
    removal?(identifiers)
  }

  private func center() -> UNUserNotificationCenter {
    if let notificationCenter { return notificationCenter }
    let value = UNUserNotificationCenter.current()
    value.delegate = self
    notificationCenter = value
    return value
  }

  func toggle() async {
    guard !isRequestingAuthorization else { return }
    if isEnabled {
      defaults.set(false, forKey: "terminalActivityNotifications")
      removeNotifications(Array(openActions.keys))
      openActions.removeAll()
      identifiers.removeAll()
      for task in deliveryTasks.values { task.cancel() }
      deliveryTasks.removeAll()
      lastSent.removeAll()
      return
    }
    isRequestingAuthorization = true
    defer { isRequestingAuthorization = false }
    let center = center()
    // Callback APIs keep notification objects on the main actor with older SDKs too.
    let allowed = await withCheckedContinuation { continuation in
      center.requestAuthorization(options: [.alert, .sound]) { allowed, error in
        continuation.resume(returning: allowed && error == nil)
      }
    }
    defaults.set(allowed, forKey: "terminalActivityNotifications")
    if !allowed {
      let alert = NSAlert()
      alert.messageText = "알림이 꺼져 있어요"
      alert.informativeText = "시스템 설정 → 알림 → Chop에서 알림을 허용해 주세요."
      alert.addButton(withTitle: "확인")
      alert.runModal()
    }
  }

  func post(id: UUID, name: String, status: ProgramStatus, onOpen: @escaping () -> Void) {
    guard isEnabled, status.state == .done || status.state == .blocked || status.state == .error
    else {
      return
    }
    let now = Date()
    lastSent = lastSent.filter { now.timeIntervalSince($0.value) < 60 }
    let delay = max(0, 3 - now.timeIntervalSince(lastSent[id] ?? .distantPast))
    clear(id)
    let identifier = "chop.activity.\(id.uuidString).\(UUID().uuidString)"
    identifiers[id] = identifier
    openActions[identifier] = onOpen
    let content = UNMutableNotificationContent()
    content.title = name
    content.body = status.statusLabel
    content.sound = .default
    let deliver: Delivery
    if let delivery {
      deliver = delivery
    } else {
      let center = center()
      deliver = { request in
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          center.add(request) { error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          }
        }
      }
    }
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    deliveryTasks[id] = Task { [weak self] in
      if delay > 0 {
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      }
      guard self?.openActions[identifier] != nil else { return }
      self?.lastSent[id] = Date()
      try? await deliver(request)
      if self?.openActions[identifier] == nil {
        self?.removeNotifications([identifier])
      }
      if self?.identifiers[id] == identifier { self?.deliveryTasks.removeValue(forKey: id) }
    }
  }

  func clear(_ id: UUID) {
    deliveryTasks.removeValue(forKey: id)?.cancel()
    guard let identifier = identifiers.removeValue(forKey: id) else { return }
    openActions.removeValue(forKey: identifier)
    removeNotifications([identifier])
  }

  func openNotification(_ identifier: String) {
    let action = openActions[identifier]
    action?()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let identifier = response.notification.request.identifier
    Task { @MainActor [weak self] in
      self?.openNotification(identifier)
      NSApp.activate(ignoringOtherApps: true)
    }
    completionHandler()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
}
