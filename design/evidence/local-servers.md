# 터미널별 로컬 서버 — 2026-11-04

셀프 리뷰이며 외부 사람의 승인으로 표시하지 않는다. 사용자 요청은 해당 터미널에서 연 서버 주소의 헤더 표시와 브라우저 열기다. 전체를 새 디자인으로 재현하는 요청이 아니다. 기존 2×2/중앙 추가/공통 툴바·오른쪽 파일 트리·옅은 단일 경계를 보존한다.

## 구현/제한

고정 Ghostty v1.2.3 커밋은 유지한다. IO가 atomic으로 publish한 root PID를 읽는 C API만 확장했고 원래 라이선스/출처를 보존했다. background utility task가1초마다 Chop의 직접 자식 root와 후손의 native TCP LISTEN socket만 조회한다. 프로세스 환경·전체 시스템 포트·서버 네트워크 요청을 읽거나 실행하지 않는다. 같은 surface/PID인지 재확인한 뒤 UI에 반영하고 종료/restore 때 목록을 비운다. root/child의 parent와 가능한 start time을 재확인하며 취소·4096개 프로세스·FD 버퍼 상한을 유지한다.

루프백/전체 주소 bind가 대상이다. TCP로부터 HTTP 여부를 확정하지 않는다. 기본 HTTP, 현재 화면에 같은 local host/port의 HTTPS 출력이 있으면 scheme만 적용한다. 출력에서 외부 destination·credentials·custom scheme은 채택하지 않는다. Docker/외부 daemon으로 분리된 프로세스와 원격 서버는 자동 추적 범위 밖이다. 실제 TLS 연결/인증서와 모든 개발 프레임워크를 검증했다고 주장하지 않는다.

header는 기존40pt/14pt medium/12pt inset·gap·28pt native button과 secondaryForeground를 사용한다. arrow.up.right는 SF Symbols14pt medium이며 외부 브라우저 열기를 뜻한다.480pt 미만에서 경로를 이름 툴팁으로 넘기고340pt 미만(탭 바420pt 미만)은 :port +N으로 압축한다. 모두 chosen 값이다. 자체 색·경계·hover 모션·별도 패널을 추가하지 않았다.

## 실제 AppKit/브라우저 관찰

macOS26.5.2/Apple Silicon, 별도 bundle ID·세션 경로의 /tmp/ChopLocalServerVerification.app에서 직접 실행했다. 사용 중인 원래 Chop은 종료하지 않았다. 아래 캡처는 CUA에서 직접 본 이미지와 AX의 기록이며 PNG 파일을 내보냈다는 뜻이 아니다.

- E-L1: 최종 1100×752pt 창/2200×1504px 라이트 격자에서1번 localhost:54792,2번 localhost:54797 +1을 직접 봤다. 화면 로그의 실제 ephemeral 포트와 각각 일치하며 이름/연필은 붙어 있고 주소/화살표/확대/닫기는 겹치지 않는다. canvas는 두 열·두 행과 중앙 plus를 유지한다. 원본 crop의 동등한 두 열과 현재 canvas의 두 열 폭 비율은 눈금/경계의 시각 추정으로 모두 약1이며 허용0.02 안이다. 이미지px를 pt로 환산한 수치가 아니다.
- E-L2: native 창 모서리를 드래그한1784×890px 축소 창(AX pane 폭280pt) 라이트·다크에서 :54792 및 :54797 +1로 줄고 이름과 필수 버튼은 남는 것을 확인했다. 원래 파일 트리의 native divider와48pt 추가 영역도 보존됐다.
- E-L3: 다크 탭 보기에서 선택한1번의 localhost:54792를 보고2번으로 전환하면 두 포트, 빈4번에서는 주소가 사라지는 것을 AX/이미지로 확인했다. 라이트 탭에서도2번의 복수 표시와 arrow 아이콘을 확인했다. 셸 로그와 PID는 보기 전환 때문에 바뀌지 않는다.
- E-L4: 주소 클릭으로 Chrome의 http://localhost:52330/ 에서 Chop local server test / Opened from this terminal. 실제 페이지를 확인했다.2번 주소 목록에는52335와52336이 따로 표시됐고 두 번째를 선택해 Chrome의 http://localhost:52336/ 과 같은 테스트 페이지/HTTP200 로그를 확인했다. 이 행동은 최종 arrow 아이콘을 넣기 전 동일 openServer/openItem 코드에서 실행했으며 최종 코드의 클릭 연결은 native button 검사로 재검증했다. 검증 탭은 닫았다.
- E-L5: 실제2번 Ctrl+C 뒤 두 주소가 사라지고 경로가 돌아오며1번 주소는 남았다.1번 종료도 확인했다. 최종 라이트 탭에서2번 종료 후 선택한 주소 컨트롤이 제거되는 것도 재확인했다. 재실행은 새 셸을 열고 이전 주소를 표시하지 않았다.

## 발견/수정/자동 검사

최초 proc_listchildpids의 반환을 byte로 해석해 후손을 놓쳤다. Apple libproc.c가 PID count를 반환하는 것을 확인하고 수정했다. 이후 macOS login(1)의 BSD 조회가 EPERM인 실제 조건을 발견했다. Chop의 직접 자식 목록으로 root 소유를 검증하고 privileged login은 자식 순회를 계속하며, 읽을 수 있는 프로세스의 start time/parent는 계속 검증한다. 별도 권한을 요청하지 않는다. 초기 실패를 무시하거나 단순 화면 문자열 매칭으로 대체하지 않았다.

최종 ./scripts/check.sh: strict format·shell syntax·plist·release/서명/아이콘과 전체44개15.152초 통과. 실제 TCP bind→LISTEN→close, 외부 root 제외, 자식 Python listener, URL destination 제한과 HTTPS hint, 클릭 전 자동 열기 없음/중지 후 클릭 방지, 실제 두 셸 PID/중첩 launcher/2개 대1개 포트 격리/Tab 전환/Ctrl+C/칸 닫기, 두 모드 최소 칸의 frame/hit overlap을 검사한다. 물리 VoiceOver 전체/고대비/모든 셸·TLS·외부 daemon은 실행 완료로 표시하지 않는다. 입력 inset와 나머지 변경 없는 자산의 이전 근거는 이번 실행으로 포장하지 않는다.

변경 범위는 aligned. 원본 기본 grid와 현재 canvas의 관계만 재대조했으며 서버 버튼에 외부 시각 레퍼런스가 있었다고 주장하지 않는다. 현재 source snapshot과 이 기록을 v2 reference comparison에 연결한다.

## 셀프 리뷰 후 조회 비용 보완

HTTPS 힌트를 위해 accessibilityValue(SCREEN 전체 기록)를 매번 복사하던 경로를 ACTIVE 출력 화면의 최대32KiB로 제한했다. 확인한 HTTPS scheme은 현재 listener가 유지되는 동안 보존하고 새 명시 HTTP 출력은 다시 적용한다. listener가 없어지면 scheme 캐시도 비운다. source snapshot은 E-L1 첫 핵심 화면 당시의 보존본이며 덮어쓰지 않았다. 변경된 부분은 텍스트 조회/프로토콜 힌트이므로 HTTP 주소/헤더 geometry/메뉴와 E-L1–5 화면은 바뀌지 않는다. 명시 HTTP override/HTTPS 선호 유지 검사와 최종 전체44개14.196초 check.sh를 재실행했다. 원격 결과는 PR에 기록한다.
