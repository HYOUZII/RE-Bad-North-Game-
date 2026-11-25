# AI 연동 안내

AI는 두 군데서 씁니다. 둘은 서로 독립적이라 하나만 써도 됩니다.

## A. 개발할 때: Claude가 PC의 Godot을 직접 다루기

PC에 설치한 Claude 데스크톱 앱에 **Godot MCP 서버**를 연결하면 Claude가 프로젝트를 실행하고, 오류 로그를 읽고, 씬을 만들 수 있습니다.

1. [SETUP.md](SETUP.md)의 4번(Claude 데스크톱 + Node.js)을 설치합니다.
2. 커뮤니티 Godot MCP 서버(예: GitHub의 `Coding-Solo/godot-mcp`)의 README 안내대로 Claude 데스크톱 설정 파일에 등록합니다. Godot 실행 파일 경로(예: `C:\Godot\Godot_v4.x-stable_win64.exe`)를 넣는 칸이 있습니다.
3. Claude 데스크톱을 다시 시작하고 "Godot 프로젝트 실행해서 오류 알려줘"라고 시켜 봅니다.

> 커뮤니티 도구라 설정 방법이 바뀔 수 있습니다. 막히면 그 화면을 캡처해서 알려 주세요.

## B. 게임 실행 중: 게임이 AI 모델에 묻고 답 받기

코드에서는 이렇게 씁니다.

```gdscript
var id := AI.ask("새 섬의 이름과 짧은 전설을 지어 줘", "너는 북유럽풍 판타지 게임의 작가야")
AI.response_received.connect(func(req_id, text): print(text))
AI.request_failed.connect(func(req_id, err): print("AI 실패: ", err))
```

AI가 꺼져 있거나 실패해도 게임은 멈추지 않습니다. AI를 쓰는 기능은 항상 "AI 없을 때 기본값"을 갖도록 만듭니다.

### 설정 파일

게임을 한 번 실행하면 아래 위치에 `ai_config.cfg`가 생깁니다(저장소에는 올라가지 않습니다).

```
%APPDATA%\Godot\app_userdata\Isle Defense\ai_config.cfg
```

**Claude API 사용 (유료, 품질 높음)**
```ini
[ai]
provider="claude"
api_key="sk-ant-..."   ; https://console.anthropic.com 에서 발급
model="claude-opus-5-5"
max_tokens=1024
```
비용을 줄이고 싶으면 `model`을 `claude-haiku-5-5`로 바꾸세요.

**Ollama 사용 (무료, PC에서 실행)**
```ini
[ai]
provider="ollama"
model="llama3.2"
endpoint="http://localhost:11434"
```
Ollama 설치 후 명령 프롬프트에서 `ollama pull llama3.2`를 한 번 실행해 두세요.

**끄기**: `provider="none"`

> API 키는 절대 GitHub나 채팅에 올리지 마세요. 이 설정 파일에만 넣으세요.
