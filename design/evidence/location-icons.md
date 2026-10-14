# 파일 바로가기 아이콘

2026-10-15 KST, macOS26.5.2, 구현자 셀프 리뷰. 사용자 제공 Finder crop는 [원본](../references/finder-shortcuts-user.png), 구현 전 역할/관계 분석은 [분해 기록](location-shortcuts-reference.md)이다. 검증은 아이콘 왼쪽/이름 오른쪽의 세로 행·같은 열/시작선 관계에 한정하며 Finder 전체 픽셀 복제를 주장하지 않는다.

구현: 홈/다운로드/문서의 native NSButton 안에16×16pt aspect-fit SF Symbols와8pt 뒤의14pt medium 이름을 배치한다. 각 행은28pt, 행간4pt, 기존 panel inset12를 사용한다. Glyph의 서로 다른 고유 폭이 label 시작점을 바꾸지 않는다. house/arrow.down.circle/doc 의미와 실제 목적지가 일치한다. label/icon AX child는 중복 노출하지 않고 native button에 목적지 이름과 기존 전체 경로 tooltip을 제공한다. hitTest는 행 안의 icon/label/빈 곳을 같은 버튼으로 전달하고 키보드/target-action은 native NSButton에 남긴다.

실제 CUA: 기본1100×752pt의 두 모드에서 세 아이콘 열/이름 시작선·가독성을 직접 비교했다. 홈 아이콘을 포인터로 눌러 홈 경로가 열리는 것을 확인했고 문서·다운로드도 눌러 각각 목적지 path/AX가 바뀌었다. 마지막 사용 중이던 다운로드로 복구했다. 실제 창을842×442pt까지 줄여 두 모드에서 모든 세 행/경로/헤더와 아래 파일 목록이 겹치거나 잘리지 않는 것을 봤다. 창을 원래 크기로 복구했다. 빈 임시 폴더를 열었을 때는 빈 상태만 나타나고 추가 scrollbar가 없었다. 실제 긴 목록은 기존 native scrollbar를 유지했다. 개인 폴더 이름은 공개 기록에 복사하지 않았다.

초기 native image-leading 버튼은 SF glyph 폭/광학 여백 때문에 이름 열이 달랐다. NSImage.size만 맞춰도 남는 것을 실제 화면에서 확인했다. 고정 icon view/간격을 갖는 native button 구성으로 바꿔 재검증했다(V-26 / F-SHORTCUT-ALIGNMENT). SF image의 원래 비율은 imageScaling으로 유지한다. frozen 분석의16pt box는 이 최종 고정 박스이며 glyph는14pt symbol configuration이다.

최종 ./scripts/check.sh16개 테스트4.907초 PASS(.cache/check-location-icons.log). 표시 상수를 반복하는 새 테스트는 만들지 않았다. 실제 클릭/이름·AX를 코드/기존 PTY·비동기/레이아웃 검사와 구분한다. 전체 VoiceOver/모든 키보드 설정을 검증했다고 주장하지 않는다. 이전 path focus-ring 제거와 header seam 수정은 최종 화면에서도 유지됐고 아직 파일 drag 기능을 완료했다고 표시하지 않는다.
