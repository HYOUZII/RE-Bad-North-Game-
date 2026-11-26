extends Node3D
## 뼈대(리깅)와 동작(애니메이션)이 들어 있는 3D 병사 모델을 움직이는 담당
## (Assets.get_model이 병사용 3D 캐릭터 파일이 있을 때 만들어 줌)
##
## 하는 일
## - 이동 속도에 맞춰 서 있기 / 걷기 / 뛰기를 부드럽게 섞어서(블렌딩) 바꿈
##   발이 미끄러져 보이지 않게 실제 속도에 맞춰 재생 속도도 바꿈
## - 공격·맞음·막기·죽음 같은 "한 번 동작"을 재생하고, 끝나면 이동 동작으로 돌아감
## - 공격은 칼이 닿는 순간(타격 시점)이 실제 피해가 들어가는 순간과 맞도록 재생 속도를 맞춤
##
## 시간은 전투 관리자(battle.gd)가 animate()로 넘겨 줍니다. 그래서 일시정지·슬로모션 때 동작도 같이 멈추거나 느려집니다.
## 아무도 animate()를 안 부르면(본 섬 화면, 쓰러진 시체) 스스로 시간을 흘려 서 있기 동작을 재생합니다.

const BLEND := 0.18           # 동작이 바뀔 때 섞는 시간(초)
const IDLE_BELOW := 0.08      # 이 속도(m/s)보다 느리면 서 있기
const RUN_ABOVE := 0.75       # 이 속도보다 빠르면 뛰기 (그 사이는 걷기)
## 문턱 근처에서 동작이 깜빡이지 않게: 서 있다가 걷기 시작하려면 조금 더 빨라야 하고,
## 뛰다가 걷기로 바꾸려면 조금 더 느려져야 함 (밀려서 한두 걸음 옮길 때 다리가 떨리지 않게)
const START_WALK := 0.15
const STOP_RUN := 0.6
const MAX_PLAY_SPEED := 3.2   # 걷기·뛰기 재생 속도 상한(발 미끄러짐을 줄이되 너무 빨리 발을 구르지 않게)

## 알려진 동작 파일의 타격 시점(초, 원래 속도 기준). 표에 없으면 동작 길이의 40%로 봄.
## tests에서 칼 든 손이 가장 빨리 움직이는 순간을 재서 적었습니다(KayKit 캐릭터 기준).
const IMPACT := {
	"1H_Melee_Attack_Chop": 0.58,
	"1H_Melee_Attack_Slice_Diagonal": 0.42,
	"1H_Melee_Attack_Slice_Horizontal": 0.26,
	"1H_Melee_Attack_Stab": 0.40,
	"2H_Melee_Attack_Stab": 0.40,
	"2H_Melee_Attack_Chop": 0.72,
	"2H_Melee_Attack_Slice": 0.40,
	"2H_Ranged_Shoot": 0.16,
	"1H_Ranged_Shoot": 0.12,
}
## 걷기·뛰기 동작을 재생 속도 1로 틀었을 때 모델 원래 크기에서 몸이 나아가는 속도(m/s).
## 실제 크기(scale)를 곱해서 게임 속 속도로 바꿉니다. 표에 없으면 걷기 0.75, 뛰기 1.5.
const STRIDE := {"Walking_A": 0.76, "Walking_B": 0.73, "Walking_C": 0.49, "Running_A": 1.5, "Running_B": 1.13}

## 동작 이름표에 없을 때(직접 만든 Mixamo 모델 등) 애니메이션 이름에서 찾을 단어
const KEYWORDS := {
	"idle": ["idle", "stand", "breath"],
	"walk": ["walk"],
	"run": ["run", "sprint", "jog"],
	"attack": ["attack", "slash", "swing", "stab", "chop", "punch", "melee"],
	"aim": ["aim", "draw"],
	"shoot": ["shoot", "fire", "release"],
	"hit": ["hit", "impact", "react", "damage"],
	"block": ["block"],
	"death": ["death", "die", "dying", "dead"],
	"fall": ["fall", "jump_idle", "jump"],
	"cheer": ["cheer", "victory", "celebrat"],
}
const LOOPING := ["idle", "walk", "run", "fall", "aim"]

var _ap: AnimationPlayer
var _anims: Dictionary = {}     # 동작 종류 -> [애니메이션 이름...]
var _gear_leader: Array = []    # 분대장일 때만 보이는 장비 노드
var _model_scale := 1.0         # 원래 모델 → 게임 크기 배율
var _loco := ""                 # 지금 재생 중인 이동 동작 종류(idle/walk/run/fall)
var _oneshot_left := 0.0        # 한 번 동작이 끝날 때까지 남은 시간(게임 시간)
var _hold := false              # 죽음: 마지막 자세로 멈춰 있음
var _driven := false            # 병사(unit.gd)가 시간을 넘겨 주는 중인가
var _speed := 0.0               # 부드럽게 다듬은 이동 속도
var _base_scale := Vector3.ONE
var _clock: Node = null         # 시체일 때 시간 빠르기를 알려 주는 전투 관리자(일시정지 따라가기)
var _sink: Tween


## model: 불러온 캐릭터(크기·방향 맞춤 노드 포함), anims: 동작 종류 -> 애니메이션 이름 목록
func setup(model: Node3D, anims: Dictionary, model_scale: float, leader_gear: Array) -> void:
	add_child(model)
	_model_scale = model_scale
	_gear_leader = leader_gear
	for g in _gear_leader:
		g.visible = false
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	_ap = found[0] as AnimationPlayer
	# 시간은 직접 넘겨 줌(일시정지·슬로모션과 맞추려고)
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var have := _ap.get_animation_list()
	for kind in KEYWORDS.keys():
		var list: Array = []
		for n in anims.get(kind, []):
			if _ap.has_animation(str(n)):
				list.append(str(n))
		if list.is_empty():
			list = _guess(kind, have)
		if not list.is_empty():
			_anims[kind] = list
	for kind in LOOPING:
		for n in _anims.get(kind, []):
			_ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_set_loco("idle", 1.0, 0.0)
	_ap.seek(randf() * 0.8, true)  # 모두 같은 박자로 숨 쉬지 않게


func has_action(kind: String) -> bool:
	return _anims.has(kind)


## 병사가 매 단계 부름. speed = 스스로 걸어간 속도(m/s, 밀려난 건 빼고)
func animate(dt: float, speed: float) -> void:
	_driven = true
	_step(dt, speed)


func _process(delta: float) -> void:
	if _driven:
		return
	var k := 1.0
	if _clock != null and is_instance_valid(_clock) and _clock.has_method("time_scale"):
		k = _clock.time_scale()
	if _sink != null:
		_sink.set_speed_scale(k)
	_step(delta * k, 0.0)


## 병사가 더는 시간을 넘겨 주지 않음(전투 끝) → 스스로 시간을 흘림
func release() -> void:
	_driven = false


func _step(dt: float, speed: float) -> void:
	if _ap == null:
		return
	_speed = lerp(_speed, speed, min(1.0, dt * 10.0))
	if _hold:
		_ap.advance(dt)
		return
	if _oneshot_left > 0.0:
		_oneshot_left -= dt
		if _oneshot_left <= 0.0:
			_loco = ""  # 이동 동작으로 돌아감
	if _oneshot_left <= 0.0 and _loco != "fall":
		_update_loco()
	_ap.advance(dt)


func _update_loco() -> void:
	var kind := "idle"
	var moving_above := START_WALK if _loco == "idle" else IDLE_BELOW
	var run_above := STOP_RUN if _loco == "run" else RUN_ABOVE
	if _speed > run_above and _anims.has("run"):
		kind = "run"
	elif _speed > moving_above and _anims.has("walk"):
		kind = "walk"
	elif _speed > moving_above and _anims.has("run"):
		kind = "run"
	var rate := 1.0
	if kind != "idle":
		var n: String = _anims[kind][0]
		var native: float = STRIDE.get(n, 1.5 if kind == "run" else 0.75) * _model_scale
		rate = clamp(_speed / max(native, 0.01), 0.6, MAX_PLAY_SPEED)
	if kind != _loco:
		_set_loco(kind, rate, BLEND)
	else:
		_ap.speed_scale = rate


func _set_loco(kind: String, rate: float, blend: float) -> void:
	_loco = kind
	if not _anims.has(kind):
		return
	_ap.play(_anims[kind][0], blend)
	_ap.speed_scale = rate


## 짧은 동작 재생. hit_at = 타격 순간까지 남은 시간(초). 0이면 원래 속도로 처음부터.
## 반환: 실제로 재생했으면 true
func _oneshot(kind: String, hit_at: float = 0.0, max_rate: float = 2.2) -> bool:
	if _ap == null or _hold or not _anims.has(kind):
		return false
	var list: Array = _anims[kind]
	var n: String = list[randi() % list.size()]
	var anim := _ap.get_animation(n)
	var rate := 1.0
	var start := 0.0
	if hit_at > 0.0:
		var impact: float = IMPACT.get(n, anim.length * 0.4)
		# 타격 시점까지 hit_at초 안에 도달하도록 빨리 감고, 그래도 늦으면 앞부분을 건너뜀
		rate = clamp(impact / hit_at, 1.0, max_rate)
		start = max(0.0, impact - hit_at * rate)
	_ap.play(n, 0.08)
	_ap.speed_scale = rate
	# 같은 동작이 이미 재생 중이면 play()만으로는 처음부터 다시 안 함 → 항상 시작 위치로 옮김
	_ap.seek(start, false)
	_oneshot_left = max(0.05, (anim.length - start) / rate - 0.12)
	_loco = ""
	return true


## 예전 그림 병사와 같은 사용법: "attack" | "hit"
func play(action: String) -> void:
	_oneshot(action)


## 근접 공격. windup = 휘두르기 시작부터 맞을 때까지 시간
func play_attack(windup: float) -> void:
	_oneshot("attack", windup)


## 활: 겨누기(windup초 동안) → release()에서 쏘기
func play_aim(windup: float) -> void:
	if _oneshot("aim"):
		_oneshot_left = windup + 0.05


func play_shoot() -> void:
	if not _oneshot("shoot", 0.05):
		_oneshot("attack", 0.05)


## 맞음. blocked = 방패로 막는 동작을 보여 줌
func play_hit(blocked: bool) -> void:
	if blocked and _oneshot("block"):
		return
	_oneshot("hit")


## 바다로 떨어지는 중: 허우적거리는 동작을 계속
func play_fall() -> void:
	if _ap == null or not _anims.has("fall"):
		return
	_oneshot_left = 0.0
	_set_loco("fall", 1.0, 0.1)


## 쓰러짐: 죽는 동작 후 마지막 자세로 멈춤
func play_death() -> void:
	if _ap == null:
		return
	if _anims.has("death"):
		var list: Array = _anims["death"]
		var n: String = list[randi() % list.size()]
		_ap.get_animation(n).loop_mode = Animation.LOOP_NONE
		_ap.play(n, 0.1)
		_ap.speed_scale = 1.0
	_hold = true


## 시체가 됨: 병사 노드에서 떨어져 나와 혼자 시간을 흘리다가 땅속으로 가라앉고 사라짐
## clock: 전투 관리자. 일시정지·슬로모션 때 쓰러지는 동작과 가라앉기도 같이 멈추거나 느려짐
func become_corpse(stay: float, clock: Node = null) -> void:
	_driven = false
	_clock = clock
	play_death()
	_sink = create_tween()
	_sink.tween_interval(stay)
	_sink.tween_property(self, "position:y", position.y - 0.3, 1.2)
	_sink.tween_callback(queue_free)


func play_cheer() -> void:
	_oneshot("cheer")


## 분대장 표시(망토 등)를 켜고 끔. 장비가 없으면 몸을 조금 키워서 구분
func set_leader(on: bool) -> void:
	for g in _gear_leader:
		g.visible = on
	if _gear_leader.is_empty():
		scale = _base_scale * (1.12 if on else 1.0)


func can_be_leader() -> bool:
	return true


## 이름에 단어가 들어간 애니메이션 찾기 (대소문자 무시)
func _guess(kind: String, have: PackedStringArray) -> Array:
	var out: Array = []
	for n in have:
		var low := n.to_lower()
		if kind == "idle" and ("attack" in low or "ranged" in low):
			continue
		for kw in KEYWORDS[kind]:
			if str(kw) in low:
				out.append(n)
				break
	return out
