# 제공된 로고의 macOS 앱 아이콘 적용

2026-10-15 KST, macOS26.5.2, 구현자 셀프 리뷰. 사용자는 보라색 열매 원본과 둥근 녹색 앱 아이콘 crop를 제공하고 같은 macOS 형식의 둥근 앱 아이콘을 요청했다. 원본은 실제 파일로 직접 확인했고 repo의 AppIcon-source.png는 cmp/SHA로 제공 파일과 바이트가 같음을 확인했다. 녹색 crop에서는 둥근 외곽/투명 주변/독립된 앱 타일 관계만 채택한다. 그 앱의 이름·전체 화면·실제 배율·픽셀 반경/동작은 추론하지 않는다. 임시 crop 파일은 이후 사라졌지만 대화에서 직접 본 원본 관찰과 사용자 요구를 근거로 사용한다.

[Apple HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons/)의 square/rounded rectangle과1024px 작업 기준을 확인했다.14+ 배포 범위를 유지해 ICNS로 내보내고 CFBundleIconFile과 실제 번들 경로를 연결한다. Source1254는 resize/continuous curve mask/shadow만 적용하며 표정·줄기·색·원래 crop은 유지한다. tile824/margin100/radius185/그림자8·16·alpha0.25는 chosen 값이고 Apple 공식 픽셀 실측값이 아니다. UI palette/functional SF 아이콘을 이 색으로 바꾸지 않는다.

Builtin imagegen의 precise-object-edit 후보는 외곽에 잔여 픽셀이 있어 폐기했다. 최종은 제공 원본을 직접 마스킹하는 SwiftUI/AppKit 스크립트다. 초기에 CGContext의 축척으로 작은16/32 representation의 그림자 크기까지 줄어든다고 가정해 corner alpha가0.012/0.008 남았다. 좌표/반경/그림자 자체를 출력 pixel 비율로 조정한 뒤 최종 ICNS를 다시 디코딩해10개 representation 모두 hasAlpha/모서리 alpha0/중앙 alpha>0.99를 확인했다.1024 출력과64 preview를 실제 이미지로 봤고 작은 크기에서도 보라색 얼굴·줄기/노란 배경이 식별됐다.

실제 clean Chop.app의 ‘Chop에 관하여’를 열어 AppKit이 로고를 앱 아이콘으로 읽는 것을 확인했다. 다크와 라이트 두 정보 창 모두 둥근 노란 타일/보라색 캐릭터가 표시되고 흰/어두운 바깥 배경에 모서리 잔여 픽셀이 없었다. 별도 runtime icon override를 추가하지 않았다. Finder에서 새 검증용 창을 열어 build/release의 실제 Chop.app 아이콘도 같은 로고로 표시되는 것을 확인했다. 검증용 Finder 창과 정보 창은 닫고 Chop의 기존4개/격자/다크/Downloads/1100×752 주 창을 다시 표시했다. 새 crash report는 없었다.

./scripts/check.sh PASS:22개 테스트5.065초 및 strict format/build/서명. 새 generator도 strict format에 포함하고 실제 Info.plist가 가리키는 bundled ICNS를 iconutil로 디코딩하는 검사를 추가했다. UI 코드/셸 동작은 바꾸지 않았으며 같은 구현을 반복하는 새 단위 테스트는 만들지 않았다. Core/file/PTY/scroll 회귀는 기존22개를 실행했다. Dock을 별도 캡처했다고 하지 않으며 실제 확인은 정보 창/Finder와 패키지 리소스다. 전체 VoiceOver/macOS14 실기기/모든 OS 아이콘 변형은 기존 미검증 범위다.
