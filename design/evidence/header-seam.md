# 터미널·파일 헤더 연결

2026-10-15 KST, macOS26.5.2, 구현자 셀프 리뷰. 사용자 교정은 두 헤더 사이의 유격이다. 실제 이전 화면에서 높이는 이미40pt였으나 두 영역 사이1pt native divider가 헤더 색 면을 끊었다. file header row만 spacing8이었고 terminal row는12였다. 전체 toolbar/peer hierarchy는 유지한다.

코드: ChopStyle.headerRow를 terminal/file 양쪽에서 사용해 horizontal/fill/spacing12/centerY를 통일했다. 파일 제목도 기존 AppearanceMode.foreground를 사용한다. WorkspaceSplitView는 기능 divider를 그대로 그리고 상단 header40pt에 해당하는 부분만 headerBackground로 연결한다. flipped/non-flipped 좌표와 bounds.height를 반영하며 숨긴 상태에는 그리지 않는다. divider 폭/hit 영역/최소 폭, native row와 terminal surface는 바꾸지 않는다.

실제 CUA1100×752pt: 다크/라이트에서 위/아래 헤더 경계와 제목·버튼 중앙을 대조했다. 파일 헤더와 첫 terminal header 사이 검은/밝은 틈이 없었다. native 경계를799→759로 이동해 파일 폭300→340pt로 바꿨다가 원복했고, 연결된 헤더와 폭 조절이 유지됐다. 패널 숨김에서는 가로 전체 canvas가 돌아오고 잔상이 없었다. 다시 열고 다크 편집 모드의4개 헤더/이동손잡이와 파일 헤더를 대조한 뒤 일반 모드로 복구했다. 사용자 폴더 이름은 공개 기록에 복사하지 않았다.

./scripts/check.sh16개 테스트3.606초 PASS. 실제 PTY/기존 preview geometry·계층·개폐/재열기·focus·theme 검사를 포함한다. 단순 색/spacing 상수를 반복하는 새 테스트는 만들지 않았다. 로그 .cache/check-header-seam.log. 기존 경로 field focus-ring 제거는 유지되고 새 파일 drag/shortcut icons는 이 PR에 포함하지 않는다.

V-25 / F-HEADER-SEAM: 사용자 교정 → 기능 divider의 header 구간과 서로 다른 row 구성을 수정 → 두 모드·개폐·실제 resize·편집 header에서 fixed-and-verified. 직접 CUA 화면 관찰 기록이며 PNG export/외부 승인/전 플랫폼 검증을 주장하지 않는다.
