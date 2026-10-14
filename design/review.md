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

현재 총괄은 실제 관찰한 v0.1 범위에서 aligned다. 스크롤백 키보드 경로도 실제 앱과 PTY 테스트로 검증했다. 최종 디자인 게이트는 `gate-report.json`과 `failure-events.jsonl`에 기록한다. 빌드 통과가 시각 검증을 대신하지 않으며, VoiceOver 전체 탐색과 macOS 14 실기기까지 검증했다고 주장하지 않는다.
