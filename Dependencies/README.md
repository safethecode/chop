# libghostty

- 원본: https://github.com/ghostty-org/ghostty
- 버전: v1.2.3, 커밋 `6d2dd585a5d87fa745d48188dd096ca6e63014d0`
- Zig: 0.14.1, 공식 배포본의 SHA-256 검증
- 준비 명령: `./scripts/prepare-ghostty.sh` (앱 빌드 스크립트에서 자동 호출)

Chop은 macOS용 libghostty embedder API와 Metal 렌더러를 사용합니다.
이 API는 안정적인 범용 API가 아니므로 버전을 고정하고 `TerminalEngine` / `TerminalView`에서만 사용합니다.
외부용 libghostty-vt는 렌더링과 프로세스 관리를 직접 구현해야 하므로 현재 버전에는 사용하지 않습니다.

`ghostty-config.patch`는 Chop의 번들 설정 파일을 읽는 함수 하나와 아카이브 도구 어댑터 연결을 추가합니다.
사용자의 Ghostty 설정이나 프로세스 인자를 수정하지 않고 설정을 읽습니다.
최신 Apple libtool이 Zig 아카이브의 정렬되지 않은 객체를 누락하는 문제는
`scripts/ghostty-libtool.sh`에서 객체를 꺼내 재조립해 해결합니다. 완성한 라이브러리의 공개 함수도 검사합니다.
입력 연결은 업스트림 `macos/Sources/Ghostty/SurfaceView_AppKit.swift`와
`NSEvent+Extension.swift`의 공개 MIT 소스를 참고했습니다.
Ghostty 라이선스는 `Resources/Ghostty-LICENSE`에 보존하며, 빌드된 의존성의 고지도 앱의 `Resources/licenses`에 복사합니다.

소스·도구·컴파일 캐시는 `.cache/`, 완성한 네이티브 아키텍처 XCFramework와 리소스는 `Dependencies/`의 무시된 경로에 생성됩니다.
원본 소스와 Zig 다운로드는 체크섬을 검증합니다. 준비 스크립트·패치·호스트 아키텍처·Xcode 버전이 달라지면 다시 빌드합니다.

Xcode 26의 일부 arm64 SDK에서는 Zig 0.14 링크가 실패합니다.
이 경우 설치된 Command Line Tools의 호환 libSystem stub과 현재 SDK 헤더를 묶은 로컬 오버레이를 사용합니다.
시스템 SDK 파일이나 `xcode-select` 설정을 변경하지 않습니다.
직접 준비한 SDK 오버레이가 있으면 `CHOP_GHOSTTY_SDKROOT`로 지정할 수 있습니다.
Metal 도구가 빠져 있으면 Xcode의 공식 `MetalToolchain` 구성 요소를 내려받습니다.
Git 전송을 사용하는 `zg`와 `zigimg`는 같은 커밋의 아카이브를 미리 받아 업스트림에 고정된 Zig 콘텐츠 해시를 검증합니다.
Codeberg의 Git capability 조회가 실패하는 CI 환경에서도 패키지 버전을 바꾸지 않고 빌드하기 위한 처리입니다.
