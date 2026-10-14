# 터미널 수로 막지 않는 좌우 배치

2026-10-15 KST, macOS26.5.2, 구현자 셀프 리뷰. 사용자 교정은 좌우 모드를2개 초과 실행 때문에 비활성화하지 말고 열린 터미널만큼 나란히 표시하는 것이다. 이 PR은 좌우와 그 상태에서 돌아갈 격자의 모든 pane 보존을 구현한다. 상하 전환은 별도 PR에서 마무리한다.

## 계약/구현

LayoutNode는 임의 개수의 UUID를 균형 잡힌 split tree로 만든다. 좌우는 전부 한 행, rows 모델은 한 열, 격자는 sqrt 기반 행으로 배치한다. 4개 격자의 기존2×2는 그대로다. defaultPaneCount는 초기 슬롯 수이지 최대 수가 아니다. 좌우/격자 applyPreset은 기존 empty/running pane 모두와 순서/포커스를 유지하고 필요한 최소2/4슬롯만 더한다. 5개 이상을 지우거나 거절하지 않는다.

실제 pane 문서는 기존 minimum280×180을 지키고 viewport는 최대2×2 최소값까지만 요구한다. 처음부터 화면보다 커진 창을 요구하지 않고 native scroller로 접근한다. 자유 추가도 화면 너비 때문에 막지 않으며 기존 총16칸/session 검증은 별개로 유지한다. 키보드 포커스/새 셸을 해당 viewport 안에 드러낸다. 확대/탭은 전체 split 문서의 큰 최소 크기를 해제하고 실제 표시 한 칸에 맞춘다. 파일 패널과 공통 toolbar는 viewport 바깥에서 기존 계층/폭/색을 유지한다.

## 발견한 실패와 수정

초기에는 가로 넘침 뒤 불필요한 세로 scroller가 생겼다. 실제 clip bounds와 legacy scroller의 축 변화를 기준으로 문서 크기를 맞추도록 수정했다. 첫 수정에서 layout 중 super.tile을 다시 호출해 실제 좌우→탭 전환 뒤 AppKit constraint display-cycle 예외로 앱이 종료됐다(02:17:51 로컬 crash report, _postWindowNeedsUpdateConstraints/NSScrollView._updateBetweenScrollersView). 자동 검사만으로 이 동작을 통과 처리하지 않았다.

최종판은 layout/tile 내부에서 재타일링하지 않고 다음 main queue 화면 갱신으로 문서 크기 정리를 넘긴다. native tiling이 바꾼 clip 크기는 다음 갱신에서 수렴시키고 변경이 없으면 끝낸다. 회귀 검사는 legacy scroller를 강제해 가로/세로 넘침에 반대 축이 추가되지 않는지 확인하고, PTY 모드 전환 사이에도 실제 화면 갱신 시점을 둔다. 이후 실제 좌우↔탭5회 왕복/새5번째 셸/좌우5/격자5/탭으로 돌아와 새 셸만 닫기와 추가 최종 확대→복귀→탭→좌우→격자를 확인했고 새 crash report는 없었다.

## 실제 CUA 관찰

기존4개 실행 셸11/16/5/6에서 좌우 버튼이 활성화되고4개의 같은 높이 열이 생겼다. 창1100×752에서 폭을 넘는 칸은 가로 스크롤로 접근한다. ⌘⌥→3회로 마지막6번에 포커스를 주면 그 칸이 보였다. 직접 Scroll Left로 앞쪽 칸도 볼 수 있었다. 불필요한 canvas 세로 scroller는 사라졌고 파일 목록의 세로 scroll은 유지됐다.

단일 보기의 +로 검증용5번째 셸을 연 뒤 좌우→격자로 전환해5개의 이름/셸이 보존되는 것을 실제 AX와 화면으로 확인했다. 격자는 위3/아래2였다. 그 셸만 탭 모드에서⌘W로 닫고 원래4개를 남겼다. 최종 수정본에서 검증 ENV를 넣고 모드/포커스/최소 창/라이트·다크 전환 뒤 첫 셸에서 같은 값을 다시 출력했다.

두 모드1100×752/최소842×442에서 가로 이동·본문/헤더/file peer/toolbar를 확인했다. 파일 패널 열기/기존 탐색은 유지됐다. 좌우에서 칸 확대는 scroller 없이 전체 viewport를 채우고 복귀하면 이전4열을 되돌렸다. 마지막은 기존4개/격자/다크/Downloads/1100×752로 복원했다. source cleanup 뒤 최종 clean 앱에서도 확대와 복귀/탭/좌우/격자를 다시 확인했다.

## 검증 범위

최종 ./scripts/check.sh PASS:22개 테스트4.734초 및 format/build/서명. 임의1/3/5/7/16개 모델의 중복 없는 모든 UUID·최소 크기·겹침 없음/저장 roundtrip, 실제4/5셸 좌우·격자 전환/surface identity/viewport focus/확대/탭 복귀와 기존 파일 panel 최소 공간 회귀, legacy scroller 반대 축 검사를 통과했다. 구16개 상한은 모델 검사 범위이며16개 실물 셸을 UI에서 띄웠다고 하지 않는다. VoiceOver 전체/macOS14 실기기/모든 TUI는 기존 미검증 범위다.
