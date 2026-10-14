# Chop

원하는 칸에 터미널을 추가하고 나눠 쓰는 macOS 네이티브 앱입니다.
Swift와 AppKit을 사용하며, 터미널 엔진은 [libghostty](https://github.com/ghostty-org/ghostty)를 연결할 예정입니다.
[cmux](https://github.com/manaflow-ai/cmux)의 작업 공간과 알림 기능을 참고하되, Chop은 중앙 `+`와 레이아웃 중심의 조작 방식을 사용합니다.

현재는 **보일러플레이트 단계**입니다. 기본 창과 메뉴, 빌드·실행·검증 환경만 포함하며 터미널 기능은 아직 없습니다.

## 개발 환경

- macOS 14 이상
- Xcode 16 이상 / Swift 6 이상
- Xcode Command Line Tools (`xcode-select -p`로 선택된 개발 도구 확인)

외부 Swift 패키지 의존성은 아직 없습니다. Xcode에서 `Package.swift`를 열어 소스를 편집할 수 있습니다.

## 실행

```sh
./scripts/run.sh
```

디버그 빌드 후 `build/debug/Chop.app`을 만들어 실행합니다.
이미 실행 중이면 기존 앱을 활성화하므로, 변경한 코드를 실행하려면 먼저 앱을 종료합니다.

릴리스 빌드와 실행:

```sh
./scripts/run.sh release
```

앱 번들만 만들려면:

```sh
./scripts/build-app.sh release
```

`build/release/Chop.app`이 생성됩니다. 개발용 임시 서명을 사용하며, 외부 배포용 Developer ID 서명과 공증은 포함하지 않습니다.

## 검증

```sh
./scripts/check.sh
```

Swift 포맷, 셸 스크립트 문법, 앱 메타데이터, 릴리스 빌드와 앱 서명을 검증합니다.
GitHub Actions도 같은 명령을 실행합니다. 현재 보일러플레이트에는 자동화된 기능 테스트가 없으며,
앱 실행과 창·메뉴 동작은 수동 확인합니다.

Swift 포맷 수정:

```sh
xcrun swift-format format --in-place --recursive Package.swift Sources
```

## 구조

```text
Package.swift          Swift Package Manager 설정
Sources/Chop/          앱 진입점, 앱 수명 주기, 기본 창
Resources/Info.plist   macOS 앱 메타데이터
scripts/              빌드, 실행, 검증
.github/              CI와 PR 템플릿
```

## 구현 순서

각 단계는 별도 브랜치와 PR로 진행합니다. 범위가 커지면 더 작은 PR로 나눕니다.

1. 보일러플레이트: 앱 실행, 빌드 스크립트, CI
2. 단일 터미널: libghostty 연결, 빈 칸 중앙 `+`로 셸 열기
3. 분할: 레이아웃 모델, 프리셋, 자유 분할, 크기 조절
4. 칸 관리: 포커스 이동, 확대·복귀, 닫기와 빈 칸 합치기
5. 복원: 레이아웃, 이름, 작업 경로 저장과 복원
6. 작업 상태: 알림, Git 브랜치, CLI 연동

기여와 PR 절차는 [CONTRIBUTING.md](CONTRIBUTING.md)를 따릅니다.
