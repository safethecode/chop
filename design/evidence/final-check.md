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
