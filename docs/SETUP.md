# 설치 안내 (Windows 기준)

필수 3개, 선택 3개입니다. 순서대로 진행하세요.

## 필수

### 1. Godot 4 (게임 엔진)
1. https://godotengine.org/download/windows/ 에서 **Godot Engine** (표준판, .NET 아님) 최신 4.x 를 받습니다.
2. 압축을 풀면 `Godot_v4.x-stable_win64.exe`가 나옵니다. 설치 과정 없이 이 파일을 실행하면 됩니다.
3. 찾기 쉽게 `C:\Godot\` 같은 폴더에 두고 바탕화면 바로가기를 만들어 두세요.

### 2. GitHub Desktop (코드 받기)
1. https://desktop.github.com/ 에서 설치 후 GitHub 계정(HYOUZII)으로 로그인합니다.
2. `File > Clone repository`에서 `RE-Bad-North-Game-`를 골라 내려받습니다. 예: `C:\Games\RE-Bad-North-Game-`
3. 제가 코드를 올리면 GitHub Desktop의 **Fetch origin → Pull origin**을 누르면 최신 코드로 바뀝니다.

### 3. 프로젝트 열기
1. Godot 실행 → 프로젝트 매니저에서 **Import** → 내려받은 폴더의 `project.godot` 선택.
2. 처음 열 때 몇 초간 자동 준비(임포트)를 합니다.
3. **F5** 또는 오른쪽 위 ▶ 버튼으로 실행합니다.

## 선택 (필요할 때 설치)

### 4. Claude 데스크톱 앱 + Node.js (개발 중 AI 연동)
Claude가 PC의 Godot을 직접 실행하고 로그를 읽게 하는 용도입니다. 자세한 건 [AI_INTEGRATION.md](AI_INTEGRATION.md).
- Claude 데스크톱: https://claude.ai/download
- Node.js LTS: https://nodejs.org/

### 5. Blender (3D 모델 다듬기)
- https://www.blender.org/download/ — AI로 만든 모델의 크기, 방향을 고칠 때 씁니다. [ASSET_PIPELINE.md](ASSET_PIPELINE.md) 참고.

### 6. Ollama (PC에서 도는 무료 AI 모델, 게임 실행 중 사용)
- https://ollama.com/download — API 비용 없이 게임 안에서 AI를 쓰고 싶을 때.

## 문제가 생기면
- "프로젝트를 열 수 없음": Godot 버전이 4.3 이상인지 확인하세요.
- 화면이 하늘색만 보임: 마우스 휠을 아래로 돌려 축소해 보세요.
- 그 외 오류: Godot 아래쪽 **Output / Debugger** 탭의 빨간 글씨를 복사해서 알려 주세요.
