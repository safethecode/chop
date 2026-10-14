# 파일 트리 → 터미널 경로 드롭

2026-10-15 KST, macOS26.5.2, 구현자 셀프 리뷰. 사용자 요청은 별도 PR의 파일/폴더 경로 입력이다. 구현/자동 검사와 실제 OS 드래그 관찰을 구분한다. 아래의 후속 실제 관찰로 파일 경로 입력을 확인했다.

## 코드와 자동 실행

FileBrowserView는 실제 entry만 NSURL pasteboard writer로 내보내고 native copy operation을 사용한다. 파일 이동/삭제나 목록 재배열을 하지 않는다. 일반 텍스트·웹 URL을 받지 않고 file URL만 읽는다. 실제 NSURL writer의 pasteboard types에 public.file-url이 포함되는 것도 별도의 private pasteboard 실행으로 확인했다.

TerminalFileDrop은 각 절대 file URL.path를 POSIX single-quoted 인자로 만들고 내부 apostrophe를 분리 인용한다. 인자 사이/마지막에 공백을 두며 newline/CR/tab/ESC/DEL/C1 제어 문자를 입력하지 않는다. 한글·공백·따옴표·달러·backtick·역슬래시·emoji ZWJ는 실제 /bin/sh argv roundtrip으로 검증했다. 제어 문자·비파일 URL·빈 입력은 거절한다.

TerminalView는 실행 중인 surface/window에만 native file URL 드롭을 받는다. AppKit drag tracking 뒤 main queue에서 여전히 살아 있는 같은 surface/window를 확인하고 focus+기존 insertText로 입력한다. Enter를 합성하거나 global clipboard를 사용하지 않는다. pane 재배치의 custom pasteboard type/모델/preview 구현은 그대로다.

최종 ./scripts/check.sh PASS:19개 테스트6.307초(.cache/check-file-drop.log). 추가한3개 테스트는 실제 셸 argv/제어 문자 거절/native file URL과 일반 문자열 구분을 확인한다. 기존 실제 PTY flow에는 다른 칸으로 drop 입력·first responder/선택 칸·같은 surface/clipboard 유지·닫힌 surface 거절을 추가했다. printf의 redirect 파일이 드롭 직후에는 없고 테스트가 Return을 따로 보낸 뒤에만 생성되며, 파일 내용이 정확히 원래 경로 한 인자와 같았다. 일반 drop 처리 호출과 실제 포인터 drag routing 검증은 다르다.

## 실제 앱 관찰과 후속 확인

최신 clean 앱을 사용자의 기존4칸/두 실행 셸로 띄웠다. 검증용 폴더에는 `프로젝트 폴더`와 `한글 '문서' $.txt`가 있고 실제 file outline에서 선택/이름/아이콘을 확인했다. 이전 입력 focus-ring/연결된 header/바로가기 행은 유지됐다.

CUA의 drag는 NSURL writer까지 호출했다. 임시 진단과 sample에서 AppKit NSCoreDragManager의 _dragUntilMouseUp/CoreDragStartDraggingAsync/SampleMouseAndKeyboard가 놓기 이벤트를 기다리는 것을 확인했다. destination draggingEntered는 관찰되지 않았고 터미널 경로 입력도 확인되지 않았다. 원인을 앱 드롭 처리 결함 또는 자동화 제한 하나로 확정하지 않는다. 초기 문맥 메뉴 가설 때문에 실제 메뉴/선택 로직을 바꾸지 않았다. 깨끗한 재실행에서는 file row 선택이 정상 작동했다. 임시 trace/helper/NSLog는 모두 제거했고19개 최종 검사를 재실행했다.

OS 드래그가 남아 키보드 종료가 처리되지 않는 시도에서는 CUA의 앱 메뉴로 정상 종료한 뒤 clean 빌드를 다시 띄웠다. 현재 검증용 두 항목이 보이는 앱을 열어 두고 사용자에게 실제 포인터로 파일을 터미널 본문에 놓았을 때 경로가 입력되는지 질문했다. 사용자 응답이나 완료된 native UI 관찰 없이 pass로 승격하지 않는다. 폴더 드롭·빈 칸 거절의 물리 입력·새 등록 후 pane 포인터 재배치는 아직 추가 관찰이 필요하며 모델/PTY 자동 검사와 혼동하지 않는다.

전체 VoiceOver/macOS14 실기기/모든 TUI는 기존 미검증 범위다. 파일 URL의 문자 경로를 입력하는 기능이며 셸의 현재 인용 문맥이나 모든 프로그램의 키 입력 동작까지 추론해 보장하지 않는다.

## E-DROP-END / 사용자 조작 후 실제 endpoint 관찰

01:40 KST CUA로 같은 clean 앱의 AX를 다시 읽었다. 사용자가 조작한 터미널11에 검증 fixture의 정확한 경로가 `…/한글 '\''문서'\'' $.txt` 형태의 single-quoted 인자로 들어가 있었다. 그 아래 셸이 그 파일 경로에 대해 permission denied를 출력했고 다음 프롬프트와 사용자의 별도 입력도 보였다. 다른 터미널16/5/6도 기존 이름과 별도 프롬프트를 유지했다. 자동화에서 놓기가 끝나지 않았던 최초 시도와 구분하여, 실제 사용자 조작 후 source 파일의 경로가 터미널 endpoint에 도달한 관찰로 기록한다. 사용자 입력/명령 내용과 개인 파일 목록은 공개 문서에 복사하지 않는다.

AX의 실행 결과만으로 Enter의 주체를 추론하지 않는다. Enter 미전송은 기존 실제 PTY 검사에서 Return 전에 redirect 파일이 없고 Return 뒤에만 생기는 것으로 검증했다. 물리 폴더 드롭·빈 칸 포인터 거절·추가 등록 후 pane 포인터 재배치의 모든 변형을 직접 실행했다고 주장하지 않으며, 이 경계/공존 동작은 URL/PTY·기존 모델/preview 검사와 코드의 pasteboard type 분리로 확인했다. 핵심 native 파일 드롭 입력 미확인 상태는 위 실제 endpoint 관찰로 해소했다.

원격 CI38599352217은 head b21a2c2에서 통과했다. CodeRabbit은 한도 리셋 뒤 run70d2f271-5442-4247-91db-26572dabfa33로 실제 리뷰를 시작했다. 최종 리뷰 결과와 후속 문서 head 검사는 PR 기록에 남긴다.

문서 후속 정리 시 전체 ./scripts/check.sh를 다시 실행해19개 테스트4.111초 및 build/lint/서명 검사를 통과했다.
