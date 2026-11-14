# 터미널 빠른 종료 안정성

2026-11-15, Codex 셀프 리뷰. 외부 승인이나 화면 디자인 변경 검증이 아니다.

## L-1 재현

고정 Ghostty v1.2.3에서 별도 AppKit 검사 프로세스에 터미널 두 개를 열었다.
한 터미널은 OSC 제목을 계속 출력하고, 다른 터미널에는 제목 변경과 입력을 보냈다.
app 스레드를 250ms 멈춰 큐를 채운 직후 첫 터미널을 닫았다.
수정 전에는 45초 제한을 넘겨 검사 프로세스만 중단했다.
스택은 `Surface.deinit → pthread_join`과 IO 종료/읽기 스레드의 대기를 보였다.
기존 V-68/70의 원격 join 대기와 같은 종류의 멈춤을 이 고정 버전에서 재현한 것이다.
모든 과거 멈춤이 같은 원인이었다고 단정하지 않는다.

## L-2 수정과 검증

Ghostty PR #14444의 큐 drain 방식을 Zig 0.14.1과 고정 버전에 맞춰 적용했다.
app 스레드가 renderer/IO 종료를 기다릴 때 별도 drain이 큐의 역압력을 해소한다.
UI 콜백은 worker에서 실행하지 않고 다른 surface 메시지를 순서대로 보류한다.
닫는 surface를 참조하는 기존 보류 메시지도 제거하며 clipboard/pwd/config/write의 소유 메모리를 정리한다.
한 번의 처리량에 상한을 두어 다른 터미널의 지속 출력이 drain 종료를 막지 않게 했다.
보류 메시지는 head cursor로 소비해 큐가 많이 쌓여도 앞 항목 삭제를 반복하지 않는다.

- 첫 동일 재현: 수정 후 0.692초 통과, 남은 터미널 제목과 `ACK:ping` 유지.
- 최종 회귀 검사: 제목·DSR 응답·renderer 색상 출력 폭주 각각에서 종료 후 남은 터미널의 새 제목과 입력 응답 확인.
- 새 surface 준비를 기다리지 않고 16개 생성/종료를 3회 반복하고 남은 터미널 입력 응답 확인.
- 최종 `./scripts/check.sh`: 56개, 26.276초 통과. 새 격리 검사는 3.335초.
- Zig `queue_drain.zig` 검사: 가득 찬 큐의 producer 해제와 FIFO 보존 및 기존 queue 검사, 3개 통과. 로컬 Xcode 26용 SDK overlay를 사용했다.
- 테스트 child는 45초 제한을 두고 자신이 시작한 검사만 중단한다. 기존 사용자의 Chop 프로세스는 종료하지 않았다.

고정 커밋·MIT 고지·libghostty 공개 API는 유지했다. 변경 범위는 의존성 패치·빌드 캐시 키·회귀 검사·문서다.
`Sources/`, `Resources/`, `DESIGN.md`의 화면 구현·토큰은 변경하지 않았다. 이전 UI 관찰을 새 캡처로 표현하지 않는다.
thread 생성 자체가 OS 자원 부족으로 실패한 조건이나 모든 subprocess의 종료 동작까지 보장하는 검사는 아니다.

출처: [Ghostty #14245](https://github.com/ghostty-org/ghostty/issues/14245),
[PR #14444](https://github.com/ghostty-org/ghostty/pull/14444),
참고 커밋 `3cc748e676cf7fdd5e3d2ca48caf316415354069`.
