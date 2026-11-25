# Isle Defense (가제)

작은 섬을 침략자로부터 지키는 실시간 전술 로그라이크입니다. Bad North 같은 장르에서 영감을 받은 **오리지널** 프로젝트로, 원작의 이름, 아트, 레벨, 음악은 쓰지 않습니다.

- 엔진: **Godot 4.3 이상** (GDScript)
- 대상: Windows PC

## 바로 실행하기

1. [docs/SETUP.md](docs/SETUP.md)를 따라 Godot과 GitHub Desktop을 설치합니다.
2. Godot에서 이 폴더의 `project.godot`를 엽니다(Import).
3. 오른쪽 위 ▶ 버튼(또는 F5)을 누르면 섬이 나타납니다.

조작: 우클릭 드래그 또는 Q/E로 회전, 휠로 확대/축소, R로 새 섬 생성.

## 폴더 구조

| 폴더 | 내용 |
|---|---|
| `scenes/` | 씬 파일. `main.tscn`이 시작 씬 |
| `scripts/core/` | 공용 기능. `asset_library.gd`가 모델 불러오기 담당 |
| `scripts/island/` | 절차적 섬 생성 |
| `scripts/camera/` | 카메라 조작 |
| `scripts/ai/` | 게임 실행 중 AI 모델 호출 (`AI.ask(...)`) |
| `assets/models/` | 직접 만든 3D 모델(.glb)을 넣는 곳 |
| `docs/` | 설치, 그래픽 제작, AI 연동 안내서 |

## 개발 단계

1. ✅ 환경 준비: 프로젝트 뼈대, 섬 생성, 모델 교체 구조, AI 연동 계층
2. 전투 프로토타입: 분대 3종, 적 상륙 웨이브, 클릭 이동, 자동 전투
3. 로그라이크 루프: 캠페인 지도, 골드, 업그레이드, 퍼마데스
4. v1.0 마무리: 밸런스, Windows 빌드, 코드 구조 설명서

## 관련 문서

- [설치 안내](docs/SETUP.md)
- [그래픽 제작 안내 (ChatGPT → 3D → 게임)](docs/ASSET_PIPELINE.md)
- [AI 연동 안내 (개발용 + 게임 실행용)](docs/AI_INTEGRATION.md)
