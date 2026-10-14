# 코드·명세 대조

최종 스크롤백 변경까지 실제 diff와 아래 파일을 검토했다. `.cache/custom-effects-audit.txt`의 검색은 Sources와 terminal.conf의 shadow/gradient/cornerRadius에 매치가 없었다. 네이티브 AppKit 컨트롤 자체 효과는 이 검색의 대상이 아니며 계약에서 별도로 예외를 선언한다.

| 영역 | 소스와 실제 계약 |
|---|---|
| 색/글꼴/조작 크기 | ChopStyle: white, #24262B, system14 medium, header40, inset12, 아이콘 버튼28; terminal.conf: white/24262b/font14/padding12 |
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
