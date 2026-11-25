extends RefCounted
## 분대 하나 = 지휘관 1명이 이끄는 병사 여러 명
##
## - 분대는 "기준 칸(anchor_cell)" 하나를 차지하고, 병사들은 그 칸 안에 둥글게 섭니다.
## - 이동 명령을 받으면 도착할 때까지 행군 상태(marching)가 되어 싸우지 않습니다.
##   그래서 적과 붙어 있을 때 함부로 움직이면 위험합니다.
## - 멀쩡한 집 칸에 서 있고 근처에 적이 없으면 쓰러진 병사가 하나씩 돌아옵니다.

const REGEN_TIME := 2.5      # 병사 1명 회복 시간(초)
const MARCH_TIMEOUT := 8.0   # 이 시간이 지나면 도착 못 해도 행군 종료

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
var regen_t := 0.0
var label: Label3D


func setup(p_battle, p_commander: Dictionary, p_index: int, cell: Vector2i, soldiers: int, p_hp_mult: float, p_dmg_mult: float) -> void:
	battle = p_battle
	commander = p_commander
	index = p_index
	anchor_cell = cell
	max_soldiers = soldiers
	hp_mult = p_hp_mult
	dmg_mult = p_dmg_mult
	for i in range(max_soldiers):
		units.append(_spawn_soldier(slot_position(i)))
	_reindex()


func type_id() -> String:
	return str(commander.get("cls", "militia"))


func is_wiped() -> bool:
	return units.is_empty()


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


func order_move(cell: Vector2i) -> void:
	anchor_cell = cell
	marching = true
	march_t = 0.0
	regen_t = 0.0


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

	if marching:
		march_t += dt
		# 모두 기준 칸 안(중심에서 0.6m 이내)에 들어오면 도착. 다른 분대와 겹쳐 자리가 좁아도 멈추게.
		var arrived := true
		var center := anchor_pos()
		for u in units:
			if u.state == u.State.ACTIVE and Vector2(u.position.x - center.x, u.position.z - center.z).length() > 0.6:
				arrived = false
				break
		if arrived or march_t > MARCH_TIMEOUT:
			marching = false

	# 집에서 회복
	var house = battle.house_at(anchor_cell)
	if house != null and house.intact and not marching and units.size() < max_soldiers \
			and not battle.enemy_near(anchor_pos(), 2.5):
		regen_t += dt
		if regen_t >= REGEN_TIME:
			regen_t = 0.0
			units.append(_spawn_soldier(house.position))
			_reindex()
			battle.squad_reinforced.emit(self)
	else:
		regen_t = 0.0


func centroid() -> Vector3:
	var sum := Vector3.ZERO
	for u in units:
		sum += u.position
	return sum / float(max(1, units.size()))


func _spawn_soldier(pos: Vector3):
	var u = battle.spawn_unit(type_id(), 0, pos, hp_mult, dmg_mult)
	u.squad = self
	return u


func _reindex() -> void:
	for i in range(units.size()):
		units[i].slot_index = i
