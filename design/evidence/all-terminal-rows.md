# 모든 터미널을 유지하는 상하 배치

2026-10-15 KST, macOS26.5.2, 구현자 셀프 리뷰. 사용자 교정은 세 번째 아이콘도2개 초과 실행 때문에 막지 말고 터미널 수만큼 가로 판을 세로로 쌓는 것이다. 이전 PR의 임의 개수 모델/scroll canvas를 재사용하고 마지막 fixed-capacity 축소/삭제 경로를 없앴다.

모든 non-single preset은 layout.paneIDs와 pane/surface/빈 칸/순서/선택을 유지한다. 처음 필요한 최소 슬롯만 추가하고, 적용할 때 이미 있는 칸을 없애지 않는다. rows는 전부 vertical tree이며40pt header와280×180 최소 pane을 유지한다. toolbar의 세 번째 AX/툴팁은 ‘상하로 나란히’다. 전환 버튼을 실행 셸 수로 비활성화하지 않는다. 기존 전체16칸 session/추가 경계와 초기2/4슬롯 수는 표시 모드별1/2/4 최대 수와 다르다.

CUA 실제 앱에서4개 실행 셸11/16/5/6으로 상하 모드에 전환해 네 행을 확인했다. ⌘⌥↓3회로6번에 focus가 가면 마지막 행 전체가 보였다. 실제 +로 검증용5번째 셸을 연 뒤 상하/좌우/격자/탭/상하/탭/좌우/상하를 전환해5개 모두 유지되는 AX/화면을 확인했다. 그 셸만⌘W로 닫아 원래4개가 남았다. 첫 셸에 둔 ENV를 모든 전환 뒤 다시 출력해 같은 값을 확인했다.

1100×752 및 실제 최소681×442에서 두 모드의 화면을 확인했다. native Scroll Up으로 앞 행을 볼 수 있고 세로 넘침에 canvas 가로 scroller가 생기지 않는다. 경로/바로가기와 file header/toolbar는 기존 peer 계층을 유지한다. 상하 모드/6번 선택을 저장하고 앱 종료 뒤 프로세스가 없는 것을 확인한 후 다시 실행했다. 상하 선택/네 이름/6번 first responder/네 셸이 복원됐다. 마지막은 원래4개 격자/첫 셸/다크/Downloads/1100×752로 복원했다. UI 검증 중 새 crash report는 없었다.

./scripts/check.sh PASS:22개 테스트5.388초,strict lint/build/서명. 기존 PTY flow에4/5개 rows 전환의 surface/모든 UUID 보존과 focus pane이 실제 viewport 안에 들어오는 검사를 더했다. 기존 임의1/3/5/7/16개 rows 모델/저장 검사와 scroller 반대 축/legacy/나머지 PTY 회귀도 통과했다. native 실행과 자동 검사는 구별하고 독립 외부 승인으로 표시하지 않는다. VoiceOver 전체/macOS14 실기기/모든 TUI는 기존 미검증 범위다.
