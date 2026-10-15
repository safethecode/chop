# README macOS 스타일 사진 재구성

- F-ID: F-README-MACOS-PRESENTATION. 사용자는 이전 사진이 대충 만들어졌다고 지적하고 PCMag macOS 화면을 제시했다. V-37의 당시 검증 범위와 원본 사진은 보존하며, 앱 창만 자른 구도가 최신 요구를 만족하지 못했다는 후속 교정을 기록한다.
- 기준: [사용자 지정 PCMag 이미지](https://i.pcmag.com/imagery/articles/04qJdxyFGsUg83r6HTjBAdX-20..v1740591348.png)를 직접 열어 확인했다. 로컬 `.cache/readme-macos/reference-pcmag.png`는1280×720px다. 컬러 바탕 위 x약174/y약49의 약916×621px Safari 창, 네이티브 chrome·둥근 모서리·얕은 그림자와 사방 여백 관계를 관찰했다. 참고 이미지의 배경과 Safari 콘텐츠는 배포 자산으로 복사하지 않았다.
- 구성 계약: 출력1280×720px, 창920×628.95px, x180/y45.52, 모서리13px, 두 겹 CSS 그림자. 같은 중심축·크기·배경을 다크 격자/라이트 격자/라이트 탭에 적용했다. 이미지 px/CSS px와 실제 앱의 macOS pt를 구별한다. 정확한 레퍼런스 픽셀 복제라고 주장하지 않는다.
- 이미지 출처: `docs/showcase/captures/`는 최신 main d11fdc0 release의 CUA 실제 캡처2200×1504px 세 장이다. `wallpaper.png`만 내장 imagegen으로 생성한 오리지널1672×941px 배경이다. 앱 내부 픽셀은 모델로 생성하거나 리터칭하지 않았다. `index.html`의 img와 CSS가 배경/클리핑/그림자를 구성하며 최종 JPEG는 CUA Chrome에서1280×720 영역을 저장했다. 생성 프롬프트와 재현 방법은 `docs/showcase/README.md`에 있다.
- 실제 내용: 공개 파일만 `/tmp/Chop`으로 복사해 ls/head로 출력했다. Core tests에는 실제 fileSearch 테스트3개 통과 요약을 tail로 표시했다. 긴 함수 이름이 여러 줄로 감겨 사진이 산만해진 첫 시도를 실제 명령의 간결한 요약으로 바꿨다. 격자는 실행 셸3개와 빈 칸 중앙+1개, 탭은 네 이름·선택된 소스·오른쪽 파일 트리를 보여준다. 앱의 수평 바로가기·검색창·연한 목록면도 최신 모습이다.
- 로컬 시각 판독: 최종 세 이미지를 각1280×720 브라우저 캡처로 열어 읽었다. 창은 중앙에 있고 traffic lights와 제목 막대가 살아 있으며 가장자리가 잘리거나 배경이 창 안으로 침범하지 않는다. 사진에 별도 배너/기기 목업/가짜 Dock을 추가하지 않았다. 터미널·파일명은 식별 가능하며 본문을 가리는 포인터가 없다. 작은 GitHub 본문에서는 상세 글자가 작아질 수 있어 원본 라이트/다크 링크와 충분한1280px 이미지를 유지했다.
- GitHub 실물: 공개 docs/macos-readme-showcase 브랜치 README에서 다크 picture가 선택되어 실제 로드1280×720임을 DOM과 화면으로 확인했다. 격자 전체·배경·설명/라이트·다크 링크가 표시되고 레이아웃 목차 클릭으로 탭 사진까지 이동했다. 탭 사진도 실제 로드1280×720을 확인했다. 라이트는 로컬 완성 이미지를 직접 판독했으며 GitHub 계정/OS 테마를 바꿔 테스트하지 않았다. 실물 캡처는 로컬 `.cache/readme-macos/github-readme-hero.jpg`, `github-readme-tabs.jpg`다.
- 사용자 작업 복원: 기존 셸은 종료하지 않고 cwd/PROMPT를 복원했다. 데모용 두 셸만 exit로 닫고 이름6/5/7/8, 실행 셸1개/빈 칸3개, 다운로드 폴더, 다크 격자, 기존1100×752pt 창, 마지막 빈 칸 포커스를 실제 AX로 확인했다.
- 검증: `./scripts/check.sh` 전체 통과,32개 테스트 통과. 문서/사진 변경으로 앱 소스·UI 토큰·동작은 수정하지 않았다. 기존 기능의 물리 드래그/macOS14/VoiceOver 미검증과 CHOP-RUI-12 예외는 그대로 유지한다. PR의 셀프 리뷰와 CodeRabbit 실행 여부·CI 결과는 별도로 확인한다.
