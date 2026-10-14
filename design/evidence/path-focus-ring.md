# 파일 경로 입력 포커스 테두리

2026-10-15 KST / macOS26.5.2 / 구현자 셀프 리뷰. 사용자 요청은 입력창 클릭 시 생기는 focus ring 제거다. 기존 native field 예외를 이 입력창에는 적용하지 않도록 범위를 바꿨다. 다른 요청의 헤더/바로가기/파일 드래그는 별도 PR로 진행한다.

- 코드: FileBrowserView의 pathField.focusRingType만 none으로 설정한다. blur/비활성화/first responder 제거를 하지 않는다. 경로 입력 액션, frame28pt, selection/caret, 다른 버튼·메뉴 초점과 terminal/no-pane-border 계약은 그대로다.
- 실제 CUA:1100×752pt 전체 창, 사용자 기존4칸과 다운로드 루트를 보존해 재실행했다. 다크에서 클릭+전체 선택, 라이트에서 선택 해제+좌우 커서 이동 중 파란 외곽선이 없었다. 선택 글자와 편집 커서는 보였다. x 입력/Backspace로 원래 경로로 되돌리고 Enter를 실행했으며 기존 루트 목록이 유지됐다. Tab/Shift-Tab 입력도 전달했으나 전체 AX 키보드 순서/VoiceOver를 완주했다고 주장하지 않는다. 다크로 복원했다.
- 필수 검사: ./scripts/check.sh PASS,16개 테스트3.597초. strict format/build/signature/기존 PTY·경로/비동기·계층 검사를 포함한다. 단일 native 표시 속성을 그대로 검사하는 새 테스트는 만들지 않았다. 로그 .cache/check-path-focus.log.
- 시각 증거는 CUA에서 직접 본 화면의 관찰 기록이다. PNG 파일/독립 승인이나 모든 OS 입력 조합 검증으로 표현하지 않는다. 개인 파일 이름은 공개 기록에 복사하지 않았다.

F-PATH-FOCUS / V-24: 사용자 교정. 기존 native input 예외 때문에 클릭 때 파란 외곽선이 남았다. 해당 field의 ring만 제거하고 두 모드 실제 편집을 확인해 fixed-and-verified다. 기존 terminal caret/포커스 제거 금지, toolbar 아래 hierarchy/검은 선 개폐 정책은 유지한다.
