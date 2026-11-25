extends RefCounted
## 분대 하나 = 지휘관 1명이 이끄는 병사 여러 명
##
## - 분대는 "기준 칸(anchor_cell)" 하나를 차지하고, 병사들은 그 칸 안에 둥글게 섭니다.
## - 이동 명령을 받으면 도착할 때까지 행군 상태(marching)가 됩니다.
##   행군 중에도 몸에 닿을 만큼 가까운 적은 공격하고, 적이 없으면 다시 걸어갑니다.
## - 집에서 회복: 병사가 줄어든 분대를 멀쩡한 집 칸으로 보내면(또는 집 칸에서 R 키) 집 안으로 들어갑니다.
##   집 안에서는 싸우지 않고(적에게 맞지도 않음) 병사가 REST_PER_SOLDIER초마다 1명씩 돌아오며, 다 차면 나옵니다.
##   도중에 이동 명령을 내리면 바로 나오고, 집이 불타면 쫓겨나옵니다.

const REST_PER_SOLDIER := 5.0  # 집 안에서 병사 1명이 돌아오는 시간(초). 남은 병사 체력도 이 시간에 다 참
const MARCH_TIMEOUT := 8.0     # 최소 행군 시간 한도. 먼 길이면 길이에 맞춰 늘어남(order_move)

var battle
var commander: Dictionary    # Game.roster 항목 {id, name, cls, level}
var index: int = 0           # 화면 표시 번호(0부터)
var units: Array = []
var max_soldiers: int = 5
var hp_mult: float = 1.0
var dmg_mult: float = 1.0
var anchor_cell := Vector2i.ZERO
var marching := false
var march_t := 0.0
var march_limit := MARCH_TIMEOUT  # 이 시간 동안 싸우지 않고 걸었는데도 도착 못 하면 행군 종료
var resting := false        # 집 안에서 회복 중
var rest_t := 0.0
var engaged := false        # 행군 중 적과 맞붙어 있는가 (병사가 매 단계 알려 줌)
var speed_mult: float = 1.0
var path_cells: Array = []  # 행군 경로(점선 표시용)
var skill_cd := 0.0          # 기술을 다시 쓸 수 있을 때까지 남은 시간
var item_used := false       # 이번 전투에서 장비(1회용)를 썼는가
var label: Label3D


func setup(p_battle, p_commander: Dictionary, p_index: int, cell: Vector2i, soldiers: int, p_hp_mult: float, p_dmg_mult: float, p_speed_mult: float = 1.0) -> void:
	battle = p_battle
	commander = p_commander
	index = p_index
	anchor_cell = cell
	max_soldiers = soldiers
	hp_mult = p_hp_mult
	dmg_mult = p_dmg_mult
	speed_mult = p_speed_mult
	for i in range(max_soldiers):
		units.append(_spawn_soldier(slot_position(i)))
	_reindex()


func type_id() -> String:
	return str(commander.get("cls", "militia"))


func is_wiped() -> bool:
	return units.is_empty()


func has_skill() -> bool:
	return bool(commander.get("skill", false)) and type_id() != "militia"


func skill_ready() -> bool:
	return has_skill() and skill_cd <= 0.0


func item_ready() -> bool:
	var item := str(commander.get("item", ""))
	return item != "" and not item_used and bool(battle.Catalog.ITEMS.get(item, {}).get("active", false))


## 쓰러진 병사를 모두 그 자리에서 되살림 (뿔나팔)
func refill() -> void:
	var c := centroid()
	while units.size() < max_soldiers:
		var u = _spawn_soldier(c + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2)))
		units.append(u)
	_reindex()


func anchor_pos() -> Vector3:
	return battle.cell_center(anchor_cell)


## i번째 병사가 서야 할 위치 (해바라기 씨앗 배열로 고르게 퍼짐)
func slot_position(i: int) -> Vector3:
	var center := anchor_pos()
	var n: int = max(1, max_soldiers)
	var r: float
	var a: float
	if battle.house_at(anchor_cell) != null:
		r = 0.42  # 집이 가운데 있으니 둘레에 섬
		a = float(i) * TAU / float(n)
	else:
		r = 0.36 * sqrt((float(i) + 0.5) / float(n))
		a = float(i) * 2.39996
	return center + Vector3(cos(a) * r, 0.0, sin(a) * r)


## 이동 명령. path는 화면에 점선으로 그릴 경로(칸 목록).
func order_move(cell: Vector2i, path: Array = []) -> void:
	if resting:
		_exit_rest()  # 칸을 바꾸기 전에 먼저 지금 집 둘레로 나옴 (순간이동 방지)
	anchor_cell = cell
	path_cells = path
	marching = true
	march_t = 0.0
	# 길이 길수록 시간 한도도 늘림 (칸 1개 ≈ 1m, 넉넉하게 2배)
	var spd: float = 1.4 * speed_mult
	march_limit = max(MARCH_TIMEOUT, float(path.size()) / spd * 2.0 + 3.0)


func tick(dt: float) -> void:
	# 죽은 병사 정리
	var alive: Array = []
	for u in units:
		if is_instance_valid(u) and u.state != u.State.DEAD:
			alive.append(u)
	if alive.size() != units.size():
		units = alive
		_reindex()
	if units.is_empty():
		return
	skill_cd = max(0.0, skill_cd - dt)

	if resting:
		_tick_rest(dt)
		return

	if marching:
		if not engaged:
			march_t += dt  # 싸우는 동안은 행군 시간에 안 셈
		engaged = false
		# 모두 기준 칸 안(중심에서 0.6m, 집 칸은 집 둘레에 서므로 0.85m 이내)에 들어오면 도착
		var arrived := true
		var center := anchor_pos()
		var arrive_r := 0.85 if battle.house_at(anchor_cell) != null else 0.6
		for u in units:
			if u.state == u.State.ACTIVE and Vector2(u.position.x - center.x, u.position.z - center.z).length() > arrive_r:
				arrived = false
				break
		if arrived or march_t > march_limit:
			marching = false
			path_cells = []
			# 다친 분대가 집 칸에 오면 들어가서 회복
			if needs_rest():
				try_rest()


# ---------------------------------------------------------------- 집에서 회복

## 병사가 줄었거나 다친 병사가 있는가
func needs_rest() -> bool:
	if units.size() < max_soldiers:
		return true
	for u in units:
		if u.hp < u.max_hp * 0.99:
			return true
	return false


## 지금 선 칸이 멀쩡한 집이면 집 안으로 들어가 회복 시작. 성공하면 true
func try_rest() -> bool:
	if resting or marching or units.is_empty() or not needs_rest():
		return false
	var house = battle.house_at(anchor_cell)
	if house == null or not house.intact:
		return false
	resting = true
	rest_t = 0.0
	for u in units:
		u.enter_rest(house.position)
	battle.squad_rest_changed.emit(self, true)
	return true


func _tick_rest(dt: float) -> void:
	var house = battle.house_at(anchor_cell)
	if house == null or not house.intact:
		_exit_rest()  # 집이 불타면 쫓겨나옴
		return
	for u in units:
		u.hp = min(u.max_hp, u.hp + u.max_hp * dt / REST_PER_SOLDIER)
	if units.size() < max_soldiers:
		rest_t += dt
		if rest_t >= REST_PER_SOLDIER:
			rest_t = 0.0
			var u = _spawn_soldier(house.position)
			u.enter_rest(house.position)
			units.append(u)
			_reindex()
			battle.squad_reinforced.emit(self)
	elif not needs_rest():
		_exit_rest()  # 다 회복하면 나와서 다시 싸움


## 회복 진행도 0~1 (화면 표시용)
func rest_progress() -> float:
	return clamp(rest_t / REST_PER_SOLDIER, 0.0, 1.0)


func _exit_rest() -> void:
	if not resting:
		return
	resting = false
	for i in range(units.size()):
		units[i].exit_rest(slot_position(i))
	battle.squad_rest_changed.emit(self, false)


func centroid() -> Vector3:
	var sum := Vector3.ZERO
	for u in units:
		sum += u.position
	return sum / float(max(1, units.size()))


func _spawn_soldier(pos: Vector3):
	var u = battle.spawn_unit(type_id(), 0, pos, hp_mult, dmg_mult, tier())
	u.squad = self
	u.speed_mult = speed_mult
	return u


## 병사 그림 단계: Lv1~2 기본, Lv3 숙련, Lv4 정예
func tier() -> String:
	var lv := int(commander.get("level", 1))
	if lv >= 4:
		return "elite"
	if lv >= 3:
		return "veteran"
	return "basic"


func _reindex() -> void:
	var has_leader := false
	for i in range(units.size()):
		units[i].slot_index = i
		if units[i].is_leader:
			has_leader = true
	# 지휘관(분대장)이 쓰러지면 남은 병사 중 첫 번째가 지휘관 모습을 이어받음
	if not has_leader and not units.is_empty():
		units[0].set_leader(true)
