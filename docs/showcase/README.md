# README 프로그램 사진 구성

README의 세 이미지는 최신 Chop의 실제 창을 오리지널 배경 위에 구성한 것입니다.
실제 macOS 바탕화면 전체를 캡처했다고 표현하지 않습니다.

| 입력 / 출력 | 역할 |
| --- | --- |
| `captures/grid-dark.jpg` | 실제 다크 격자 창, 2200×1504px |
| `captures/grid-light.jpg` | 실제 라이트 격자 창, 2200×1504px |
| `captures/tabs-light.jpg` | 실제 라이트 탭 창, 2200×1504px |
| `wallpaper.png` | 생성한 오리지널 배경, 1672×941px |
| `index.html` | 동일한 창 배치·모서리·그림자를 적용하는 HTML/CSS |
| `../images/chop-macos-{dark,light,tabs}.jpg` | README용 최종 JPEG, 각1280×720px |

## 촬영

2026-10-15에 main `d11fdc0`의 release 앱을 CUA로 직접 촬영했습니다.
공개 소스의 Sources/Tests/Resources/scripts와 Package.swift/README.md/CONTRIBUTING.md를
임시 `/tmp/Chop`에 복사해 개인 파일 대신 보여주었습니다. 데모용 칸 이름은 Chop / Core tests /
Sources / 터미널 4입니다. 격자에서는 세 셸과 빈 칸 중앙 `+`가 보입니다.

- Chop: 실제 `ls -1G` 출력.
- Core tests: 실제 저장소에서 `swift test --filter fileSearch 2>&1 | tail -n 1`의 성공 요약.
- Sources: 격자에서 실제 `head -n 8 Package.swift`, 탭에서 `head -n 24 Package.swift` 출력.

원본 앱 픽셀을 재생성하거나 명령 출력을 만들어 넣지 않았습니다. 촬영 후 추가한 두 셸은
`exit`로 닫고 기존 셸·이름·다운로드 폴더·다크 격자·창 크기·빈 칸 포커스를 복원했습니다.

## 배경

사용자 제공 [PCMag 참고 이미지](https://i.pcmag.com/imagery/articles/04qJdxyFGsUg83r6HTjBAdX-20..v1740591348.png)의
컬러 배경·중앙 창·여백·그림자 관계만 참고했습니다. 해당 이미지의 배경이나 앱 콘텐츠를 복사하지 않았습니다.
2026-10-15에 내장 imagegen으로 새 배경을 생성했습니다. 창이나 앱 UI는 생성 대상에서 제외했습니다.
출력은1672×941px이며 도구에 전달한 요청 해상도와 실제 출력 해상도를 구별합니다.

사용한 프롬프트:

> Create an original premium macOS-style desktop wallpaper for a software README product screenshot presentation. Asset: wallpaper background ONLY, no windows and no UI. Landscape 16:9, ideally 3840 by 2160. Broad flowing layered ribbons and sweeping curved color fields, reminiscent of refined contemporary Mac desktop wallpapers: luminous warm apricot, amber and coral near the upper center, clean saturated azure and cobalt to the right, deep ultramarine and indigo in the lower left. The colors flow in broad smooth folds with restrained fine edge highlights and realistic soft lighting, not a busy texture. Clean editorial polish and rich but controlled color. Keep the center visually calm because a large real app window will be placed there later. Fill the entire canvas edge to edge. Absolutely no text, no logo, no watermark, no desktop menu bar, no dock, no icons, no app windows, no computer hardware, no border.

## 다시 구성하기

저장소 루트에서 정적 서버를 실행합니다.

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

`http://127.0.0.1:8765/docs/showcase/?view=dark`를 열고 `view=light`, `view=tabs`도 확인합니다.
배경1280×720px, 창920×628.95px, 좌우180px/상하45.52px, 모서리13px를 CSS에서 고정합니다.
창을 둘러싼 두 겹의 CSS 그림자는 `index.html`에 기록되어 있습니다.
페이지의 `(0,0,1280,720)` 영역을 브라우저 스크린샷으로 저장하면 됩니다.
최종 세 파일은 CUA Chrome의 해당 영역 캡처로 출력했습니다. 브라우저 viewport 설정은 바꾸지 않았습니다.
