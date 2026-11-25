extends Node
## 게임 실행 중 AI 모델과 대화하는 창구 (자동 로드 이름: AI)
##
## 사용법:
##   var id := AI.ask("섬 이름 하나 지어줘", "너는 판타지 게임 작가야")
##   AI.response_received.connect(func(req_id, text): print(text))
##
## 설정은 user://ai_config.cfg 에서 읽습니다 (저장소에 올라가지 않는 개인 폴더).
## 파일이 없으면 AI 기능은 꺼진 상태(provider = none)로 동작하고, 게임은 정상 실행됩니다.
## 설정 방법은 docs/AI_INTEGRATION.md 참고.

signal response_received(request_id: int, text: String)
signal request_failed(request_id: int, error: String)

const CONFIG_PATH := "user://ai_config.cfg"
const CLAUDE_URL := "https://api.anthropic.com/v1/messages"
const CLAUDE_API_VERSION := "2026-10-21"

var provider: String = "none"  # "none" | "claude" | "ollama"
var api_key: String = ""
var model: String = ""
var endpoint: String = "http://localhost:11434"  # Ollama 기본 주소
var max_tokens: int = 1024

var _next_id: int = 1


func _ready() -> void:
	load_config()


func is_enabled() -> bool:
	return provider != "none"


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_write_example_config()
		return
	provider = str(cfg.get_value("ai", "provider", "none"))
	api_key = str(cfg.get_value("ai", "api_key", ""))
	endpoint = str(cfg.get_value("ai", "endpoint", endpoint))
	max_tokens = int(cfg.get_value("ai", "max_tokens", max_tokens))
	var default_model := "claude-opus-5-5" if provider == "claude" else "llama3.2"
	model = str(cfg.get_value("ai", "model", default_model))
	if provider == "claude" and api_key == "":
		push_warning("AI: provider가 claude인데 api_key가 비어 있어 AI를 끕니다.")
		provider = "none"


## 질문을 보내고 요청 번호를 바로 돌려줍니다. 답은 response_received 신호로 옵니다.
func ask(prompt: String, system_prompt: String = "") -> int:
	var id := _next_id
	_next_id += 1
	if not is_enabled():
		request_failed.emit.call_deferred(id, "AI disabled")
		return id

	var url := ""
	var headers := PackedStringArray(["content-type: application/json"])
	var body := {}
	match provider:
		"claude":
			url = CLAUDE_URL
			headers.append("x-api-key: " + api_key)
			headers.append("anthropic-version: " + CLAUDE_API_VERSION)
			# 안전 필터로 거절되면 서버가 다른 모델로 자동 재시도
			headers.append("anthropic-beta: server-side-fallback-2026-07-01")
			body = {
				"model": model,
				"max_tokens": max_tokens,
				"fallbacks": "default",
				"messages": [{"role": "user", "content": prompt}],
			}
			if system_prompt != "":
				body["system"] = system_prompt
		"ollama":
			url = endpoint.trim_suffix("/") + "/api/chat"
			var msgs: Array = []
			if system_prompt != "":
				msgs.append({"role": "system", "content": system_prompt})
			msgs.append({"role": "user", "content": prompt})
			body = {"model": model, "stream": false, "messages": msgs}
		_:
			request_failed.emit.call_deferred(id, "Unknown provider: " + provider)
			return id

	var http := HTTPRequest.new()
	http.timeout = 120.0
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http, id))
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		request_failed.emit.call_deferred(id, "HTTP request error %d" % err)
	return id


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray, http: HTTPRequest, id: int) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(id, "Network error %d" % result)
		return
	var text := raw.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if code < 200 or code >= 300 or typeof(data) != TYPE_DICTIONARY:
		request_failed.emit(id, "HTTP %d: %s" % [code, text.left(300)])
		return
	match provider:
		"claude":
			if data.get("stop_reason", "") == "refusal":
				request_failed.emit(id, "refusal")
				return
			var out := ""
			for block in data.get("content", []):
				if typeof(block) == TYPE_DICTIONARY and block.get("type", "") == "text":
					out += str(block.get("text", ""))
			response_received.emit(id, out)
		"ollama":
			var msg = data.get("message", {})
			response_received.emit(id, str(msg.get("content", "")) if typeof(msg) == TYPE_DICTIONARY else "")


func _write_example_config() -> void:
	# 처음 실행할 때 예시 설정 파일을 만들어 둡니다 (AI는 꺼진 상태).
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "provider", "none")
	cfg.set_value("ai", "api_key", "")
	cfg.set_value("ai", "model", "")
	cfg.set_value("ai", "endpoint", endpoint)
	cfg.set_value("ai", "max_tokens", max_tokens)
	cfg.save(CONFIG_PATH)
