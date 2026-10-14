# Chop 앱 아이콘

사용자가 제공한 `A1-realistic-v2.png`를 원본으로 사용합니다. 원본은1254×1254이며 `AppIcon-source.png`로 바이트 그대로 보관합니다. SHA-256: `5dd63b3e30a7d9f8a91aaa18d610c95a54902eedf96dbaddf897b11b07204e93`. 캐릭터·표정·줄기·보라색/노란색·원래 구도를 유지하고 크기 조절/플랫폼 외곽 처리만 적용합니다.

[Apple 앱 아이콘 가이드](https://developer.apple.com/design/human-interface-guidelines/app-icons/)의 정사각형/둥근 사각형과1024px 작업 기준을 참고합니다. macOS14부터 사용할 수 있는 ICNS 형식으로 번들에 넣습니다. 아래 수치는 제품 선택값이며 Apple 공식 템플릿에서 실측한 값이라고 주장하지 않습니다.

- 1024×1024 투명 canvas 안의824×824 tile, 사방100px 여백
- SwiftUI RoundedRectangle의 continuous curve, cornerRadius185px
- 그림자 y=-8px/blur16px/black alpha0.25; 모든 출력 크기에 비례 조절
- 16/32/128/256/512pt의1×·2×, 총10개 PNG representation을 ICNS로 패키징

원본을 바꾼 뒤 저장소 루트에서 `swift scripts/generate-app-icon.swift`를 실행하면 `Resources/AppIcon.png`(1024 preview)와 `Resources/AppIcon.icns`를 다시 만듭니다. `Info.plist`의 CFBundleIconFile을 빌드/검증 스크립트가 실제 번들 리소스로 연결하고 iconutil 디코딩을 확인합니다.

이미지 생성 검토는 built-in imagegen의 precise-object-edit 모드로 다음 요청을 사용했습니다: “Keep the original purple fruit mascot, face, spiral stem, yellow background and original composition unchanged. Only fit the same artwork into a macOS continuous rounded square with a small transparent outer margin; preserve the yellow background inside; no text, border, recoloring or redraw; output a1024×1024 transparent PNG.” 외곽 잔여 픽셀이 있어 이 후보는 채택하지 않았습니다. 최종 제작은 제공된 원본을 SwiftUI/AppKit의 연속 곡선으로 직접 마스킹하는 재생성 스크립트이며 모델로 다시 그린 이미지를 사용하지 않습니다.
