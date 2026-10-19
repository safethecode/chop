import AppKit
import ChopCore

@MainActor
final class SessionCoordinator {
  let store: SessionStore
  private var snapshotProvider: (() -> ApplicationSnapshot?)?
  private(set) var migratedLegacyWorkspace = false
  private var pendingSave: Task<Void, Never>?
  private var stopped = false
  private var readBlocked = false
  private var reportedSaveFailure = false

  init(store: SessionStore) { self.store = store }

  func load() -> ApplicationSnapshot? {
    do {
      let result = try store.loadApplication()
      migratedLegacyWorkspace = result.migratedLegacyWorkspace
      if let backup = result.recoveredFile {
        let alert = NSAlert()
        alert.messageText = "저장된 레이아웃을 열지 못했어요"
        alert.informativeText = "기본 레이아웃에서 다시 시작합니다. 기존 파일은 \(backup.lastPathComponent)에 보관했어요."
        alert.addButton(withTitle: "확인")
        alert.runModal()
      }
      return result.snapshot
    } catch {
      readBlocked = true
      let alert = NSAlert()
      alert.messageText = "레이아웃을 불러오지 못했어요"
      alert.informativeText =
        "\(error.localizedDescription)\n기존 파일을 보호하기 위해 자동 저장을 멈췄어요. 터미널 메뉴에서 다시 저장할 수 있습니다."
      alert.addButton(withTitle: "확인")
      alert.runModal()
      return nil
    }
  }

  func attach(_ manager: WorkspaceWindowManager) {
    snapshotProvider = { [weak manager] in manager?.snapshot() }
    manager.onChange = { [weak self] in self?.scheduleSave() }
  }

  private func scheduleSave() {
    guard !stopped, !readBlocked else { return }
    pendingSave?.cancel()
    pendingSave = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
      self?.saveNow()
    }
  }

  @discardableResult
  func saveNow(reportFailure: Bool = true) -> Bool {
    pendingSave?.cancel()
    pendingSave = nil
    guard !stopped, !readBlocked, let snapshot = snapshotProvider?() else { return false }
    do {
      try store.save(snapshot)
      reportedSaveFailure = false
      return true
    } catch {
      guard reportFailure, !reportedSaveFailure else { return false }
      reportedSaveFailure = true
      let alert = NSAlert()
      alert.messageText = "레이아웃을 저장하지 못했어요"
      alert.informativeText = "\(error.localizedDescription)\n터미널 메뉴의 ‘레이아웃 다시 저장’으로 재시도할 수 있어요."
      alert.addButton(withTitle: "확인")
      alert.runModal()
      return false
    }
  }

  func retrySave() {
    if readBlocked {
      // Successfully read or quarantine the old file before allowing replacement.
      do {
        _ = try store.loadApplication()
        readBlocked = false
      } catch {
        let alert = NSAlert()
        alert.messageText = "기존 레이아웃 파일을 열 수 없어요"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "확인")
        alert.runModal()
        return
      }
    }
    reportedSaveFailure = false
    saveNow()
  }

  func prepareToTerminate() {
    stopped = true
    pendingSave?.cancel()
  }

  func confirmTerminationIfUnsaved() -> Bool {
    guard snapshotProvider != nil, !saveNow(reportFailure: false) else { return true }
    let alert = NSAlert()
    alert.messageText = "레이아웃을 저장하지 않고 종료할까요?"
    alert.informativeText = "현재 칸 배치와 작업 경로의 변경 사항을 저장하지 못했어요. 취소한 뒤 터미널 메뉴에서 다시 저장할 수 있습니다."
    alert.addButton(withTitle: "취소")
    alert.addButton(withTitle: "저장하지 않고 종료")
    return alert.runModal() == .alertSecondButtonReturn
  }
}
