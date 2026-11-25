# 프로젝트 규칙 (Claude용)

- Godot 4.3+ / GDScript. 씬은 최소화하고 노드는 코드로 생성한다(텍스트 diff 리뷰가 쉽도록).
- 그래픽은 반드시 `Assets.get_model(id)`로 만든다. 직접 메시 생성 금지(타일 제외). 새 id는 `asset_library.gd`의 PLACEHOLDERS와 `docs/ASSET_PIPELINE.md` 표에 함께 추가.
- AI 호출은 `AI.ask()`만 사용. AI가 꺼져도 게임이 동작하도록 항상 기본값 경로를 둔다.
- 원작(Bad North)의 이름, 아트, 레벨, 음악을 복제하지 않는다. 장르 메커니즘만 참고.
- 사용자는 엔진 초보다. 주석과 문서는 한국어로, 쉬운 말로 쓴다.
- 커밋 전 `gdparse`로 문법 검사 (pip install gdtoolkit==4.5.0).
- 커밋 전 자동 플레이 테스트: `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn -- --runs=5` → `SMOKE_TEST_DONE`, SCRIPT ERROR 0건. 단순 지휘 AI 기준 승률 30~50%가 현재 목표 난이도.
- 전투 이벤트(타격, 사망, 추락, 집 피해)는 `battle.gd`의 signal로 내보낸다. 손맛 효과는 여기에 연결.
