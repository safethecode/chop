# 최종 로컬 검사 실행 기록

2026-10-14, macOS 26.5.2 Apple Silicon / Xcode 26.6 Swift 6.3.3.
명령: `./scripts/check.sh`, 종료 코드 0, 마지막 출력 `All checks passed.`
원본 로그는 로컬 생성물 `.cache/check.log`에 있으며 이 문서는 실행 결과 요약이다.

- swift-format strict, bash 문법, Info.plist lint 통과
- 릴리스 빌드와 앱 패키징 통과, codesign --verify --strict 통과
- Swift Testing 9개 테스트 통과 (약 3.2초)
- 분할/병합, 프리셋 최소 크기, 비율 직렬화, 공간 포커스 이동 테스트
- 저장 roundtrip/손상 바이트 보존, 잘못된 참조·깊이·비율·버전·상대 경로·용량 거절, 실패한 쓰기의 기존 파일 보존
- 실제 PTY 명령·cwd·한국어 preedit/commit·분리된 클립보드·복사/붙여넣기·중복 열기 거절·exit/재열기
- 여러 셸 변수 격리, 분할/확대/숨긴 셸 작업 완료, 안전한 프리셋 축소/빈 칸 병합
- 새 셸 복원과 이전 변수 소멸, 이름/cwd/포커스/빈 칸 유지, 없는 폴더 fallback
- 120줄 출력 후 GHOSTTY_POINT_VIEWPORT로 상단/하단/페이지 이동과 복귀 검증

테스트 성공은 UI 시각 판독이나 마우스 휠 실기 검증을 대신하지 않는다. 실제 화면 관찰은 별도 `pr*-ui.md`에 있다.

PR #7 재검증: `./scripts/check.sh` 종료 0, 9개 테스트 약 3~4초 통과. 기본 grid의 최초 shell 1개/다음 셸 2·3·4개, 중복 시작 방지, 이전 단일 빈 저장 전환을 기존 실제 PTY flow에 추가했다. 초기 0-size split frame 경고도 수정 후 재실행에서 사라졌다. 원본 로그는 `.cache/check-default-grid.log`다.

PR #8 화면 모드: `./scripts/check.sh` 성공 (`.cache/check-appearance.log`): Swift strict format, bash syntax, plist, release build/adhoc codesign verification, 10 tests passed in 3.252s. 실제 PTY에서 repeated light/dark + hidden task completion + same surface/shell variable/layout/focus, new/restored surface appearance를 확인했다. 격리된 UserDefaults suite에서 light/dark 재로딩과 invalid 값 fallback을 확인했다. 실제 CUA 검증은 `pr8-appearance.md` E-A1–A6. 사용자 shell integration/외부 TUI의 색상은 자체 서식을 따르며 시스템 자동 추종은 이 두 수동 모드 범위 밖이다.

PR #10 toolbar icons: `.cache/check-toolbar-icons.log`의 check.sh 성공, 10 tests passed in 3.333s, build/signature/format/plist/shell syntax 통과. 실제 E-I1–6에서 네 preset 방향/선택, icon/menu 양방향 모드 상태, 셸 변수 보존, 640×441pt 최소 전체 창과 1100×752pt 복구, icon 선택 모드 재실행을 검증했다.

PR #11 pane reordering: `.cache/check-pane-motion.log`의 check.sh 성공, 11 tests passed in 3.463s, 경고·오류 없음. 전체 칸 preview/GPU component·same live surface/NSView·geometry·무효 ID/편집 밖 거절·교환/역교환·snapshot roundtrip 검증. 실제 앱에서는 비대칭 5칸 드래그/toolbar 취소/키보드 좌우 이동/동일 PID와 변수/두 모드 헤더를 확인했다. 미리보기 중간 프레임 자동 캡처는 지원되지 않아 사용자의 최신 빌드 모션 확인을 별도 근거로 기록했다. 동작 줄이기는 코드 분기 확인이며 시스템 설정을 바꾼 실기는 아니다.
