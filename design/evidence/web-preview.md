# 웹사이트 미리보기 검증

사용자 요청: 같은 창의 새 칸에서 로컬 페이지와 웹사이트를 연다. 추가 버튼·메뉴·안내·오류 문구는 한국어로 통일한다. 기존48pt rail·32pt 버튼·옅은 단일 경계를 보존하고, clone 위의 하단52pt에 globe 버튼을 둔다. 로컬 서버 주소 클릭은 새 웹 칸, 우클릭은 외부 브라우저 경로다. 빈 칸 우선·없으면 아래 행/새 탭 추가·전체16칸 한도·기존 셸은 유지한다. 동일 URL이 열려 있으면 그 칸을 선택한다.

웹 칸은 기존40pt header와 별도40pt 주소 행을 쓰고,28pt native 뒤로/앞으로/새로고침(로딩 중에는 중지)/외부 열기와 기존 blur inset 주소 입력을 둔다. 읽는 글자는14pt medium, 행 inset8/gap4, 빈/오류 안내는 기존 중립 면·보조 글자와12pt 그룹 간격이다(chosen/existing-token). 웹사이트가 그린 글자·색·기능은 제삼자 콘텐츠이며 Chop의14pt/테마로 덮어쓰지 않는다.

상태 계약: 빈 주소→입력/Enter→loading/stop→성공·navigation/history→오류/주소 수정/retry. 같은 WKWebView를 tab/grid/zoom/drag에서 이동해 문서와 입력 상태를 보존한다. 닫기/재실행 시 페이지의 메모리는 유지하지 않고 종류와 유효한 HTTP(S) 주소만 복원하며, 기존 terminal-only v1/v2 저장은 계속 읽는다. 주소나 저장된 문자열은 셸 명령/특수 URL scheme으로 실행하지 않는다. 인증서 오류는 WebKit 기본 처리를 유지한다. HTTP 로컬 네트워크만 ATS 예외로 선언하고 일반 연결 전체를 허용하지 않는다.

기존 default-grid-user.png의 동등한 열/행·작은 header·첫 실행/빈 중앙 plus 관계와 현재 native 토큰을 재사용한다. 새 브라우저 chrome은 외부 화면의 복제가 아닌 사용자 요구에 따른 제품 확장이다. 원본 crop의 폰트/상태 미확인은 그대로 남긴다. 첫 실제 렌더와 수치 대조, 한국어/긴 주소/좁은 폭/오류/재진입 검증은 후속 기록에서 실제 실행과 구별한다.

E-W0 첫 핵심 화면: 별도 bundle ID/세션 경로의 /tmp/ChopWebPreviewVerification.app에서 globe 버튼→기존 빈2번 칸이 웹1로 열림→localhost:61448 입력/Return을 직접 실행했다. 실제 HTTP fixture의 한국어 페이지·입력·링크와 '실시간 연결 확인1' WebSocket 이벤트를 AX/2200×1504px 이미지에서 확인했다. 터미널1의 기존 셸·3/4 중앙 plus·2×2 두 열/행·40pt header·48pt rail/세 버튼을 유지한다. 현재 canvas의 동등한 열/행 비율은 경계 시각 추정 약1(±0.01)로 이전 기본 crop의 약1과 허용0.02 안이다. 새 주소 행은 웹 칸 안에만 두며 옆 터미널/파일 헤더를 밀지 않는다. 첫 빈 화면은 비활성 창 색이었으므로 활성 대비의 최종 근거로 쓰지 않고, 실제 입력 후 활성 로컬 페이지를 별도로 판독했다. 첫 source와 그때 WebPreviewView를 web-preview-reference에 보존했다. 실제 CUA 캡처를 내보낸 PNG가 아니라 직접 본 화면/AX의 기록이다. 사용 중인 사용자 Chop은 종료하지 않았다.


E-W1 동작과 도입 결함: 실제 첫 페이지의 확인 버튼이 즉시 취소 결과를 반환했다. WKUIDelegate의 알림/확인/입력 시트를 연결하고 한국어 `웹사이트 알림`·`취소`·`확인`으로 수정했다. 새 검증 빌드에서 확인 버튼→native sheet→확인→페이지의 `확인했어요.`를 실행했다. 시트가 열린 상태에서⌘Q로 앱이 종료되고 process가 사라지는 것도 확인했다. 실제 문구를 제공하는 웹사이트 본문은 제삼자 콘텐츠다.

E-W2 같은 창·같은 상태: 웹1에 `보존할 한글 입력`을 붙여넣고 탭 전환→격자→두 모드 전환에서 유지되는 것을 AX/화면에서 확인했다. 다음 링크→다음 페이지→⌘[ 뒤로에서 입력 상태와 앞으로 버튼이 살아 있었다. 마지막 빌드에서는 `자리 바꿔도 유지`를 입력한 채 칸 확대/복귀→편집→`아래 칸과 자리 바꾸기` 메뉴를 실행해 웹1이 오른쪽 아래로 이동하고 같은 입력을 유지했다. 물리 drag의 GPU 미리보기 품질은 새 검증으로 주장하지 않는다. 새 창 링크(target=_blank)는 기존 웹 칸에서 URL이 바뀌고 별도 창/칸은 늘지 않았다.

E-W3 터미널 주소의 실제 목적지: 검증 앱 터미널1에서 자체 Python fixture를 실행해 localhost:50044가 헤더에 나타나는 것을 확인했다. 주소 클릭→기존 빈3번이 웹2로 열림→동일 주소 재클릭에서 칸 수가 늘지 않음을 확인했다. 터미널의 Ctrl+C로 서버를 중단한 뒤 웹2 새로고침에서 한국어 연결 오류/다시 불러오기 버튼이 나타났다. 앱을 재실행해 웹1 정상 페이지·웹2의 중단된 주소·터미널 새 셸이 각각 복원되는 것도 확인했다. 서버를 자동 재실행하지 않는다. 실제 라이브 업데이트는 fixture WebSocket의 1초 이벤트(최대119회)로 확인했으며 무제한 연결 검증으로 확대하지 않는다.

E-W4 작은 창·간격·언어: 실제2200×1504px 기본 창의 두 모드, native 드래그로 줄인1782×896px 창의280pt 칸을 직접 확인했다(이미지 px와 AppKit pt는 등치하지 않음). 긴 한글 query를 입력해도 주소 행/외부 버튼이 칸 안에 남고 header에 주소를 중복하지 않는다. 추가 영역은48pt/32pt/좌우8pt, clone과 globe의 수직 간격8pt를 유지하며 최소 창에서도 중앙 plus와 겹치지 않는다. 주소 행40pt·컨트롤28pt·inset8pt/gap4pt, 안내의 가로16pt 제한/세로중앙·버튼 간격12pt는 기존 토큰 확장으로 선택한 값이다. native geometry 검사로 두 모드/네 preset/트리 개폐의 모든 rail 버튼 크기·안쪽 배치·hit test·겹침을 확인했다. 화면에서도 옅은 단일 경계·중립 헤더·입력 inset을 확인했다. 페이지200% 확대(메뉴4회)와⌘0 복귀, 작은 창 다크 확대 칸, 파일 트리를 숨긴 탭 보기의 globe/선택/닫기와 고정 rail을 확인했다. 웹페이지 내부 스크롤은 사이트 콘텐츠이며 Chop의 추가 버튼/주소 행은 고정된다. CUA의 등호/복합 방향 단축키는 실제 결과가 없었으므로 메뉴 실행 결과와 구분한다. 전체 물리 키보드 조합 검증으로 주장하지 않는다.

E-W5 주소·초점·외부 연결: file:///tmp/미리보기 입력에서 한국어 HTTP/HTTPS 안내를 표시하고 실행하지 않았다. 주소를 고쳐 다시 정상 로컬 페이지를 열었다. 터미널이 first responder인 채 웹 새로고침을 누르면 키보드 초점이 터미널에 남던 문제를 발견했다. 웹 도구에서 실제 first responder를 옮기고 오류/빈 상태는 주소로 초점을 보내도록 수정했다. 최종 빌드에서 새로고침→⌘L에 해당 웹 주소가 선택되는 것을 확인했다. ⌘⇧B로 빈 칸이 웹3/빈 주소/비활성 history·reload·external 상태가 되는 것도 실행했다. https://www.apple.com/kr/의 실제 HTTPS 문서 로드와 `Apple (대한민국)` AX를 확인했다(해당 사이트의 내용/화면을 디자인 원본으로 삼지 않음). 웹1의 외부 열기는 고유한 자체 fixture query를 붙인 주소로 실행해 Chrome 주소/문서/실시간 이벤트를 확인하고 만든 탭만 닫았다. 브라우저 connector의 URL 선택 오류는 native CUA로 대체했으며 성공으로 표시하지 않는다.

E-W6 자동 검증: 최종 ./scripts/check.sh는 format·shell·plist·release build·codesign·icon과54개 테스트를 통과했다(17.704초 테스트). 새 주소 정규화/위험 scheme·인증정보 거부/이전 저장 호환/웹 저장 검증, 실제 WKWebView의 초기 연결 실패→서버 시작→재시도→뒤로/앞으로→잘못된 주소→복구, 혼합 칸의 두 모드·네 preset·동일 URL 재선택·기존 셸 PID/문서 입력/스크립트 보존·웹 도구 초점·재복원, 단일 빈 웹 저장 복원을 포함한다. 최초 offline fixture가 TCP socket을 bind만 한 채 남겨 연결 완료가 지연된 테스트 조건은 socket을 닫고 시작 신호에서 다시 listen하도록 수정했다. 제품의 연결 실패를 성공으로 완화하지 않았다. 테스트 저장소는 nonPersistent이고 자체 Python 서버/폴더/창을 정리한다.

검증 한계: 셀프 리뷰이며 독립 승인/외부 사람 리뷰가 아니다. macOS14 실기기, 전체 VoiceOver 읽기 순서, 물리 Reduce Motion/고대비, 인증 제공자 popup/카메라·마이크·다운로드 실파일·전체 단축키 조합은 새 성공으로 주장하지 않는다. 기존 엔진/아이콘/파일 검색·clone 과정의 미변경 근거는 이전 기록으로 남긴다. 새 앱 chrome의 언어는 한국어이고 코드 식별자·URL·브랜드 고유명은 그대로 쓴다. 사용 중인 원래 Chop은 종료하지 않았다.


E-W7 CI 호환 후속: 최초 원격 Xcode16.4/Swift6.1 빌드가 URL KVO closure의 같은 guard에서 self를 암시한 세 위치를 거부했다. self.isClosed/self.webView/self.updateURL로 참조를 명시했다. 같은54개 check.sh(17.470초)가 다시 통과했다. 재빌드한 실제 앱에서 기존1셸/3웹 탭과 선택 주소 복원→로컬 다음 링크→URL/뒤로 버튼 갱신을1782×896px 다크 화면과 AX에서 재확인했다. 초기 CUA pipe 연결 종료는 reset 후 복구했으며 그 실패를 앱 성공으로 표시하지 않는다. chrome의 간격/색/구조는 변경하지 않았고 앞선 전체 상태 관찰을 새 캡처로 바꾸지 않는다. 원격 최종 CI 결과는 PR에서 별도로 확인한다.


E-W8 자동 리뷰 후속: CodeRabbit의 두 주소 경계 지적을 먼저 테스트로 재현했다. query 안의 :// 때문에 scheme 없는 정상 주소3개가 거부됐고, 로딩 중 history.replaceState로4100자 query를 만들면 didFinish가 긴 URL을 저장해 SnapshotError.invalid를 일으켰다. scheme은 문자열 처음에서만 판별하고 호스트는 /·?·# 앞에서 자른다. updateURL의 공통 진입점에서 WebAddress.accepts를 확인해 didFinish와 History API에도 저장 계약을 적용했다. 수정 후54개 check.sh(17.497초)가 통과했다. 실제 최종 앱에서 localhost:61448/login?next=http://localhost:61448/를 입력해 정상 HTTP 문서를 확인했다. /long 페이지는 `주소 길이 4128자`를 AX로 표시하는 동안 native 주소/탭은 마지막 유효한 /long을 유지하고 종료한 검증 세션의 최장 webURL도27자였다. 후속 재실행에서도 해당 짧은 주소를 복원하고 정상 렌더했다. 새 chrome 구조·색은 바꾸지 않았다. 자동 리뷰의 최초 Swift CI 지적은 E-W7에서 이미 수정했다. 자동 리뷰를 외부 사람의 승인으로 표현하지 않으며 원격 최신 CI는 PR에서 확인한다.


E-W9 SDK·CI 진단 후속: e0995b3의 원격 실행42972203314는9분 동안 끝나지 않아 진단 로그를 확보하기 위해 취소했다. 반복 stack은 기존 realShellExecutesCommandAndReturnsToEmptyPane → verifyGlobalTerminalAddition:735 → TerminalPaneView.closeTerminal → Surface.deinit → pthread_join을 가리켰다.16칸에서 새로 다시 연 터미널을 즉시 닫는 위치이며 정확한 재현 조건/엔진 원인은 미확정이다. 기존 터미널 검사의 항목·기대값·실행 방식은 변경하지 않는다. 앞선73787b5의 원격54개 검사는24.733초에 통과했다.
같은 로그에서 Xcode16.4 SDK의 JS alert completion에는 MainActor 표기가 없어 optional delegate 일치 경고가 있는 것을 확인했다. SDK 세대에 맞춘 callback typealias를 사용하고 실제 WKWebView의 alert/confirm/prompt 시트를 클릭해 각각 JS 결과를 받는55번째 검사를 추가했다. 열린 confirm을 칸과 함께 닫을 때 false가 반환되고 시트도 제거됨을 확인한다. 최신 SDK의 같은 UI 구현과 한국어 버튼은 유지한다. 최종 로컬 ./scripts/check.sh는55개21.389초에 통과했고 새 delegate 일치 경고가 없다. 취소한 CI를 성공으로 표시하지 않으며 수정본에서 같은 전체 검사를 다시 실행한다.
