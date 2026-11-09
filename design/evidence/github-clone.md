# GitHub 프로젝트 클론 검증

## 요구와 구현 전 계약

사용자 요청: 기존 터미널 추가 세로 영역의 하단에서 GitHub 저장소를 클론하고 새 프로젝트의 터미널까지 연다. 기존48pt 영역·32pt 버튼·옅은 단일 경계·파일 트리 개폐와 중앙 plus는 유지한다. 새32pt native circular 다운로드(SF arrow.down.to.line) 버튼은 하단12pt, 좌우8pt이다. 별도 GitHub 브랜드 로고는 만들지 않는다.

기존 실행 Chop의 CUA 화면을 변경 없이 직접 봤다. 현재 다크 격자에서 세로 영역은 두 배율 이미지상 약96px이고 중앙 plus가 있으며 오른쪽 트리 native divider와 겹친 선은 없다. 코드의48pt를 image-px 실측 환산으로 주장하지 않는다. 기본 grid 원본은 기존 local-server-reference의 decomposition/interpretation/handoff를 재사용한다. 새 클론 시트는 외부 복제 레퍼런스가 아닌 사용자 요구와 기존 native 창/InsetTextField 패턴의 확장이다.

D-C1: 저장소 주소→저장 위치→폴더 이름→클론하고 열기. 새 프로젝트는 별도 창에서 열어 기존 셸과 분리한다. URL/SSH/owner/repo 입력은 canonical github.com 주소로 제한한다. 이름은 자동 제안하되 직접 바꾼 이름은 보존한다. 신규 창은 실제 클론 완료 뒤에만 생성한다.
D-C2: native520×408pt sheet, 바깥24pt·그룹16pt·내부8pt, 라벨/입력/행동은 기존14pt medium, 목적 제목은20pt semibold(chosen),28pt 입력·버튼(existing-token). 기존 blur inset/0.18초 hover·focus를 재사용한다. 진행은 실제 퍼센트를 알지 못하므로 숫자 대신 spinner와 상태를 제공한다. 비공개 저장소는 기존 Git credential helper/SSH agent를 사용하고 새 인증 저장·설정 변경은 하지 않는다.
D-C3: 입력→진행→실패(입력 유지)→수정/재시도→완료, 취소→process group 종료/이번 staging 정리→기존 창 복귀. 같은 이름의 기존 항목과 다운로드 중 생긴 항목은 대체하지 않는다. clone완료 전 앱 종료도 취소/정리가 끝난 뒤 응답한다. 의존성 설치나 저장소 명령은 자동 실행하지 않는다.
Do: 작은 고정 진입점/기존 native 표면/명확한 클론 및 새 창 결과. Avoid: 큰 rail, 중복 경계, 새 계정 로그인 장벽, 가짜 진행률, 기존 경로 덮어쓰기, 실패 시 입력 초기화. Unknown: 실제 VoiceOver 전체·물리 고대비·모든 private credential provider/SSH host 설정.

## 첫 화면 직접 판독

E-C0: 별도 bundle ID/세션 경로의 /tmp/ChopGitHubCloneVerification.app에서 하단 버튼을 클릭해520×408pt 클론 시트를 직접 열었다.1040×816px CUA 이미지에서 목적 제목, 세 입력 묶음, 기존 inset, disabled 제출/취소와 새 창 결과 안내가 보인다. 첫 source는 github-clone-reference/first-sheet-source.swift.txt에 보존했다. 실제 캡처를 내보낸 PNG 파일이 아니라 CUA에서 직접 본 이미지의 기록이다. 최종 판독과 첫 관찰을 구별한다. 원래 사용 중인 Chop은 종료하거나 조작하지 않았다.

## 초기 자동 검사 발견

URL parser가 /tmp/repo를 owner/repo로 받아들이는 결함을 실제 거부 검사에서 발견했다. shorthand의 선행 slash를 거부하도록 수정한다. 다른 host·credential 포함 URL·option 문자열은 거부한다. 로컬 실제 git clone, 기존 디렉터리·dangling symlink 보존, 실패 후 staging 정리와 실제 대기 중 git 전송 취소/소켓 닫힘 검사는 최초 실행에서 통과했다. 최종 결과는 후속 검증에 기록한다.

## 최종 실제 앱 확인

E-C1: native 폴더 선택기에서 /tmp/chop-github-clone-ui-fixture를 선택했다. octocat/Hello-World 주소 붙여넣기→Hello-World 자동 제안→already-exists로 변경→충돌 안내/입력 유지→한글 '새 프로젝트 테스트'로 변경→Return을 연속 실행했다. 실패 후 폴더 이름에 초점이 돌아왔고 같은 폼에서 재시도했다. 라이트 오류 화면1040×816px에서14pt 라벨·입력·오류·실행/취소와20pt 목적 제목을 직접 판독했다. 첫 화면 뒤 그룹의 vertical hugging과 footer spacer를 명시해 그룹 사이16pt를 안정화했다.

E-C2: 실제 GitHub public 저장소 클론이 완료되자 한글 이름의 별도 창이 자동으로 열렸다. 첫 셸에서 직접 printf/pwd/git remote get-url origin을 실행해 CHOP_CLONE_CWD_OK, 실제 /tmp/chop-github-clone-ui-fixture/새 프로젝트 테스트 경로, https://github.com/octocat/Hello-World.git를 확인했다. 파일 트리도 같은 루트의 README를 표시했다. 기존 검증 창도 유지됐다. light2200×1504px 격자의 canvas 두 열/두 행 비율은 시각 추정으로 약1(±0.01)이며 원본 default-grid-user.png의 약1과 허용0.02 안이다. 기본1실행/3중앙 plus·작은 header·본문 우선 관계를 보존한다. 본문 focus outline 제거와 헤더 배경 등은 이전 사용자 후속 요구다.

E-C3: 다크 동일 크기와 native 모서리 축소1784×890px(AX 최소 pane280pt), 탭 전환/트리 숨김을 직접 확인했다. 하단 clone과 중앙 plus는 각각32pt이며48pt rail을 늘리거나 경계를 겹치지 않는다. 최소 창에서도 클론 시트 전체의 입력과 마지막 행동에 접근했다. 다크 시트1040×816px에서 목적 제목/세 그룹/기존 inset/disabled 제출을 판독했다. 대비 수치나 물리 고대비 전체 검증을 수행했다고 주장하지 않는다.

E-C4: torvalds/linux 전송을 시작해 disabled 저장소·이름·위치/제출, native spinner와 취소 버튼을 확인한 뒤 Escape로 취소했다. 같은 터미널과 기존 경로/셸 내용으로 돌아왔고 새 linux 창은 열리지 않았다. 파일 확인에서 linux 폴더 및 .chop-clone-* staging이 없고 기존 already-exists/완료된 한글 프로젝트는 남았다. 이 저장소는 취소 상태 검증용이며 끝까지 내려받거나 실행하지 않았다.

E-C5: 최초 클론 sheet가 NSWindow의 기본 preventsApplicationTerminationWhenModal 때문에 Cmd+Q를 막는 조건을 실제 관찰했다. 해당 sheet에서만 false로 설정하고 다시 실제 앱에서 전송→Cmd+Q→종료 안내→취소(전송 유지)→Cmd+Q→종료를 실행했다. 최종 안내에는 터미널 작업과 클론 종료를 함께 표시했다. 프로세스 종료와 staging/linux 미생성, 완료된 프로젝트/기존 항목 보존을 파일/프로세스 메타데이터로 확인했다. 이 보완과 상태 문구를 중립적인 '프로젝트를 클론하고 있어요…'로 바꾼 최종 코드에서 종료 경로를 재실행했다. UI geometry는 바뀌지 않았다.

## 자동 검사와 셀프 리뷰 범위

집중6개 검사1.010초 통과. 전체 ./scripts/check.sh는49개15.018초, strict format/shell syntax/plist/release·서명·아이콘 검사 통과. 이 전체 실행 뒤의 변경은 상태 문구·README/DESIGN뿐이며 최종 release를 다시 빌드했다. 네트워크 없는 실제 로컬 Git clone→publish/.git·파일 확인, 기존 디렉터리·dangling symlink 보존, 실패 시 정리, 대기 중 실제 git socket 전송 취소→EOF, canonical GitHub URL/SSH/shorthand 허용 및 다른 host/credential/local path/option 거부, failure→입력 유지→retry→한 번만 완료, 진행 중 중복 제출/취소, 두 모드×네 보기×패널 개폐 최소 hit geometry를 검사했다. 원격 CI 결과는 PR에 별도 기록한다.

셀프 리뷰: URL을 셸 문자열로 실행하지 않으며 고정 /usr/bin/git의 인자로 전달한다. 임시 경로는 선택 parent에 이번 작업이 직접 mkdir한 UUID 폴더만 정리한다. 완료 publish는 renamex_np(RENAME_EXCL)로 같은 파일시스템에서 원자적으로 수행해 다운로드 중 생긴 대상도 대체하지 않는다. posix_spawn의 별도 process group을 취소하고 waitid(WNOWAIT) 뒤 reap해 PID 재사용에 잘못 신호를 보내지 않는다. 취소와 publish는 같은 lock에서 직렬화한다. 새 창 열기는 기존 WorkspaceWindowManager.open을 재사용한다. UI와 실제 Git 동작 검증은 독립적인 외부 사람 승인으로 표시하지 않는다.

Copy C1(진입): GitHub 프로젝트 클론… → 시트 열기. C2(제출): 클론하고 열기 → 다운로드 완료 뒤 새 창. C3(상태): 진행/취소 정리/기존 항목 충돌/접근 실패에 맞춰 같은 위치에서 갱신하며 가짜 완료 시간·원인 단정·입력 초기화는 없다. C4(취소): idle은 닫기, 진행 중은 정리 후 복귀. ux-copy 8원칙으로 즉시 행동·새 창 결과·충돌 시 다음 행동·입력 선택권을 검토했다. 개발자용 바이트 제한/진행률 추정은 UI에 넣지 않았다.

미검증: 모든 private credential provider/SSH agent·처음 host 확인/실제 VoiceOver 전체·물리 글자200%/고대비·네트워크 단절 종류별 원인. 별도 GitHub OAuth/계정 목록·원격 저장소 생성·자동 명령 실행은 제공 범위 밖이다. 이전 file drop/자산 등 변경 없는 기능의 과거 증거를 이번 실제 실행으로 다시 주장하지 않는다.
