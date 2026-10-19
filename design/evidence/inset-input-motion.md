# 입력창 inset 경계와 상태 전환 — 2026-10-20

셀프 리뷰이며 외부 사람의 승인으로 표시하지 않는다. 사용자 요청: 입력 border를 blur inset으로 바꾸고 hover/focus도 부드럽게 전환한다. 기존 파란 외곽선 생략 규칙은 유지하되 입력창에 중립색 상태 표시를 허용하는 최신 계약이다. 터미널 전체 포커스 경계나 세로 추가 영역 경계는 변경하지 않는다.

## 구현과 수치

`Sources/Chop/InsetInput.swift`의 native NSTextField/NSSearchField subclass와 cell은 기본 편집/선택/IME/검색·취소/AX 역할을 재사용한다. 배경과 clip된 안쪽 그림자를 그리며 overlay는 hitTest에서 nil을 반환한다. 경계 이미지는 크기·배율·appearance가 바뀔 때만 재생성한다. 기존28pt 높이/14pt medium, 경로와 이름 반경6pt·검색14pt. 이름 변경 accessory만24→28pt로 맞춘다. light 검정/dark 흰색, 경계 안쪽0.5pt/blur2.5pt, opacity0.10→hover0.17→focus0.25. 0.18초 easeInEaseOut으로 opacity만 바꾸며 빠른 전환은 presentation opacity에서 이어간다. 모두 chosen 값이며 이미지 실측이 아니다. Reduce Motion을 매 상태 변경에서 읽고 활성 시 진행 중 모션도 제거한다.

## 실제 앱 관찰

macOS26.5.2/Apple Silicon, CUA에서 직접 본 실제 AppKit 창이다. 원래 사용자 작업 중인 Chop을 종료하지 않았다. 별도 bundle ID와 세션 경로의 검증 앱을 사용했다. 초기 검증 앱에 사용자가 검색을 실행한 뒤 후속 확인은 `/tmp/ChopInputVerification.app`으로 분리했다.

- E-I1: 1100×752pt 창(2× 캡처2200×1504px) 라이트 기본 경로·검색창. 안쪽의 은은한 경계, 기존 검색 아이콘·자리표시자,48pt 세로 영역과 단일 파일 트리 경계를 직접 확인했다.
- E-I2: 경로 클릭·전체 선택·프로젝트 경로 붙여넣기·Enter로 폴더 이동하고 검색 초기화/트리 복귀를 AX로 확인했다. FileTree 검색3건, native 취소 버튼으로 일반 트리 복귀, 한글 붙여넣기와0건 표시, 다시 FileTree/Tab으로 목록 초점 이동을 실행했다.
- E-I3: ⌘⇧R로 이름 변경 창을 열어 전체 선택/붙여넣기·Return 저장을 실행했다. 300×28pt 입력창의 라이트 inset과 caret, 변경된 헤더 이름을 직접 확인했다.
- E-I4: 별도 후속 앱에서 라이트 검색 포커스/한글 caret, 다크 기본 경로·빈 검색과 FileTree 포커스 상태를 직접 비교했다. 글자/아이콘의 위치와 치수는 전환 전후 유지되고 포커스는 중립색으로 강해졌다. 실제 시간의 매 프레임을 캡처한 주장은 아니다.

포인터만 옮기는 API가 없고 좌표 drag는 noWindowsAvailable로 실행되지 않았다. 따라서 실제 포인터 hover 단독 캡처는 확보했다고 표시하지 않는다. hover 이벤트부터 CAAnimation까지는 아래 native 이벤트 검사로 실행했다. 전체 VoiceOver, macOS14 실기기, 물리적인 동작 줄이기 설정 변경은 이번 확인 범위 밖이다.

## 자동 검사와 수정

`InsetInputTests.swift`의 두 검사는 native mouseEntered 이벤트가 hover 상태/opacity animation을 만드는지, focus가 더 강한 상태로 전환되는지, Reduce Motion 주입 시 모션 제거/최종 상태 적용, hover/focus가 프레임·렌더 이미지를 바꾸거나 hitTest를 가로채지 않는지, 리사이즈가 경계 이미지를 갱신하는지 확인한다. native field editor에서 한글 marked text를 만든 상태로 경계 전환 후 같은 편집기/조합을 유지하고 확정·포커스 handoff/비활성 창·검색 아이콘 rect도 확인한다. 테스트 runner가 전면 앱이 아니라 keyWindow 기대가 실패했던 첫 fixture는 제어 가능한 test window로 바꿔 비활성 조건까지 검증한다. 제품의 focus 로직은 이 fixture 수정으로 바뀌지 않았다.

`./scripts/check.sh`: strict Swift format, shell syntax, plist, release 빌드·서명·아이콘과 전체40개 테스트 통과. 최종 native 이벤트 검사 수정 뒤 해당 두 검사도 재실행했다. 기존 최소280pt 파일 패널 hitTest·배치 검사는 두 모드에서 통과했다. 실제 hover 단독 포인터, 물리 Reduce Motion과 자동 상태 검사를 혼동하지 않는다.

결과: 변경된 입력창의 실제 두 모드 외형과 편집/이동 행동, native 이벤트 기반 hover와 애니메이션 계약은 aligned. 다른 앱 기능과 이전 사진/자산의 증거는 새 실행으로 포장하지 않는다.

## CI 후속 확인과 테스트 격리

완료된 원시 로그를 다시 확인하니 최초 실행도 debug 빌드를 끝낸 뒤 테스트 프로세스에서 응답이 없었다. live UI의 마지막 컴파일 줄만으로 compiler 자체가 멈췄다고 확정할 수 없다. 첫 실행은 동일 커밋 재검사를 위해 취소했고, 두 번째 실행도 빌드 완료 뒤 테스트 출력이 없었다. 입력창 변경 전 main 실행39340752253도 같은 단계에서30분 제한으로 종료됐다. 이 기록만으로 정확한 deadlock 위치를 단정하지 않는다.

AppKit 창/field editor와 터미널 엔진의 공유 프로세스 상태를 다른 async UI 테스트가 동시에 건드리는 경합을 줄이기 위해 check.sh에 `swift test --no-parallel`을 명시했다. [Swift Testing 공식 문서](https://docs.swift.org/latest/documentation/testing/parallelizationtrait/)의 전체 병렬화 비활성 옵션이며, 기본 도움말 표시만으로 Swift Testing의 기본 실행을 순차라고 가정하지 않는다. 삭제·skip·기대값 완화 없이 같은40개 검사가 순차로 실행되는 것을 로그에서 확인했다. 최종 `./scripts/check.sh` 전체40개11.835초 및 release/서명/format/아이콘 검사 통과. 정확한 CI 멈춤 원인과 최종 원격 재실행 결과는 PR에서 별도로 기록한다. 제품 UI 소스는 이 후속 조정에서 바뀌지 않아 E-I1–4의 화면 관찰 범위는 그대로다.

## 같은 상태의 반복 갱신 방지

셀프 리뷰에서 window.didUpdate 때 opacity가 같아도 CATransaction을 매번 commit하던 코드를 발견해, 같은 target opacity이면 레이어 갱신을 생략했다. 같은 상태에서도 Reduce Motion이 활성화되면 진행 중 모션 제거는 유지하며 이를 기존 검사에 추가했다. 이 불필요한 commit이 CI 멈춤의 원인이라고 단정하지 않는다. 최종 check.sh는 전체40개12.321초 통과했다. E-I5: 새 코드로 별도 앱을 다시 빌드·실행해 다크 검색 편집/caret, 라이트 경로 편집/caret, Tab 이동과 동일한 inset 외형을 직접 확인하고 검증 앱만 종료했다. 이전 E-I2의 검색3건/취소/이름 저장 실행과 이 후속 상태 전환 확인을 구분한다.

순차 실행 CI에서도 즉시 완료를 확인하지 못해 workflow에60초마다 실행 중인 swiftpm-testing/ChopPackageTests의2초 sample(앞160줄)을 기록하는 진단을 추가했다. 기존 check.sh를 그대로 실행하고 그 wait 종료 코드를 반환한다. monitor는 EXIT에서 종료하며 검사/기대값/30분 timeout을 줄이거나 성공으로 덮어쓰지 않는다. YAML parse 및 shell 구문 검사를 통과했다. 최종 원격 판정은 PR에 기록한다.
