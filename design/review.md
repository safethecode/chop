# Chop UI 검토 기록

검토 기준은 `DESIGN.md`와 사용자의 중앙 `+`·1/2/4 분할 요청이다. cmux는 엔진 연결과 기능 참고 자료이며 외형 복제 자료가 아니다. 코드/테스트 검증과 실제 화면 관찰을 구분한다.

| ID | 관찰과 영향 | 상태 | 확인 |
|---|---|---|---|
| V-01 | 시스템 다크 appearance에서 흰 콘텐츠의 네이티브 보조 라벨/아이콘 대비가 부족했다. 칸에 Aqua appearance를 적용했다. | fixed-and-verified | PR #2 실제 앱에서 밝은 영역의 경로·닫기 확인 |
| V-02 | 헤더 닫기 버튼이 경로 바로 옆에 붙었다. 스택 fill 분배와 경로 hugging을 조정했다. | fixed-and-verified | PR #2 및 PR #3의 실제 화면에서 오른쪽 끝 정렬 |
| V-03 | 중앙 추가가 빈 칸에만 있었던 단계에서 다중 터미널 과제를 수행할 수 없었다. 분할 트리와 편집 모드 중앙 메뉴를 연결했다. | fixed-and-verified | [분할 관찰](evidence/pr3-ui.md), 실제 5칸 추가 |
| V-04 | 칸이 줄어들 때 실행 중 셸이 사라질 위험을 검토했다. 실행 중 개수보다 작은 프리셋을 비활성화하고 모델 변경도 거절한다. | fixed-and-verified | 실제 4개 실행 화면과 실제 PTY 통합 테스트 |
| V-05 | 경로·오류·프리셋 글꼴이 동일 기준을 소비하는지 검사했다. ChopStyle의 14pt medium을 참조한다. | fixed-and-verified | 코드 검사와 최종 빈 화면 렌더 |
| V-06 | 확대/닫기 묶음을 추가하며 오른쪽 정렬이 회귀했다. 중첩 스택을 평탄화했다. | fixed-and-verified | [칸 관리 관찰](evidence/pr4-ui.md), 새 빌드의 기본/최소 창 |
| V-07 | 확대 중 가려진 셸이 유지되는지 확인했다. visible API와 surface 재사용을 연결했다. | fixed-and-verified | 실제 지연 명령 완료와 변수 유지, 통합 테스트 |
| V-08 | 복원 시 초기 배치 알림을 사용자 리사이즈로 해석해 비율이 0.5에서 약 0.745로 바뀌었다. 실제 드래그 중에만 비율을 기록하도록 수정했다. | fixed-and-verified | 실제 저장 0.618744 비율과 680pt 경계 재실행 유지, 복원 통합 테스트 |
| V-09 | 동시 복원 시 일부 첫 줄 글리프가 가려졌다. Ghostty의 layer-hosting 순서를 소스에서 확인하고 조기 wantsLayer를 제거했다. 실제 body 크기/픽셀 갱신도 연결했다. | fixed-and-verified | 새 빌드에서 세 셸의 Last login/프롬프트가 모두 처음부터 렌더링됨 |
| V-10 | 저장 실패/손상 파일/사라진 경로의 복구가 필요했다. 보존·홈 대체·재시도·종료 취소를 연결했다. | fixed-and-verified | [복원 관찰](evidence/pr5-ui.md), 권한 실패 후 저장 재시도 |

| V-11 | 마우스 휠 자동화 도구가 noWindowsAvailable을 반환해 실행 확인을 할 수 없었다. 별도의 키보드/메뉴 스크롤 경로를 추가했다. | fixed-and-verified (키보드 경로 한정) | [최종 관찰](evidence/pr6-ui.md), 마우스 휠의 실기 검증은 남음 |

| V-12 / F-DEFAULT-01 | 사용자 교정: 처음부터 1번 셸과 2·3·4번 +가 있어야 한다. 이전 완료 기준에 기본 실행 상태가 빠졌다. 기본 grid·첫 셸 자동 실행과 단일 빈 저장 전환을 구현했다. | fixed-and-verified | [사용자 화면/재검증](evidence/pr7-default-grid.md), PROJECT-DEFAULT 규칙 추가 |

| V-13 | 사용자 요청으로 라이트·다크 선택을 추가했다. 이전 흰 콘텐츠 고정은 두 팔레트와 선택한 Aqua/Dark Aqua로 확장했다. 구조·치수를 유지하고 기존/숨긴/새 셸과 앱 재실행에 일관되게 적용한다. | accepted-difference (사용자 요청), 행동 검증 완료 | [화면 모드 관찰](evidence/pr8-appearance.md), 10개 테스트 및 두 모드 재실행 |

| V-14 | 사용자 요청으로 상단에 모드 아이콘을 추가하고 글자 레이아웃 선택기를 구조 아이콘으로 바꿨다. 기본 canvas·선택 강조·분할 동작은 유지했다. | accepted-difference (사용자 요청), 행동 검증 완료 | [상단 아이콘 관찰](evidence/pr10-toolbar-icons.md), 실제 4개 preset/두 모드/최소 창/재실행 |

| V-15 / F-MOVE-01 | 사용자 교정: 검은 손잡이 아이콘 대신 창 전체가 이동하는 모션이 필요하다. 첫 구현에서 이동 결과만 확인한 검토 누락을 기록한다. 전체 칸 chrome/실제 GPU 화면 미리보기와 짧은 배치 모션으로 수정했다. | fixed-and-verified (자동 테스트·실제 이동·사용자 모션 확인) | [칸 이동 관찰](evidence/pr11-pane-reordering.md) E-M1–7; 자동화의 중간 프레임 한계와 사용자 확인을 구분 |

| V-16 | 없는 SF Symbol을 강제 unwrap해 첫 통합 테스트가 중단됐다. 제공되는 네 방향 화살표와 optional 처리로 바꿨다. | fixed-and-verified | 11개 테스트 통과와 실제 헤더 손잡이 표시 |

| V-17 | 사용자 요청으로 헤더를 본문과 다른 중립 배경으로 구분한다. 라이트F3F4F6/다크292D35를 모든 칸의 같은 역할에 적용했다. | accepted-difference (사용자 요청), 실제 확인 완료 | [헤더 배경 관찰](evidence/pr12-header-background.md) E-H1–5; 실행/빈/편집/확대/숨긴 칸 모드 갱신 |

| V-18 | 사용자 요청으로 칸 전체의 파란 입력 포커스 경계를 제거했다. 실제 입력 커서·first responder·저장된 선택과 네이티브 컨트롤 포커스는 유지한다. | accepted-difference (사용자 요청), 실제 확인 완료 | [포커스 경계 관찰](evidence/pr13-no-focus-border.md) E-F1–5; 두 모드·클릭/키보드 입력·확대·드래그 교환 뒤 미표시 |

| V-19 / F-FILETREE-HIERARCHY | 사용자 교정: 파일 트리가 편집 툴바 영역을 차지했다. 공통 toolbar 아래 canvas와 트리를 나란히 두도록 수정했다. | fixed-and-verified | [파일 트리 관찰](evidence/pr14-file-tree.md) E-T1/E-T8–9,48pt 계층 회귀 검사 |

| V-20 / F-FILETREE-DIVIDER | 사용자 교정: 숨긴 패널의 검은 구분선이 남았다. 숨긴 divider 생략·배경 재그리기·bounds clip을 적용했다. 수정 중 툴바 overdraw도 재검증했다. | fixed-and-verified | E-T8–9 실제 개폐/모드/폭 변화에서 잔상 없음 |

| V-21 | 긴 경로가 두 줄로 잘렸다. 단일 행/가로 편집/중간 말줄임으로 수정했다. | fixed-and-verified | E-T3/E-T9 전체·최소 창 |

| V-22 | 재열기 시 패널이0폭으로 남았다. 개폐 때 명시적으로 프레임을 배치한다. | fixed-and-verified | E-T8–9, 재열기 최소 폭/우측 배치 회귀 검사 |

| V-23 | CodeRabbit: 자식 하나의 메타데이터 실패가 전체 폴더 오류로 전파됐다. 개별 이름/leaf fallback으로 수정했다. | fixed-and-verified | 오류 주입+실제 열거 회귀 검사, 전체16개 테스트와 최신 앱 일반 폴더 표시/펼치기 |

현재 총괄은 실제 관찰한 v0.1 범위에서 aligned다. 스크롤백 키보드 경로도 실제 앱과 PTY 테스트로 검증했다. 최종 디자인 게이트는 `gate-report.json`과 `failure-events.jsonl`에 기록한다. 빌드 통과가 시각 검증을 대신하지 않으며, VoiceOver 전체 탐색과 macOS 14 실기기까지 검증했다고 주장하지 않는다.

V-24 / F-PATH-FOCUS: 사용자 요청의 경로 입력 외곽선을 제거했다. 두 모드 클릭/선택/커서/실제 편집과16개 검사를 확인했다. fixed-and-verified. [관찰](evidence/path-focus-ring.md).

V-25 / F-HEADER-SEAM: 파일/터미널 header 사이 native 경계의 색 틈과 서로 다른 row 간격을 수정했다. 두 모드·개폐·실제 경계 drag·편집 상태를 확인해 fixed-and-verified. [관찰](evidence/header-seam.md).

V-26 / F-SHORTCUT-ALIGNMENT: 구현 중 glyph 고유 폭 때문에 바로가기 이름 시작선이 어긋났다.16pt aspect-fit icon box와8pt 뒤 이름을 갖는 native 버튼으로 수정해 실제 두 모드·최소 창·세 목적지 클릭·빈/긴 목록을 확인했다. fixed-and-verified. [관찰](evidence/location-icons.md).

V-27 / FILE-DROP-NATIVE:19개 검사와 native URL writer 시작은 확인했다. CUA의 OS drag가 놓기 이벤트를 기다려 실제 terminal 입력 종료를 확인하지 못했다. 후속 사용자 조작 뒤 같은 clean 앱의 터미널11에서 정확한 fixture 경로의 인용 입력과 셸 결과를 실제 AX로 확인했다. 핵심 native endpoint는 verified; 최초 자동화 한계와 물리 변형/자동 검사의 범위는 증거에 따로 유지한다. [범위](evidence/file-path-drag-drop.md).

V-28 / F-SHORTCUT-SECTION: 사용자 교정으로 세 바로가기를 중립 배경 묶음으로 분리했다. 실제 두 모드·기본/최소 창·세 목적지·빈/긴 목록을 확인해 fixed-and-verified. [관찰](evidence/shortcut-section.md).

V-29 / F-SINGLE-TABS: 사용자 교정에 따라 단일 보기 전환의1칸 제한을 없애고 모든 세션을 상단 탭으로 유지했다. 실제 네 셸/ENV/추가·닫기/긴 이름/두 모드·최소/재실행과20개 검사를 확인했다. fixed-and-verified. [관찰](evidence/single-view-tabs.md).

V-30 / F-TAB-RESIZE: 초기 창 축소 때 선택한 긴 탭이 가려졌다. viewport 변경 때 선택 탭을 드러내도록 수정하고681×432 두 모드/실제 Scroll Left/⌘W를 재검증했다. fixed-and-verified.

V-31 / F-COLUMNS-COUNT: 좌우2개/격자4개 전환 제한을 없애고 모든 pane을 보존했다. 실제4/5셸·두 모드/최소/가로 탐색/ENV·확대·복원과22개 검사를 확인했다. fixed-and-verified. [관찰](evidence/all-terminal-columns.md).

V-32 / F-CANVAS-SCROLL-AXIS: 가로 넘침 뒤 불필요한 세로 scroller를 실제 발견해 clip 크기에 맞추고 legacy 축 회귀를 추가했다. fixed-and-verified.

V-33 / F-CANVAS-DISPLAY-CYCLE: 첫 scroller 수정의 layout 내 재타일링으로 native 전환 중 충돌했다. main queue 다음 갱신에서 수렴시키도록 수정해 실제5회 왕복·5셸 모드·최종 확대/복귀와22개 검사를 확인했다. fixed-and-verified; 최초 crash를 기록에 보존한다.

V-34 / F-ROWS-COUNT: 마지막 상하2개 전환 제한과 empty 슬롯 삭제 경로를 없앴다. 실제4/5셸 모든 모드/ENV/두 모드·최소 창·세로 탐색/재실행 복원과22개 검사를 확인했다. fixed-and-verified. [관찰](evidence/all-terminal-rows.md).

V-35 / APP-ICON: 사용자 제공 열매 원본을 보존한 native continuous mask/transparent margin/ICNS를 적용했다. 실제 두 모드 정보 창/Finder 아이콘과22개 검사/번들 디코딩을 확인했다. accepted-difference (사용자 브랜드 지정), verified. [관찰](evidence/macos-app-icon.md).

V-36 / F-ICON-SHADOW-SCALE: 작은 출력에서 CGContext 축척만으로 그림자가 줄어든다고 가정해 모서리에 약한 alpha가 남았다. 모든 좌표/그림자를 pixel 비율로 계산해 최종10개 representation의 투명 모서리를 다시 확인했다. fixed-and-verified.

V-37 / README-PRESENTATION: 사용자 지정 Wratop README 구성을 Chop의 실제 기능에 맞춰 적용하고 실제 macOS 창 사진3장을 추가했다. 개인 Downloads 대신 공개 프로젝트 복사본을 촬영하고 원래 앱 상태를 복원했다. 최종 로컬 이미지·GitHub 로고/배지/격자/탭 사진·목차5개 클릭·링크/alt·22개 검사를 확인했다. aligned (문서/사진 범위); 앱 UI 코드는 변경하지 않았다. [관찰](evidence/readme-presentation.md).

V-38 / F-CANVAS-RESIZE-FLICKER (regression): 사용자 교정으로 resize 때 스크롤바가 나타났다 사라지는 현상을 재검토했다. 이전 비동기 수렴 검사는50ms 뒤만 검사해 native tile 직후17pt gutter/이전 문서 크기를 놓쳤다. 현재 viewport 기반 축 계산과 tile 전 문서 갱신으로 수정해 최초 FAIL→PASS,70회 동기 경계/두 스타일,실제 두 모드·최소/3회 크기 왕복·보기/확대·셸 유지와24개 검사를 확인했다. fixed-and-verified. 과거 V-33의 충돌 기록과 당시 검사 범위를 보존하며 이번에는 layout 안 수동 재타일링을 사용하지 않는다. [관찰](evidence/stable-canvas-scrollbars.md).

V-39 / F-TAB-EMPTY-CENTER: 사용자 crop과 실제 실행 앱에서 빈 탭의 `+`가 이전 격자 좌표에 남는 것을 확인했다. 전용 탭 컨테이너가 선택 본문을 동기 배치하도록 수정해5/7/8·파일 트리 개폐·축소/재확대·두 모드·격자 왕복에서 중앙을 확인했다. 비표시 window 검사는 수정 전에도 통과했다는 한계를 남기며 전체25개 검사와 실제 창 판독을 함께 근거로 삼는다. fixed-and-verified. [관찰](evidence/center-empty-tab-content.md).

V-40 / F-RENAME-ICON-GAP: 헤더 이름 버튼의 남는 폭 때문에 연필이 멀어진 최초 구현을 content hugging으로 수정했다. 최종 두 모드·최소 격자·짧고 긴 이름·실제 연필 클릭에서 확인했다. fixed-and-verified. [관찰](evidence/terminal-name-controls.md).

V-41 / F-RENAME-TAB-REVEAL: 같은 viewport에서 마지막 탭 이름이 길어지면 선택 탭이 가려지는 회귀를 내용 폭 변화 감지로 수정했다. 최초469>316.5 FAIL→PASS,최종 실제683pt 창에서 이름 저장 직후240pt 선택 버튼 전체 표시,이름/셸 유지·취소·재실행 복원과26개 검사를 확인했다. fixed-and-verified. [관찰](evidence/terminal-name-controls.md).

V-42 / F-RENAME-TAB-REVEAL (regression): PR27 첫 CI에서464>457.5로 선택 탭 끝이 가려져 이전 viewport/내용 폭 감지만으로 충분하지 않은 조건을 발견했다. 스택 배치 후 실제 trailing edge까지 문서 폭에 포함하도록 수정했다. 두 모드×두 스타일×세 길이12조건,전체26개 검사·최종 실제1배율683pt 창64자 변경과 두 모드 판독으로 다시 확인했다. fixed-and-verified (로컬/실제 앱),CI 결과는 PR에 별도 기록한다. [관찰](evidence/terminal-name-controls.md).

V-43 / FILE-BROWSER-ROW-SURFACE: 후속 사용자 요청에 따라108pt 세로 바로가기 묶음을28pt native 버튼 행으로 대체하고 목록/빈/오류를 기존 보조 배경으로 구분했다. 두 모드·기본/최소 패널280pt·세 목적지 이동·빈/오류 복구와27개 검사/최소 폭 hitTest를 확인했다. 이번 CUA 포인터 파일 드래그는 도구 입력 제약으로 새 성공을 확인하지 못했으며 이전 drag 코드/기록과 구분했다. accepted-difference (사용자 가로 배치 지정),verified (변경 범위). [관찰](evidence/file-browser-row-surface.md).

V-44 / F-TREE-SURFACE-CONTRAST: 버튼 기본색을 목록 전체로 확대한 첫 시도에 사용자가 더 옅은 톤을 요청했다. 최신 요구에 따라 light F8F8F8/dark24262C로 대비를 낮추고 두 모드의 실제 release 화면·27개 검사로 확인했다. fixed-and-verified (사용자 후속 교정 범위). [관찰](evidence/file-tree-soft-surface.md).
