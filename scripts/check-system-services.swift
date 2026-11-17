import AppKit

// The integration suite exercises native clipboard data and must run with that service available.
let pasteboard =
  NSPasteboard.perform(NSSelectorFromString("pasteboardWithUniqueName"))?.takeUnretainedValue()
  as? NSPasteboard
let marker = UUID().uuidString
_ = pasteboard?.clearContents()
let available =
  pasteboard?.setString(marker, forType: .string) == true
  && pasteboard?.string(forType: .string) == marker
pasteboard?.releaseGlobally()
if !available {
  let message = """
    현재 실행 환경에서 macOS 클립보드 쓰기·읽기가 동작하지 않습니다.
    macOS에서 직접 연 Ghostty 또는 Terminal 앱에서 ./scripts/check.sh를 실행해 주세요.
    실제 클립보드를 사용하는 통합 검사는 생략하지 않고, 검사와 게시를 중단합니다.

    """
  FileHandle.standardError.write(Data(message.utf8))
  exit(1)
}
