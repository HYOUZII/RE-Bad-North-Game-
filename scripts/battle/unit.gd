extends Node3D
## 병사 한 명 (아군·적군 공통)
##
## 스스로 _process를 쓰지 않고, 전투 관리자(battle.gd)가 매 단계 tick()을 불러 줍니다.
## 그래서 일시정지, 슬로모션, 테스트용 빨리감기를 battle.gd 한 곳에서 조절할 수 있습니다.
##
## 행동 순서: 넉백 처리 → 공격 준비(휘두르기) 처리 → 생각(목표 고르기, 이동/공격) → 높이 맞추기

const UnitDefs := preload("res://scripts/battle/unit_defs.gd")

enum State { BOAT, ACTIVE, FALLING, DEAD }

const STUN_SPEED := 0.35        # 넉백 속도가 이보다 크면 아무것도 못 함(비틀거림)
const KNOCK_FRICTION := 7.0     # 넉백이 줄어드는 속도
const FALL_TIME := 0.8          # 바다에 빠진 뒤 사라질 때까지 시간
const FALL_DAMAGE_PER_STEP := 8.0  # 넉백으로 2단 이상 절벽에서 떨어질 때 1단당 피해

var battle  # battle.gd (서로 참조해서 타입은 생략)
var type_id: String = ""
var def: Dictionary = {}
var team: int = 0               # 0 = 아군, 1 = 적
var squad = null                # 아군만: 소속 분대(squad.gd)
var slot_index: int = 0
var max_hp: float = 1.0
var hp: float = 1.0
var damage_mult: float = 1.0
var state: int = State.ACTIVE
var velocity := Vector3.ZERO    # 화살 조준(예측 사격)용
var knock_vel := Vector3.ZERO

var _attack_cd := 0.0
var _ranged_cd := 0.0
var _windup := 0.0
var _windup_target = null
var _windup_ranged := false
var _windup_house = null
var _target = null
var _retarget_t := 0.0
var _path: Array[Vector2i] = []
var _path_goal := Vector2i(1 << 20, 1 << 20)
var _path_age := 0.0
var _fall_t := 0.0
var _last_pos := Vector3.ZERO
var _model: Node3D


func setup(p_battle, p_type: String, p_team: int, hp_mult: float, dmg_mult: float) -> void:
	battle = p_battle
	type_id = p_type
	team = p_team
	def = UnitDefs.get_def(p_type)
	max_hp = float(def["hp"]) * hp_mult
	hp = max_hp
	damage_mult = dmg_mult
	_model = Assets.get_model(p_type)
	add_child(_model)
	# 처음 공격 타이밍을 조금씩 어긋나게(모두 동시에 휘두르지 않게)
	_attack_cd = randf_range(0.0, 0.4)
	_ranged_cd = randf_range(0.0, 0.8)


func radius() -> float:
	return float(def["radius"])


func is_ranged() -> bool:
	return float(def["range"]) > 0.0


## 공격 대상이 될 수 있는 상태인가 (배 위 = 화살로만 맞힐 수 있음)
func is_targetable() -> bool:
	return state == State.ACTIVE or state == State.BOAT


static func valid(u) -> bool:
	return u != null and is_instance_valid(u) and u.is_targetable()


func tick(dt: float) -> void:
	velocity = (position - _last_pos) / max(dt, 0.0001)
	_last_pos = position
	match state:
		State.DEAD, State.BOAT:
			return
		State.FALLING:
			_fall_t += dt
			position.y -= dt * 2.5
			if _fall_t >= FALL_TIME:
				battle.kill_unit(self, "drown")
			return

	_attack_cd -= dt
	_ranged_cd -= dt
	_retarget_t -= dt
	_path_age += dt

	# 1) 넉백: 밀리는 중에는 바다나 절벽 아래로도 떨어질 수 있음
	if knock_vel.length_squared() > 0.0004:
		_try_move(knock_vel * dt, true)
		if state != State.ACTIVE:
			return
		knock_vel = knock_vel.move_toward(Vector3.ZERO, KNOCK_FRICTION * dt)
		if knock_vel.length() > STUN_SPEED:
			_cancel_windup()
			_update_height(dt)
			return

	# 2) 휘두르는 중이면 끝날 때까지 기다렸다가 판정
	if _windup > 0.0:
		_windup -= dt
		if _windup <= 0.0:
			_resolve_attack()
		_update_height(dt)
		return

	# 3) 생각하기
	if team == 0:
		_think_player(dt)
	else:
		_think_enemy(dt)
	_update_height(dt)


# ---------------------------------------------------------------- 아군 행동

func _think_player(dt: float) -> void:
	var slot: Vector3 = squad.slot_position(slot_index)
	if squad.marching:
		_target = null
		_move_toward(slot, dt, 0.05)
		return
	if _retarget_t <= 0.0 or not valid(_target):
		_target = battle.find_target_for_player(self)
		_retarget_t = 0.25
	if valid(_target):
		var d := _flat_dist(_target.position)
		var gap: float = d - radius() - _target.radius()
		# 근접 거리 안이면 근접 공격 (궁수도 바로 붙은 적에게는 칼을 씀)
		if _target.state == State.ACTIVE and gap <= float(def["reach"]):
			_face(_target.position)
			if _attack_cd <= 0.0:
				_start_attack(_target, false)
			return
		if is_ranged():
			if _ranged_cd <= 0.0 and d <= battle.effective_range(self, _target):
				_start_attack(_target, true)
				return
		elif _target.state == State.ACTIVE:
			# 근접 병종: 분대 위치에서 너무 멀어지지 않는 선에서 쫓아감
			if squad.anchor_pos().distance_to(_target.position) < battle.LEASH_RADIUS:
				_move_toward(_target.position, dt, 0.0)
				return
	_move_toward(slot, dt, 0.05)


# ---------------------------------------------------------------- 적 행동

func _think_enemy(dt: float) -> void:
	if _retarget_t <= 0.0 or not valid(_target):
		_target = battle.find_target_for_enemy(self)
		_retarget_t = 0.3
	if valid(_target):
		var d := _flat_dist(_target.position)
		var gap: float = d - radius() - _target.radius()
		if gap <= float(def["reach"]):
			_face(_target.position)
			if _attack_cd <= 0.0:
				_start_attack(_target, false)
			return
		if is_ranged() and _ranged_cd <= 0.0 and d <= battle.effective_range(self, _target):
			_start_attack(_target, true)
			return
		if not is_ranged() or d > battle.effective_range(self, _target):
			_move_toward(_target.position, dt, 0.0)
		return
	# 주변에 아군이 없으면 가장 가까운 집을 공격하러 감
	var house = battle.nearest_intact_house(position)
	if house != null:
		var hd := _flat_dist(house.position)
		if hd <= 0.6 + radius():
			_face(house.position)
			if _attack_cd <= 0.0:
				_windup = float(def["windup"])
				_windup_house = house
				_attack_cd = float(def["cooldown"])
			return
		_move_toward(house.position, dt, 0.0)
		return
	# 집이 모두 불탔으면 아군을 사냥
	var prey = battle.nearest_player_unit(position)
	if prey != null:
		_target = prey
		_move_toward(prey.position, dt, 0.0)


# ---------------------------------------------------------------- 공격

func _start_attack(t, ranged: bool) -> void:
	_windup_target = t
	_windup_ranged = ranged
	_windup_house = null
	if ranged:
		_windup = 0.35
		_ranged_cd = float(def["ranged_cooldown"]) * randf_range(0.9, 1.1)
	else:
		_windup = float(def["windup"])
		_attack_cd = float(def["cooldown"]) * randf_range(0.9, 1.1)
	_face(t.position)
	battle.unit_attack_started.emit(self, t)


func _resolve_attack() -> void:
	if _windup_house != null:
		var h = _windup_house
		_windup_house = null
		if is_instance_valid(h) and h.intact and _flat_dist(h.position) <= 0.75 + radius():
			battle.damage_house(self, h, float(def["house_damage"]) * damage_mult)
		return
	var t = _windup_target
	_windup_target = null
	if not valid(t):
		return
	if _windup_ranged:
		battle.fire_arrow(self, t)
	elif t.state == State.ACTIVE:
		var gap: float = _flat_dist(t.position) - radius() - t.radius()
		if gap <= float(def["reach"]) + 0.15:
			battle.melee_hit(self, t)


func _cancel_windup() -> void:
	_windup = 0.0
	_windup_target = null
	_windup_house = null


## 피해와 넉백을 받습니다. 체력 0 처리는 battle.gd가 합니다.
func take_hit(dmg: float, knock: Vector3) -> void:
	hp -= dmg
	knock_vel += knock
	if knock.length() > 1.0:
		_cancel_windup()  # 세게 맞으면 휘두르던 공격이 끊김


# ---------------------------------------------------------------- 이동

func _move_toward(goal: Vector3, dt: float, stop_dist: float) -> void:
	var to := Vector2(goal.x - position.x, goal.z - position.z)
	if to.length() <= stop_dist:
		return
	var my_cell: Vector2i = battle.world_to_cell(position)
	var goal_cell: Vector2i = battle.world_to_cell(goal)
	var waypoint := goal
	if goal_cell != my_cell and not battle.nav.can_step(my_cell, goal_cell):
		if goal_cell != _path_goal or _path_age > 1.0 or _path.is_empty():
			_path = battle.nav.find_path(my_cell, goal_cell)
			_path_goal = goal_cell
			_path_age = 0.0
		while not _path.is_empty() and _path[0] == my_cell:
			_path.remove_at(0)
		if _path.is_empty():
			return  # 갈 길이 없음
		waypoint = battle.cell_center(_path[0])
	var dir := Vector3(waypoint.x - position.x, 0.0, waypoint.z - position.z)
	var dist := dir.length()
	if dist < 0.001:
		return
	var step: float = min(dist, float(def["speed"]) * dt)
	var move_dir: Vector3 = battle.steer_around_houses(position, dir / dist, radius(), dist)
	if not _try_move(move_dir * step, false):
		_path_age = 2.0  # 막혔으면 다음에 길 다시 찾기
	_face(waypoint)


## 살짝 밀어내기(겹침 방지)용
func nudge(offset: Vector3) -> void:
	if state == State.ACTIVE:
		_try_move(offset, false)


## 이동을 시도합니다. 막히면 x, z 한 방향씩 미끄러지듯 다시 시도합니다.
## knock = true(넉백)이면 절벽 아래나 바다로도 밀려납니다.
func _try_move(delta: Vector3, knock: bool) -> bool:
	if _apply_move(delta, knock):
		return true
	if _apply_move(Vector3(delta.x, 0, 0), knock):
		return true
	return _apply_move(Vector3(0, 0, delta.z), knock)


func _apply_move(delta: Vector3, knock: bool) -> bool:
	if delta.length_squared() < 1e-10:
		return false
	var newp := position + delta
	var c0: Vector2i = battle.world_to_cell(position)
	var c1: Vector2i = battle.world_to_cell(newp)
	if c1 == c0:
		position.x = newp.x
		position.z = newp.z
		return true
	var tiles: Dictionary = battle.nav.tiles
	if not tiles.has(c1):
		if not knock:
			return false
		# 바다로 밀려남!
		position.x = newp.x
		position.z = newp.z
		state = State.FALLING
		_cancel_windup()
		battle.unit_fell.emit(self)
		return true
	if not tiles.has(c0):
		position.x = newp.x
		position.z = newp.z
		return true
	var dh := int(tiles[c1]) - int(tiles[c0])
	if dh > 1:
		return false  # 2단 이상 절벽은 못 올라감
	if dh < -1 and not knock:
		return false  # 걸어서는 2단 이상 뛰어내리지 않음
	position.x = newp.x
	position.z = newp.z
	if dh < -1:
		battle.fall_damage(self, FALL_DAMAGE_PER_STEP * float(-dh - 1))
	return true


func _update_height(dt: float) -> void:
	var ground: float = battle.ground_y(position)
	position.y = lerp(position.y, ground, min(1.0, dt * 14.0))


## 모델 정면(-Z)이 p를 보게 돌림
func _face(p: Vector3) -> void:
	var dx := p.x - position.x
	var dz := p.z - position.z
	if dx * dx + dz * dz > 0.0001:
		rotation.y = atan2(-dx, -dz)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - position.x, p.z - position.z).length()
