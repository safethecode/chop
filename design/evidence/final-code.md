# 코드·명세 대조

최종 스크롤백 변경까지 실제 diff와 아래 파일을 검토했다. `.cache/custom-effects-audit.txt`의 검색은 Sources와 terminal.conf의 shadow/gradient/cornerRadius에 매치가 없었다. 네이티브 AppKit 컨트롤 자체 효과는 이 검색의 대상이 아니며 계약에서 별도로 예외를 선언한다.

| 영역 | 소스와 실제 계약 |
|---|---|
| 색/글꼴/조작 크기 | AppearanceMode: light white/24262B/626975, dark 1E2026/white/D1D5DB; ChopStyle: system14 medium/header40/inset12/아이콘28; terminal.conf: font14/padding12와 두 terminal-light/dark.conf 팔레트 |
| 공간과 토큰 사용 | Pane header/toolbar labels use ChopStyle.font; header row fill/centerY/12pt symmetric inset; terminal body has no extra content padding; toolbar48/12pt inset |
| 핵심 행동 | Pane.openTerminal creates TerminalView/ghostty_surface, open guard avoids duplicates; explicit close frees it; stale onExit identity guard |
| 레이아웃 | ChopCore.LayoutNode: stable UUID leaves, recursive splits, minimum280×180, one-point native draggable separator; preset shrink keeps all running identities |
| 입력과 수명 | TerminalView NSTextInputClient, keyboard, mouse selection, scrollWheel forwarding, clipboard binding, resize/occlusion; Ghostty installs own layer before wantsLayer |
| 포커스/확대 | canonical tree + stable pane dictionary; spatial neighbor, one focus boundary, maximize reparents rather than restarting; all panes checked on quit/window close |
| 중앙 + | empty opens existing slot; editing running slot opens directional native menu; no persistent overlay during ordinary terminal use |
| 세션 | snapshot stores only version/layout/pane id/name/cwd/wasRunning/focus; validates references/depth/count/finite ratio/path; atomic write/private modes; unreadable original quarantined |
| 오류 | native alerts for missing directories, corrupt file/save failure; retry save; failed initial read blocks automatic overwrite; unflushed quit may be canceled |
| 아이콘과 접근 경로 | NSButton/SF Symbols plus,xmark,zoom/restore; tooltip and AX label; header controls28pt and plus56pt; menu/keyboard equivalents; native cursor and chrome |
| 스크롤 | native edit menu uses responder chain and four Ghostty binding actions; viewport regression test reads actual visible output, not just command echo |

배경과 UI 위계는 `DESIGN.md`, 범위/사용법은 `README.md`를 대조했다. 왼쪽 탭, fake terminal, 요청 없는 로고/슬로건, 카드/배지/hero, 장식 구분선과 불필요한 chrome scroll container가 없다. cmux의 GPL 코드를 복사하지 않았으며 Ghostty의 pinned MIT source/license는 Dependencies/README와 Resources에 남아 있다.

단위는 macOS pt다. 웹 CSS px를 계측했다고 쓰지 않는다. 네이티브 표준 시트/메뉴의 내부 여백·글꼴과 셸/TUI가 출력하는 VT 서식은 앱이 소유한 라벨 토큰과 구분한다. VoiceOver 전체를 검증했다는 주장은 하지 않는다.

PR #7 기본 상태 재검토: WorkspaceView.init은 fresh/이전 단일 빈 저장을 grid로 구성한다. window 배치 후 startRestoredTerminals가 저장 실행 칸 또는 실행 칸이 없을 때 첫 칸만 연다. 다음 빈 칸은 기존 openTerminal guard와 중앙 +를 사용한다. LayoutSplitView는 window minimum 적용 전 0-size 배치도 부모 영역 안으로 제한한다.

PR #8 화면 모드 재검토: 양쪽 번들 설정을 시작 시 검증하고 app_update_config로 기존/숨긴 surface와 이후 새 surface 설정을 갱신한다. weak TerminalView registry가 각 scheme을 전달한다. Workspace의 pane 사전을 순회해 숨긴 헤더까지 갱신하며 AppDelegate가 NSApp.appearance와 UserDefaults를 변경한다. 포커스 CGColor는 선택 appearance 안에서 다시 계산한다. start 시 저장 모드를 먼저 적용하고, 메뉴 검증은 창이 닫힌 상태에서도 모드 선택을 허용한다. 셸을 닫거나 레이아웃·포커스를 바꾸는 호출은 전환 경로에 없다. 실제 두 모드와 native 이름 변경 대화상자, 반복 전환/숨긴 칸/새 셸/재실행을 대조했다.

PR #10 toolbar 재검토: Workspace의 모드 버튼은 onAppearanceChangeRequested를 통해 AppDelegate의 공통 applyAppearance로 라우팅한다. 메뉴도 같은 함수로 저장/NSApp appearance/전체 칸을 갱신한다. weak self callback으로 순환 참조를 피한다. applyAppearance는 모드 버튼 image/tooltip/AX를 갱신한다. LayoutPreset rawValue 순서에 해당하는 네 SF Symbol image와 image 접근성 설명/tooltip을 native segmented control에 지정했다. 기존 selectPreset/applyPreset와 running guard를 그대로 사용한다. 새 segment 폭32와 icon14pt medium 이외에 기존 toolbar48/inset12/spacing12/본문 제약은 유지한다.
