extends Node3D
## 섬 전투 한 판을 관리합니다.
##
## 하는 일: 섬 만들기 → 집·분대 배치 → 웨이브마다 배 보내기 → 매 단계 유닛 움직이기 → 승패 판정
## 조작: 좌클릭으로 분대 선택 → 칸 좌클릭으로 이동 / 숫자키로 분대 선택 / Space 일시정지
##       F: 선택한 분대의 기술   G: 선택한 분대의 장비(전투마다 1번)
##
## 손맛(타격 효과, 화면 흔들림, 효과음)은 나중 단계에서 아래 신호(signal)에 연결해 붙입니다.
## 예: battle.unit_hit.connect(func(target, attacker, dmg, knock, ranged): ...)

signal battle_ended(result: Dictionary)
signal unit_hit(target, attacker, damage: float, knockback: Vector3, ranged: bool)
signal unit_died(unit, cause: String)          # cause: "melee" | "ranged" | "drown" | "fall"
signal unit_fell(unit)                         # 바다로 밀려 떨어지기 시작
signal unit_attack_started(unit, target)
signal house_damaged(house, damage: float)
signal house_burned(house)
signal boat_landed(boat)
signal wave_started(index: int, total: int)
signal squad_selected(squad)
signal squad_rest_changed(squad, resting: bool)  # 분대가 집에 들어감(true)/나옴(false)
signal squad_reinforced(squad)
signal skill_used(squad, skill_id: String)
signal item_used(squad, item_id: String)
signal explosion(position: Vector3, radius: float)

const IslandGenerator := preload("res://scripts/island/island_generator.gd")
const OrbitCamera := preload("res://scripts/camera/orbit_camera.gd")
const GridNav := preload("res://scripts/battle/grid_nav.gd")
const Unit := preload("res://scripts/battle/unit.gd")
const Squad := preload("res://scripts/battle/squad.gd")
const Boat := preload("res://scripts/battle/boat.gd")
const House := preload("res://scripts/battle/house.gd")
const Projectile := preload("res://scripts/battle/projectile.gd")
const WaveDirector := preload("res://scripts/battle/wave_director.gd")
const UnitDefs := preload("res://scripts/battle/unit_defs.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

# ---- 규칙 숫자 (밸런스 조절용) ----
const SLOWMO_SCALE := 0.35        # 분대를 고르는 동안 시간 느리게
const MAX_STEP := 1.0 / 30.0      # 한 번에 계산하는 최대 시간(너무 크면 벽을 뚫음)
const ENGAGE_RADIUS := 1.6        # 근접 분대가 적을 발견하는 거리(분대 위치 기준)
const LEASH_RADIUS := 2.4         # 근접 분대가 적을 쫓아가는 최대 거리
const HIGH_GROUND_DAMAGE := 0.25  # 높이 1단계 위에서 공격할 때 피해 +25%
const SELECT_COLOR := Color(0.35, 0.9, 1.0)  # 선택 강조색(하늘색). 창병 노랑과 겹치지 않게
const HIGH_GROUND_RANGE := 0.6    # 높이 1단계 위에서 활 사거리 +0.6m
const LOW_GROUND_MELEE := 0.85    # 아래에서 위로 근접 공격하면 피해 x0.85
const FIRST_WAVE_DELAY := 4.0
const WAVE_INTERVAL := 40.0       # 다음 웨이브까지 최대 대기 시간
const BREAK_AFTER_CLEAR := 4.0    # 웨이브를 다 잡으면 이 시간 뒤 다음 웨이브
const NO_CELL := Vector2i(1 << 20, 1 << 20)
const STALE_RETREAT_TIME := 45.0  # 마지막 웨이브에서 이 시간 동안 아무 싸움도 없으면 남은 적은 퇴각

var node_info: Dictionary = {}    # 캠페인 지도의 섬 정보 {name, difficulty, seed, radius, houses, final}
var commanders: Array = []        # 출전하는 지휘관 목록 (Game.roster 항목)
var auto_play := false            # 테스트용: 컴퓨터가 대신 지휘
var speed := 1.0                  # 테스트용 빨리감기 배율

var island
var nav
var camera_rig
var units: Array = []
var squads: Array = []
var houses: Array = []
var boats: Array = []
var projectiles: Array = []
var waves: Array = []
var wave_index := -1
var wave_timer := FIRST_WAVE_DELAY
var selected = null
var paused := false
var finished := false
var elapsed := 0.0
var result: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _units_root: Node3D
var _fx_root: Node3D
var _hover_cell := NO_CELL
var _sel_marker: Node3D
var _hover_marker: Node3D
var _hover_bad: Node3D
var _path_root: Node3D
var _path_key := ""
var _hud_top: Label
var _hud_squads: Label
var _hud_help: Label
var _result_panel: PanelContainer
var _result_label: Label
var _auto_t := 0.0
var _last_action_t := 0.0
var _action_box: HBoxContainer
var _skill_btn: Button
var _toast_label: Label
var _toast_t := 0.0
var _item_btn: Button


## add_child 하기 전에 부릅니다.
func setup(p_node: Dictionary, p_commanders: Array) -> void:
	node_info = p_node
	commanders = p_commanders


func _ready() -> void:
	_rng.seed = int(node_info.get("seed", randi()))
	_setup_world()

	island = IslandGenerator.new()
	island.name = "Island"
	island.radius = int(node_info.get("radius", 7))
	add_child(island)
	island.generate(int(node_info.get("seed", 1)), int(node_info.get("houses", 3)))
	nav = GridNav.new()
	nav.build(island)

	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)
	_fx_root = Node3D.new()
	_fx_root.name = "Effects"
	add_child(_fx_root)

	_spawn_houses()
	_spawn_squads()

	var difficulty := int(node_info.get("difficulty", 0))
	waves = WaveDirector.build(difficulty, _rng, bool(node_info.get("final", false)))

	camera_rig = OrbitCamera.new()
	camera_rig.name = "OrbitCamera"
	camera_rig.distance = 6.0 + island.radius * 2.1
	camera_rig.max_distance = camera_rig.distance + 12.0
	add_child(camera_rig)

	_sel_marker = Assets.get_model("cell_marker")
	_sel_marker.visible = false
	add_child(_sel_marker)
	_hover_marker = Assets.get_model("hover_marker")
	_hover_marker.visible = false
	add_child(_hover_marker)
	_hover_bad = Assets.get_model("hover_marker_bad")
	_hover_bad.visible = false
	add_child(_hover_bad)
	_path_root = Node3D.new()
	_path_root.name = "PathDots"
	add_child(_path_root)

	_setup_hud()


# ================================================================ 격자 도우미

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(round(p.x)), int(round(p.z)))


func height_steps(cell: Vector2i) -> int:
	return int(island.tiles.get(cell, 0))


func ground_y(p: Vector3) -> float:
	return island.ground_height(p)


## 근접 공격이 닿는가: 같은 칸이거나 걸어서 바로 갈 수 있는 옆 칸 (절벽 너머는 못 때림)
func can_melee(a: Vector3, b: Vector3) -> bool:
	var ca := world_to_cell(a)
	var cb := world_to_cell(b)
	return ca == cb or nav.can_step(ca, cb)


func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, height_steps(cell) * island.step_height, cell.y)


func house_at(cell: Vector2i):
	for h in houses:
		if h.cell == cell:
			return h
	return null


# ================================================================ 배치

func _spawn_houses() -> void:
	var difficulty := int(node_info.get("difficulty", 0))
	for cell in island.house_cells:
		var h = House.new()
		h.setup(cell, _rng.randi_range(2, 3) + difficulty / 3, _rng.randi_range(0, 3))
		h.position = cell_center(cell)
		add_child(h)
		houses.append(h)


func _spawn_squads() -> void:
	# 집 칸부터, 그다음은 섬 중앙에 가까운 칸부터 배치
	var spots: Array = []
	for h in houses:
		spots.append(h.cell)
	var rest: Array = island.tiles.keys().filter(func(c): return island.is_walkable(c))
	rest.sort_custom(func(a, b): return Vector2(a).length() < Vector2(b).length())
	for c in rest:
		if not (c in spots):
			spots.append(c)
	for i in range(commanders.size()):
		var c: Dictionary = commanders[i]
		var s = Squad.new()
		s.setup(self, c, i, spots[i % spots.size()], Game.soldiers_for(c), Game.hp_mult(c), Game.dmg_mult(c), Game.speed_mult(c))
		s.label = Label3D.new()
		s.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.label.font_size = 64
		s.label.pixel_size = 0.009
		s.label.outline_size = 16
		s.label.no_depth_test = true
		s.label.text = str(i + 1)
		add_child(s.label)
		squads.append(s)


func spawn_unit(type_id: String, team: int, pos: Vector3, hp_mult: float, dmg_mult: float):
	var u = Unit.new()
	u.setup(self, type_id, team, hp_mult, dmg_mult)
	u.position = pos
	u.name = "%s_%d" % [type_id, units.size()]
	_units_root.add_child(u)
	u._last_pos = pos
	units.append(u)
	return u


func land_unit(u, cell: Vector2i) -> void:
	if not is_instance_valid(u):
		return
	u.state = u.State.ACTIVE
	u.position = cell_center(cell) + Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.2, 0.2))
	u.rotation = Vector3.ZERO


func remove_boat(b) -> void:
	boats.erase(b)
	b.queue_free()


# ================================================================ 매 단계 진행

func _physics_process(delta: float) -> void:
	if finished or paused:
		return
	var scale := speed
	if selected != null and not auto_play:
		scale *= SLOWMO_SCALE
	var total := delta * scale
	var steps: int = max(1, int(ceil(total / MAX_STEP)))
	var dt := total / float(steps)
	for _i in range(steps):
		_step(dt)
		if finished:
			break


func _step(dt: float) -> void:
	elapsed += dt
	_update_waves(dt)
	for b in boats.duplicate():
		b.tick(dt)
	for u in units.duplicate():
		if is_instance_valid(u) and u.state != u.State.DEAD:
			u.tick(dt)
	_charge_contacts()
	_separate()
	for p in projectiles.duplicate():
		p.tick(dt)
	for s in squads:
		s.tick(dt)
	if auto_play:
		_auto_command(dt)
	_check_end()


func _update_waves(dt: float) -> void:
	if wave_index >= waves.size() - 1:
		return
	wave_timer -= dt
	if wave_index >= 0 and enemy_count() == 0 and wave_timer > BREAK_AFTER_CLEAR:
		wave_timer = BREAK_AFTER_CLEAR
	if wave_timer <= 0.0:
		wave_index += 1
		_spawn_wave(waves[wave_index])
		wave_timer = WAVE_INTERVAL
		_last_action_t = elapsed + 20.0  # 배가 도착할 시간 여유
		wave_started.emit(wave_index, waves.size())


func _spawn_wave(boat_list: Array) -> void:
	# 상륙 지점: 높이 1인 해안(모래사장)을 우선, 서로 떨어진 곳으로
	var options: Array = island.get_beach_cells()
	if options.is_empty():
		options = island.get_shore_cells().filter(func(c): return island.is_walkable(c))
	_shuffle(options)
	var used: Array = []
	var difficulty := int(node_info.get("difficulty", 0))
	# 섬을 뚫고 지나가지 않고 바다로만 배를 댈 수 있는 곳만 고름
	var landings: Array = []  # [해안 칸, 바다 칸, 오는 방향]
	for c in options:
		var l := _landing_for(c)
		if not l.is_empty():
			landings.append(l)
	if landings.is_empty():
		return  # 이런 섬은 생성 단계에서 거의 안 나오지만, 혹시 나오면 이번 웨이브는 건너뜀
	for crew in boat_list:
		var pick = null
		for l in landings:
			var far_enough := true
			for u in used:
				if Vector2(l[0] - u).length() < 3.0:
					far_enough = false
					break
			if far_enough:
				pick = l
				break
		if pick == null:
			pick = landings[_rng.randi_range(0, landings.size() - 1)]
		used.append(pick[0])
		var b = Boat.new()
		add_child(b)
		b.setup(self, pick[0], pick[1], crew, WaveDirector.enemy_hp_mult(difficulty), WaveDirector.enemy_dmg_mult(difficulty), pick[2])
		boats.append(b)


## 해안 칸 cell에 배를 댈 수 있으면 [cell, 바다 칸, 바다로 나가는 방향]을, 없으면 []을 돌려줍니다.
## 방향은 바다 칸에서 멀리까지 곧게 그은 선이 섬의 어떤 칸과도 겹치지 않는 것만 씁니다.
func _landing_for(cell: Vector2i) -> Array:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var sea: Vector2i = cell + d
		if island.tiles.has(sea):
			continue
		var base := Vector3(d.x, 0.0, d.y)
		for deg in [0.0, 25.0, -25.0, 50.0, -50.0, 75.0, -75.0]:
			var dir := base.rotated(Vector3.UP, deg_to_rad(deg))
			if _sea_lane_clear(Vector3(sea.x, 0.0, sea.y), dir):
				return [cell, sea, dir]
	return []


## start에서 dir 방향으로 Boat.SPAWN_DISTANCE만큼 가는 동안 배(폭 약 0.7)가 육지에 닿지 않는가
func _sea_lane_clear(start: Vector3, dir: Vector3) -> bool:
	const HALF := 0.5 + 0.4  # 칸 반 크기 + 배 반 폭(여유 포함)
	var t := 0.0
	while t <= Boat.SPAWN_DISTANCE + 1.0:
		var p := start + dir * t
		var cx := int(round(p.x))
		var cz := int(round(p.z))
		for x in range(cx - 1, cx + 2):
			for z in range(cz - 1, cz + 2):
				if island.tiles.has(Vector2i(x, z)) and absf(p.x - x) < HALF and absf(p.z - z) < HALF:
					return false
		t += 0.25
	return true


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## 유닛끼리, 유닛과 집이 겹치지 않게 살짝 밀어냅니다.
func _separate() -> void:
	var land: Array = []
	for u in units:
		if u.state == u.State.ACTIVE:
			land.append(u)
	var n := land.size()
	for i in range(n):
		var a = land[i]
		for j in range(i + 1, n):
			var b = land[j]
			var dx: float = b.position.x - a.position.x
			var dz: float = b.position.z - a.position.z
			var min_d: float = a.radius() + b.radius()
			var d2 := dx * dx + dz * dz
			if d2 >= min_d * min_d:
				continue
			var d := sqrt(d2)
			var dir := Vector3(dx, 0, dz) / d if d > 0.0001 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
			var push := (min_d - d) * 0.5
			var ma: float = float(a.def["mass"]) * a.mod("mass")
			var mb: float = float(b.def["mass"]) * b.mod("mass")
			a.nudge(-dir * push * (mb / (ma + mb)) * 2.0)
			b.nudge(dir * push * (ma / (ma + mb)) * 2.0)
	for h in houses:
		for u in land:
			var dx: float = u.position.x - h.position.x
			var dz: float = u.position.z - h.position.z
			var min_d: float = 0.32 + u.radius()
			var d2 := dx * dx + dz * dz
			if d2 < min_d * min_d and d2 > 0.000001:
				var d := sqrt(d2)
				var out := Vector3(dx, 0, dz) / d
				u.nudge(out * (min_d - d))


## 가려는 방향 앞에 집이 있으면 옆으로 돌아가는 방향을 돌려줍니다.
func steer_around_houses(pos: Vector3, dir: Vector3, r: float, goal_dist: float) -> Vector3:
	for h in houses:
		var to_h := Vector3(h.position.x - pos.x, 0.0, h.position.z - pos.z)
		var d := to_h.length()
		var min_d := 0.34 + r
		if d < 0.001 or d > goal_dist + min_d or d > 1.2:
			continue
		var ahead := to_h.dot(dir)
		if ahead <= 0.0:
			continue  # 집이 뒤쪽
		var lateral := (to_h - dir * ahead).length()
		if lateral >= min_d:
			continue  # 비켜 지나감
		# 집 둘레의 접선 방향 중 원래 방향에 가까운 쪽으로
		var tangent := Vector3(-to_h.z, 0.0, to_h.x) / d
		if tangent.dot(dir) < 0.0:
			tangent = -tangent
		if tangent.dot(dir) < 0.05:
			# 정면으로 마주 봄: 원래 방향의 오른쪽을 기준으로 고정해 망설이지 않게
			var right := Vector3(-dir.z, 0.0, dir.x)
			tangent = right if right.dot(tangent) >= 0.0 else -right
		return (tangent + dir * 0.2).normalized()
	return dir


# ================================================================ 목표 찾기

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 높은 곳에서 쏘면 사거리가 늘어남
func effective_range(shooter, target) -> float:
	var diff := height_steps(world_to_cell(shooter.position)) - _steps_of(target)
	return float(shooter.def["range"]) * shooter.mod("range") + HIGH_GROUND_RANGE * float(max(0, diff))


func _steps_of(u) -> int:
	if u.state == u.State.BOAT:
		return 0
	return height_steps(world_to_cell(u.position))


func find_target_for_player(u):
	var best = null
	var best_d := INF
	if u.is_ranged():
		# 바로 붙은 적이 있으면 그 적 먼저(칼로 방어)
		for e in units:
			if e.team == 1 and e.state == e.State.ACTIVE:
				var d := _flat_dist(u.position, e.position)
				if d - u.radius() - e.radius() <= float(u.def["reach"]) and d < best_d:
					best = e
					best_d = d
		if best != null:
			return best
		for e in units:
			if e.team == 1 and e.is_targetable():
				var d := _flat_dist(u.position, e.position)
				if d < best_d and d <= effective_range(u, e):
					best = e
					best_d = d
		return best
	var anchor: Vector3 = u.squad.anchor_pos()
	for e in units:
		if e.team == 1 and e.state == e.State.ACTIVE:
			if _flat_dist(anchor, e.position) > ENGAGE_RADIUS:
				continue
			var d := _flat_dist(u.position, e.position)
			if d < best_d:
				best = e
				best_d = d
	return best


func find_target_for_enemy(u):
	var best = null
	var best_d := INF
	var reach: float = float(u.def["aggro"])
	for p in units:
		if p.team == 0 and p.state == p.State.ACTIVE:
			var d := _flat_dist(u.position, p.position)
			var limit := reach
			if u.is_ranged():
				limit = max(reach, effective_range(u, p))
			if d <= limit and d < best_d:
				best = p
				best_d = d
	return best


func nearest_intact_house(pos: Vector3):
	var best = null
	var best_d := INF
	for h in houses:
		if h.intact:
			var d := _flat_dist(pos, h.position)
			if d < best_d:
				best = h
				best_d = d
	return best


## 걸어서 가는 길이 가장 짧은 멀쩡한 집 (절벽을 돌아가야 하면 그만큼 멀다고 봄)
func nearest_house_by_path(pos: Vector3):
	var from := world_to_cell(pos)
	var best = null
	var best_len := INF
	for h in houses:
		if not h.intact:
			continue
		var p: Array = nav.find_path(from, h.cell)
		var length := INF
		if from == h.cell:
			length = 0.0
		elif not p.is_empty():
			length = 0.0
			for i in range(1, p.size()):
				length += Vector2(p[i] - p[i - 1]).length()
		if length < best_len:
			best_len = length
			best = h
	if best == null:
		return nearest_intact_house(pos)  # 길이 없으면 직선거리로라도
	return best


## 다른 분대가 이미 자리 잡은 칸인가 (한 칸에는 분대 하나만)
func cell_taken(cell: Vector2i, except_squad = null) -> bool:
	for s in squads:
		if s != except_squad and not s.is_wiped() and s.anchor_cell == cell:
			return true
	return false


## 분대가 이 칸으로 갈 수 있으면 경로(칸 목록)를, 못 가면 빈 배열을 돌려줍니다.
func order_path(s, cell: Vector2i) -> Array:
	if s == null or s.is_wiped() or not island.is_walkable(cell) or cell_taken(cell, s):
		return []
	var from := world_to_cell(s.centroid())
	if not nav.tiles.has(from) or not island.is_walkable(from):
		from = s.anchor_cell
	if from == cell:
		return [cell]
	return nav.find_path(from, cell)


func try_order(s, cell: Vector2i) -> bool:
	var path := order_path(s, cell)
	if path.is_empty():
		return false
	s.order_move(cell, path)
	return true


func nearest_player_unit(pos: Vector3):
	var best = null
	var best_d := INF
	for p in units:
		if p.team == 0 and p.state == p.State.ACTIVE:
			var d := _flat_dist(pos, p.position)
			if d < best_d:
				best = p
				best_d = d
	return best


## 행군 중인 병사 u의 몸에 닿을 만큼 가까운 적 (없으면 null)
func contact_enemy(u):
	var best = null
	var best_gap := float(u.def["reach"]) + 0.1
	for e in units:
		if e.team != 1 or e.state != e.State.ACTIVE:
			continue
		var gap: float = _flat_dist(u.position, e.position) - u.radius() - e.radius()
		if gap <= best_gap and can_melee(u.position, e.position):
			best_gap = gap
			best = e
	return best


func enemy_near(pos: Vector3, r: float) -> bool:
	for e in units:
		if e.team == 1 and e.state == e.State.ACTIVE and _flat_dist(pos, e.position) <= r:
			return true
	return false


func enemy_count() -> int:
	var n := 0
	for u in units:
		if u.team == 1:
			n += 1
	return n


func player_count() -> int:
	var n := 0
	for u in units:
		if u.team == 0:
			n += 1
	return n


# ================================================================ 전투 판정

## 공격자 정보 묶음 (화살은 쏜 사람이 죽은 뒤에도 날아가므로 미리 복사)
func attack_info(u) -> Dictionary:
	return {
		"unit": u,
		"team": u.team,
		"def": u.def,
		"steps": height_steps(world_to_cell(u.position)),
		"mult": u.damage_mult * u.mod("damage"),
		"knock_mult": u.mod("knock"),
		"ranged_knock_mult": u.mod("ranged_knock"),
		"pos": u.position,
	}


func melee_hit(attacker, target) -> void:
	_apply_damage(attack_info(attacker), target, float(attacker.def["damage"]), false)


func fire_arrow(shooter, target) -> void:
	var info := attack_info(shooter)
	var p = Projectile.new()
	_fx_root.add_child(p)
	# 날아가는 동안 움직일 위치를 대충 예측해서 조준
	var aim: Vector3 = target.position
	p.setup(self, info, aim, float(shooter.def["ranged_damage"]))
	var lead: Vector3 = target.velocity * p.flight_time() * 0.8
	lead.y = 0.0
	p.end = aim + lead + Vector3(_rng.randf_range(-0.12, 0.12), 0.2, _rng.randf_range(-0.12, 0.12))
	projectiles.append(p)


func arrow_impact(p) -> void:
	projectiles.erase(p)
	var best = null
	var best_d := INF
	var team: int = p.info["team"]
	for u in units:
		if u.team != team and u.is_targetable():
			var d := _flat_dist(p.end, u.position)
			if d <= 0.22 + u.radius() and d < best_d:
				best = u
				best_d = d
	if best != null:
		_apply_damage(p.info, best, p.damage, true)
	p.queue_free()


func _apply_damage(info: Dictionary, target, base: float, ranged: bool) -> void:
	if not target.is_targetable():
		return
	var adef: Dictionary = info["def"]
	var dmg: float = base * float(info["mult"])
	var diff: int = int(info["steps"]) - _steps_of(target)
	if diff > 0:
		dmg *= 1.0 + HIGH_GROUND_DAMAGE * float(diff)
	elif diff < 0 and not ranged:
		dmg *= LOW_GROUND_MELEE
	if ranged:
		dmg *= float(target.def["ranged_taken"]) * target.mod("ranged_taken")
	if bool(target.def["large"]):
		dmg *= float(adef["bonus_vs_large"])
	if bool(target.def["shielded"]) and not ranged:
		dmg *= float(adef["bonus_vs_shield"])
	var src: Vector3 = info["pos"]
	var dir := Vector3(target.position.x - src.x, 0.0, target.position.z - src.z)
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var kmult: float = float(info.get("ranged_knock_mult", 1.0)) if ranged else float(info.get("knock_mult", 1.0))
	var force: float = float(adef["ranged_knock"] if ranged else adef["knock"]) * kmult \
			/ (float(target.def["mass"]) * target.mod("mass"))
	if diff > 0:
		force *= 1.0 + 0.2 * float(diff)
	var kb := dir * force
	if target.state == target.State.BOAT:
		kb = Vector3.ZERO
	target.take_hit(dmg, kb)
	_last_action_t = elapsed
	var attacker = info["unit"] if is_instance_valid(info["unit"]) else null
	unit_hit.emit(target, attacker, dmg, kb, ranged)
	if target.hp <= 0.0:
		kill_unit(target, "ranged" if ranged else "melee")


## 폭발: 반경 안의 적(team이 아닌 쪽)에게 피해를 주고 바깥으로 날려 보냅니다.
func explode(pos: Vector3, team: int, dmg: float, radius: float, knock: float) -> void:
	var fx := Assets.get_model("blast")
	fx.position = Vector3(pos.x, ground_y(pos) + 0.02, pos.z)
	fx.scale = Vector3.ONE * (radius / 0.7)  # 임시 도형 기준 크기 보정
	_fx_root.add_child(fx)
	get_tree().create_timer(0.4).timeout.connect(fx.queue_free)
	explosion.emit(pos, radius)
	for u in units.duplicate():
		if u.team == team or not u.is_targetable():
			continue
		var d := _flat_dist(pos, u.position)
		if d > radius:
			continue
		var dir := Vector3(u.position.x - pos.x, 0.0, u.position.z - pos.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
		var kb := dir * knock * (1.0 - 0.5 * d / radius) / float(u.def["mass"])
		if u.state == u.State.BOAT:
			kb = Vector3.ZERO
		u.take_hit(dmg, kb)
		unit_hit.emit(u, null, dmg, kb, false)
		if u.hp <= 0.0:
			kill_unit(u, "explosion")


## 지금 기술을 못 쓰는 이유 ("" = 쓸 수 있음). 버튼과 안내 문구에 씁니다.
func skill_block_reason(s) -> String:
	if s == null or s.is_wiped() or not s.has_skill():
		return "기술 없음"
	if s.resting:
		return "집에서 회복 중"
	if not s.skill_ready():
		return "%d초" % int(ceil(s.skill_cd))
	var sk: Dictionary = Catalog.SKILLS[s.type_id()]
	if bool(sk.get("volley", false)) and _volley_targets(s).is_empty():
		return "사거리 안에 적 없음"
	return ""


## 일제 사격: 궁수마다 사거리 안에서 가장 가까운 적 [[궁수, 적], ...]
func _volley_targets(s) -> Array:
	var out: Array = []
	for u in s.units:
		if u.state != u.State.ACTIVE:
			continue
		var best = null
		var best_d := INF
		for e in units:
			if e.team != 1 or not e.is_targetable():
				continue
			var d := _flat_dist(u.position, e.position)
			if d < best_d and d <= effective_range_with(u, e, Catalog.SKILLS["archer"]["buff"]):
				best_d = d
				best = e
		if best != null:
			out.append([u, best])
	return out


## 기술 버프가 켜졌다고 치고 계산한 사거리 (기술 쓰기 전 판단용)
func effective_range_with(shooter, target, b: Dictionary) -> float:
	var diff := height_steps(world_to_cell(shooter.position)) - _steps_of(target)
	return float(shooter.def["range"]) * float(b.get("range", 1.0)) + HIGH_GROUND_RANGE * float(max(0, diff))


func use_skill(s) -> bool:
	var why := skill_block_reason(s)
	if why != "":
		if s != null and not auto_play:
			_toast("기술을 쓸 수 없음: " + why)
		return false
	var sk: Dictionary = Catalog.SKILLS[s.type_id()]
	s.skill_cd = float(sk["cooldown"])
	for u in s.units:
		u.apply_buff(sk["buff"], float(sk["duration"]))
	# 돌진: 가장 가까운 적 쪽으로 분대를 곧장 보냄
	if sk.has("rush"):
		var c: Vector3 = s.centroid()
		var best = null
		var best_d := float(sk["rush"])
		for e in units:
			if e.team == 1 and e.state == e.State.ACTIVE:
				var d := _flat_dist(c, e.position)
				if d < best_d:
					best_d = d
					best = e
		if best != null:
			try_order(s, world_to_cell(best.position))
	# 창벽: 쓰는 순간 주변 적을 한꺼번에 밀쳐 냄
	if sk.has("sweep"):
		var sw: Dictionary = sk["sweep"]
		var done := {}
		for u in s.units:
			for e in units.duplicate():
				if e.team != 1 or e.state != e.State.ACTIVE or done.has(e):
					continue
				if _flat_dist(u.position, e.position) <= float(sw["radius"]) and can_melee(u.position, e.position):
					done[e] = true
					_skill_hit(u, e, float(sw["damage"]), _push_dir(u, e, false) * float(sw["knock"]))
	# 일제 사격: 장전 대기 없이 바로 쏨 (행군 중이어도 쏨)
	if bool(sk.get("volley", false)):
		for pair in _volley_targets(s):
			fire_arrow(pair[0], pair[1])
			pair[0]._ranged_cd = float(pair[0].def["ranged_cooldown"]) * float(sk["buff"]["ranged_cd"])
	skill_used.emit(s, s.type_id())
	return true


## 기술로 적을 칠 때: 넉백은 적 무게로 나눠서 적용 (무거운 적은 덜 밀림)
func _skill_hit(attacker, target, dmg: float, push: Vector3) -> void:
	if not target.is_targetable() or target.state != target.State.ACTIVE:
		return
	var kb: Vector3 = push / (float(target.def["mass"]) * target.mod("mass"))
	target.take_hit(dmg, kb)
	_last_action_t = elapsed
	unit_hit.emit(target, attacker, dmg, kb, false)
	skill_hits += 1
	if target.hp <= 0.0:
		kill_unit(target, "melee")


## a가 b를 미는 방향. 달리는 중이면 달리는 방향을 더 따름(돌격)
func _push_dir(a, b, follow_motion: bool) -> Vector3:
	var away := Vector3(b.position.x - a.position.x, 0.0, b.position.z - a.position.z)
	away = away.normalized() if away.length() > 0.001 else Vector3.FORWARD
	if follow_motion:
		var mv: Vector3 = a.velocity
		mv.y = 0.0
		if mv.length() > 0.3:
			return (away * 0.6 + mv.normalized()).normalized()
	return away


## 방패 돌격 중인 병사가 몸에 닿은 적을 들이받음 (매 단계 호출)
var _charge_next := {}  # "병사id:적id" -> 다시 칠 수 있는 시각
var skill_hits := 0     # 기술로 친 횟수 (테스트 통계용)

func _charge_contacts() -> void:
	for u in units:
		if u.team != 0 or u.state != u.State.ACTIVE or u.buff_t <= 0.0 or u.squad == null:
			continue
		var sk: Dictionary = Catalog.SKILLS.get(u.squad.type_id(), {})
		if not sk.has("charge"):
			continue
		var ch: Dictionary = sk["charge"]
		for e in units.duplicate():
			if e.team != 1 or e.state != e.State.ACTIVE:
				continue
			if _flat_dist(u.position, e.position) > u.radius() + e.radius() + float(ch["reach"]):
				continue
			if not can_melee(u.position, e.position):
				continue
			var key := "%d:%d" % [u.get_instance_id(), e.get_instance_id()]
			if elapsed < float(_charge_next.get(key, -1.0)):
				continue
			_charge_next[key] = elapsed + float(ch["again"])
			_skill_hit(u, e, float(ch["damage"]), _push_dir(u, e, true) * float(ch["knock"]))


## 지금 장비를 못 쓰는 이유 ("" = 쓸 수 있음)
func item_block_reason(s) -> String:
	if s == null or s.is_wiped():
		return "분대 없음"
	var item := str(s.commander.get("item", ""))
	if not Catalog.item_active(item):
		return "쓰는 장비 없음"
	if s.item_used:
		return "이번 전투에 이미 사용함"
	if s.resting:
		return "집에서 회복 중"
	match item:
		"bomb":
			if _bomb_target(s) == null:
				return "근처(%dm)에 적 없음" % int(Catalog.BOMB_REACH)
		"horn":
			if s.units.size() >= s.max_soldiers:
				return "병사가 모두 살아 있음"
	return ""


## 화약 단지: 분대 근처에서 적이 가장 많이 모인 곳의 적
func _bomb_target(s):
	var c: Vector3 = s.centroid()
	var target = null
	var best := -1
	for e in units:
		if e.team != 1 or e.state != e.State.ACTIVE or _flat_dist(c, e.position) > Catalog.BOMB_REACH:
			continue
		var crowd := 0
		for o in units:
			if o.team == 1 and o.state == o.State.ACTIVE and _flat_dist(o.position, e.position) <= Catalog.BOMB_RADIUS:
				crowd += 1
		if crowd > best:
			best = crowd
			target = e
	return target


func use_item(s) -> bool:
	var why := item_block_reason(s)
	if why != "":
		if s != null and not auto_play:
			_toast("장비를 쓸 수 없음: " + why)
		return false
	var item := str(s.commander.get("item", ""))
	match item:
		"bomb":
			explode(_bomb_target(s).position, 0, Catalog.BOMB_DAMAGE, Catalog.BOMB_RADIUS, Catalog.BOMB_KNOCK)
		"horn":
			s.refill()
	s.item_used = true
	item_used.emit(s, item)
	return true


func fall_damage(u, dmg: float) -> void:
	u.hp -= dmg
	unit_hit.emit(u, null, dmg, Vector3.ZERO, false)
	if u.hp <= 0.0:
		kill_unit(u, "fall")


func damage_house(attacker, h, dmg: float) -> void:
	var burned: bool = h.take_damage(dmg)
	_last_action_t = elapsed
	house_damaged.emit(h, dmg)
	if burned:
		house_burned.emit(h)


func kill_unit(u, cause: String) -> void:
	if u.state == u.State.DEAD:
		return
	u.state = u.State.DEAD
	units.erase(u)
	unit_died.emit(u, cause)
	u.queue_free()


# ================================================================ 승패

func intact_house_count() -> int:
	var n := 0
	for h in houses:
		if h.intact:
			n += 1
	return n


func _check_end() -> void:
	if finished:
		return
	# 안전장치: 마지막 웨이브에서 오랫동안 싸움이 없으면(적이 길을 못 찾는 등) 남은 적은 퇴각
	if wave_index >= waves.size() - 1 and elapsed - _last_action_t > STALE_RETREAT_TIME:
		for u in units.duplicate():
			if u.team == 1:
				kill_unit(u, "retreat")
	if player_count() == 0 or intact_house_count() == 0:
		_finish(false)  # 병사가 모두 죽거나, 지킬 집이 하나도 안 남으면 패배
	elif wave_index >= waves.size() - 1 and enemy_count() == 0:
		_finish(true)


func _finish(won: bool) -> void:
	finished = true
	_select(null)
	var gold := 0
	var saved := 0
	for h in houses:
		if h.intact:
			saved += 1
			gold += h.gold
	var wiped: Array = []
	for s in squads:
		if s.is_wiped():
			wiped.append(s.commander["id"])
	result = {
		"won": won,
		"gold": gold if won else 0,
		"houses_saved": saved,
		"houses_total": houses.size(),
		"wiped": wiped,
		"time": elapsed,
	}
	if auto_play:
		_emit_end.call_deferred()
		return
	_show_result()


func _emit_end() -> void:
	battle_ended.emit(result)


# ================================================================ 입력

func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# 분대를 고른 뒤에는 다른 분대의 숫자 라벨을 눌러야만 바뀜 (옆 칸 클릭이 분대 선택으로 새지 않게)
			var sq = _pick_squad(mb.position) if selected == null else _pick_squad_label(mb.position)
			if sq != null and sq != selected:
				_select(sq)
			elif selected != null:
				var cell := _pick_cell(mb.position)
				# 갈 수 없는 칸(절벽 너머 막힘, 바위, 다른 분대 자리)이면 선택을 유지해서 다시 고르게 함
				if cell != NO_CELL and try_order(selected, cell):
					_select(null)  # 명령을 내리면 선택 해제(시간도 원래대로)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_hover_cell = _pick_cell((event as InputEventMouseMotion).position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9:
			var i := int(key - KEY_1)
			if i < squads.size() and not squads[i].is_wiped():
				_select(null if selected == squads[i] else squads[i])
		elif key == KEY_F:
			use_skill(selected)
		elif key == KEY_G:
			use_item(selected)
		elif key == KEY_R:
			rest_squad(selected)
		elif key == KEY_SPACE:
			paused = not paused
		elif key == KEY_ESCAPE:
			_select(null)


## R 키: 집 칸에 선 분대를 집 안으로 들여보내 회복
func rest_squad(s) -> bool:
	if s == null or s.is_wiped():
		return false
	if s.try_rest():
		return true
	if not auto_play:
		var h = house_at(s.anchor_cell)
		if s.marching:
			_toast("회복할 수 없음: 이동 중")
		elif h == null or not h.intact:
			_toast("회복할 수 없음: 멀쩡한 집 칸에 있어야 함")
		else:
			_toast("회복할 수 없음: 다친 병사가 없음")
	return false


func _select(s) -> void:
	selected = s
	squad_selected.emit(s)


## 화면 좌표 → 섬 칸 (각 타일 상자와 시선이 만나는지 직접 계산)
func _pick_cell(screen_pos: Vector2) -> Vector2i:
	if camera_rig == null or camera_rig.camera == null:
		return NO_CELL
	var cam: Camera3D = camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best := NO_CELL
	var best_d := INF
	for c in island.tiles.keys():
		var h: float = height_steps(c) * island.step_height
		var box := AABB(Vector3(c.x - 0.5, 0.0, c.y - 0.5), Vector3(1.0, h, 1.0))
		var hit = box.intersects_ray(from, dir)
		if hit != null:
			var d := from.distance_to(hit)
			if d < best_d:
				best_d = d
				best = c
	return best


func _pick_squad(screen_pos: Vector2):
	var cam: Camera3D = camera_rig.camera
	var best = null
	var best_d := 26.0
	for s in squads:
		for u in s.units:
			var wp: Vector3 = u.global_position + Vector3(0, 0.25, 0)
			if cam.is_position_behind(wp):
				continue
			var d := cam.unproject_position(wp).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = s
	return best


func _pick_squad_label(screen_pos: Vector2):
	var cam: Camera3D = camera_rig.camera
	var best = null
	var best_d := 22.0
	for s in squads:
		if s == selected or s.label == null or not s.label.visible:
			continue
		if cam.is_position_behind(s.label.global_position):
			continue
		var d := cam.unproject_position(s.label.global_position).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = s
	return best


# ================================================================ 화면 표시

func _process(_delta: float) -> void:
	for s in squads:
		if s.label == null:
			continue
		s.label.visible = not s.is_wiped()
		if s.label.visible:
			s.label.position = s.centroid() + Vector3(0, 1.15, 0)  # 집 골드 라벨보다 위
			s.label.modulate = SELECT_COLOR if s == selected else Color(1, 1, 1)
	if selected != null and not selected.is_wiped():
		_sel_marker.visible = true
		_sel_marker.position = cell_center(selected.anchor_cell) + Vector3(0, 0.01, 0)
		if house_at(selected.anchor_cell) != null:
			_sel_marker.position.y += 0.75  # 집에 가려지지 않게 지붕 위에 띄움
		var hover_ok := _hover_cell != NO_CELL and not order_path(selected, _hover_cell).is_empty()
		_hover_marker.visible = _hover_cell != NO_CELL and hover_ok
		_hover_bad.visible = _hover_cell != NO_CELL and not hover_ok
		if _hover_cell != NO_CELL:
			_hover_marker.position = cell_center(_hover_cell) + Vector3(0, 0.02, 0)
			if island.blocked.has(_hover_cell) or house_at(_hover_cell) != null:
				_hover_marker.position.y += 0.7  # 바위·집에 가려지지 않게 위로 띄움
			_hover_bad.position = _hover_marker.position
	else:
		_sel_marker.visible = false
		_hover_marker.visible = false
		_hover_bad.visible = false
	_refresh_paths()
	_update_hud()


## 이동 경로 점선: 행군 중인 분대는 흰 점, 선택 중 미리보기는 하늘색 점.
## 경로가 바뀔 때만 점을 다시 만듭니다.
func _refresh_paths() -> void:
	var lines: Array = []  # [[칸 목록, 미리보기 여부, 시작 위치]]
	for s in squads:
		if s.marching and not s.is_wiped() and s.path_cells.size() > 0:
			lines.append([s.path_cells, false, null])
	if selected != null and not selected.is_wiped() and _hover_cell != NO_CELL:
		var p := order_path(selected, _hover_cell)
		if not p.is_empty():
			lines.append([p, true, selected.centroid()])
	var key := str(lines.map(func(l): return [l[0], l[1]]))
	if key == _path_key:
		return
	_path_key = key
	for c in _path_root.get_children():
		c.queue_free()
	for l in lines:
		var pts: Array = []
		if l[2] != null:
			pts.append(l[2])
		for c in l[0]:
			pts.append(Vector3(c.x, 0.0, c.y))
		_spawn_dots(pts, "path_dot_preview" if l[1] else "path_dot")


func _spawn_dots(pts: Array, model_id: String) -> void:
	const GAP := 0.22  # 점 사이 간격(m)
	var carry := 0.0
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var seg := Vector2(b.x - a.x, b.z - a.z)
		var length := seg.length()
		var t := carry
		while t < length:
			var p := a.lerp(b, t / length)
			var dot := Assets.get_model(model_id)
			dot.position = Vector3(p.x, ground_y(p) + 0.03, p.z)
			_path_root.add_child(dot)
			t += GAP
		carry = t - length


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.90)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.78, 0.86)
	env.fog_density = 0.002
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	sea.mesh = plane
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color(0.13, 0.33, 0.50)
	sea_mat.roughness = 0.3
	sea.material_override = sea_mat
	sea.position.y = 0.02
	sea.name = "Sea"
	add_child(sea)


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_top = _make_label(20)
	_hud_top.position = Vector2(16, 12)
	layer.add_child(_hud_top)
	_hud_squads = _make_label(18)
	_hud_squads.anchor_top = 1.0
	_hud_squads.anchor_bottom = 1.0
	_hud_squads.offset_left = 16
	_hud_squads.offset_top = -190
	_hud_squads.offset_bottom = -12
	_hud_squads.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hud_squads.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_hud_squads)
	_hud_help = _make_label(15)
	_hud_help.anchor_left = 1.0
	_hud_help.anchor_right = 1.0
	_hud_help.offset_left = -600
	_hud_help.offset_right = -16
	_hud_help.offset_top = 12
	_hud_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_help.text = "분대(숫자) 좌클릭 → 칸 좌클릭: 이동\n다른 분대로 바꾸기: 그 분대 숫자 클릭\n숫자키 1~9: 분대 선택   Space: 일시정지\nF: 기술   G: 장비(전투마다 1번)   R: 집에서 회복\n우클릭 드래그 / Q,E: 회전   휠: 확대·축소\n다친 분대를 집 칸으로 보내면 집 안에서 회복(그동안 못 싸움)"
	layer.add_child(_hud_help)

	# 잠깐 떴다 사라지는 안내 문구 (예: "장비를 쓸 수 없음: 근처에 적 없음")
	_toast_label = _make_label(20)
	_toast_label.anchor_left = 1.0
	_toast_label.anchor_right = 1.0
	_toast_label.anchor_top = 1.0
	_toast_label.anchor_bottom = 1.0
	_toast_label.offset_left = -640
	_toast_label.offset_right = -16
	_toast_label.offset_top = -110
	_toast_label.offset_bottom = -76
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_label.modulate = Color(1.0, 0.75, 0.6)
	_toast_label.visible = false
	layer.add_child(_toast_label)

	# 선택한 분대의 기술/장비 버튼 (화면 아래 가운데)
	_action_box = HBoxContainer.new()
	_action_box.anchor_left = 1.0
	_action_box.anchor_right = 1.0
	_action_box.anchor_top = 1.0
	_action_box.anchor_bottom = 1.0
	_action_box.offset_left = -640
	_action_box.offset_right = -16
	_action_box.offset_top = -70
	_action_box.offset_bottom = -16
	_action_box.alignment = BoxContainer.ALIGNMENT_END  # 오른쪽 아래 (왼쪽 아래 분대 목록과 안 겹치게)
	_action_box.add_theme_constant_override("separation", 12)
	_action_box.visible = false
	layer.add_child(_action_box)
	_skill_btn = Button.new()
	_skill_btn.add_theme_font_size_override("font_size", 18)
	_skill_btn.focus_mode = Control.FOCUS_NONE
	_skill_btn.add_theme_color_override("font_disabled_color", Color(0.8, 0.8, 0.8))  # 못 쓸 때도 이유가 읽히게
	_skill_btn.pressed.connect(func(): use_skill(selected))
	_action_box.add_child(_skill_btn)
	_item_btn = Button.new()
	_item_btn.add_theme_font_size_override("font_size", 18)
	_item_btn.focus_mode = Control.FOCUS_NONE
	_item_btn.add_theme_color_override("font_disabled_color", Color(0.8, 0.8, 0.8))  # 못 쓸 때도 이유가 읽히게
	_item_btn.pressed.connect(func(): use_item(selected))
	_action_box.add_child(_item_btn)

	_result_panel = PanelContainer.new()
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -220
	_result_panel.offset_right = 220
	_result_panel.offset_top = -120
	_result_panel.offset_bottom = 120
	_result_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	_result_panel.add_child(vb)
	_result_label = _make_label(22)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_result_label)
	var btn := Button.new()
	btn.text = "계속"
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(_emit_end)
	vb.add_child(btn)
	layer.add_child(_result_panel)


func _toast(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_t = 2.0


func _update_hud() -> void:
	if _hud_top == null:
		return
	if _toast_t > 0.0:
		_toast_t -= get_process_delta_time()
		if _toast_t <= 0.0:
			_toast_label.visible = false
	var intact := 0
	for h in houses:
		if h.intact:
			intact += 1
	var wave_text := ""
	if wave_index < 0:
		wave_text = "첫 배가 %d초 뒤 출발" % int(ceil(wave_timer))
	elif wave_index < waves.size() - 1:
		wave_text = "웨이브 %d/%d   다음 웨이브까지 %d초" % [wave_index + 1, waves.size(), int(ceil(wave_timer))]
	else:
		wave_text = "마지막 웨이브 %d/%d   남은 적 %d" % [wave_index + 1, waves.size(), enemy_count()]
	var status := ""
	if paused:
		status = "   [일시정지]"
	elif selected != null:
		status = "   [분대 %d 선택 중 - 시간 느리게]" % (selected.index + 1)
	_hud_top.text = "%s (난이도 %d)%s\n%s\n집 %d/%d" % [
		str(node_info.get("name", "섬")), int(node_info.get("difficulty", 0)), status,
		wave_text, intact, houses.size()]
	var lines: PackedStringArray = []
	for s in squads:
		var c: Dictionary = s.commander
		var bar := "병사 %d/%d" % [s.units.size(), s.max_soldiers]
		var tag := "  (행군 중)" if s.marching else ""
		if s.resting:
			tag = "  (집에서 회복 중 %d%%)" % int(s.rest_progress() * 100.0) if s.units.size() < s.max_soldiers else "  (집에서 회복 중)"
		if s.is_wiped():
			bar = "전멸"
			tag = ""
		var extra := ""
		if not s.is_wiped():
			if s.has_skill():
				extra += "  기술:%s" % ("준비" if s.skill_ready() else "%d초" % int(ceil(s.skill_cd)))
			var item := str(c.get("item", ""))
			if Catalog.item_active(item):
				extra += "  %s:%s" % [Catalog.item_name(item), "사용함" if s.item_used else "준비"]
		lines.append("[%d] %s %s Lv%d  %s%s%s" % [s.index + 1, str(c.get("name", "")), UnitDefs.display_name(s.type_id()), int(c.get("level", 1)), bar, extra, tag])
	_hud_squads.text = "\n".join(lines)
	_update_action_buttons()


func _update_action_buttons() -> void:
	if selected == null or selected.is_wiped() or finished:
		_action_box.visible = false
		return
	_action_box.visible = true
	if selected.has_skill():
		_skill_btn.visible = true
		var nm := Catalog.skill_name(selected.type_id())
		var why := skill_block_reason(selected)
		_skill_btn.text = "[F] %s" % nm if why == "" else "[F] %s (%s)" % [nm, why]
		_skill_btn.disabled = why != ""
	else:
		_skill_btn.visible = false
	var item := str(selected.commander.get("item", ""))
	if Catalog.item_active(item):
		_item_btn.visible = true
		var why_i := item_block_reason(selected)
		_item_btn.text = "[G] %s" % Catalog.item_name(item) if why_i == "" else "[G] %s (%s)" % [Catalog.item_name(item), why_i]
		_item_btn.disabled = why_i != ""
	else:
		_item_btn.visible = false


func _show_result() -> void:
	var r := result
	var text := ""
	if r["won"]:
		text = "섬을 지켰습니다!\n\n지킨 집 %d/%d   골드 +%d" % [r["houses_saved"], r["houses_total"], r["gold"]]
	else:
		if intact_house_count() == 0:
			text = "집이 모두 불탔습니다.\n섬을 잃었습니다. (보상 없음)"
		else:
			text = "출전한 분대가 모두 쓰러졌습니다.\n섬을 잃었습니다. (보상 없음)"
	if not (r["wiped"] as Array).is_empty() and r["won"]:
		text += "\n\n전멸한 분대 %d개는 영영 돌아오지 않습니다." % (r["wiped"] as Array).size()
	_result_label.text = text
	_result_panel.visible = true


# ================================================================ 자동 지휘 (테스트용)

## 사람 대신 단순하게 지휘합니다: 상륙한 적 중 집에 가장 가까운 적에게 근접 분대를 보내고,
## 궁수는 그 근처 높은 칸으로 보냅니다. 적이 없으면 집으로 돌아가 회복합니다.
func _auto_command(dt: float) -> void:
	_auto_t -= dt
	if _auto_t > 0.0:
		return
	_auto_t = 2.0
	var landed: Array = []
	for u in units:
		if u.team == 1 and u.state == u.State.ACTIVE:
			landed.append(u)
	var house_list: Array = houses.filter(func(h): return h.intact)
	for s in squads:
		if s.is_wiped():
			continue
		if enemy_near(s.centroid(), 1.5):
			use_skill(s)
			var item := str(s.commander.get("item", ""))
			if item == "bomb":
				use_item(s)
			elif item == "horn" and s.units.size() * 2 < s.max_soldiers:
				use_item(s)
	for i in range(squads.size()):
		var s = squads[i]
		if s.is_wiped() or s.marching or s.resting:
			continue
		var goal := NO_CELL
		# 병사가 절반 아래로 줄었고 근처에 적이 없으면 가까운 집으로 가서 회복
		if s.units.size() * 2 < s.max_soldiers and not enemy_near(s.centroid(), 2.5):
			var hh = nearest_intact_house(s.centroid())
			if hh != null:
				if hh.cell != s.anchor_cell:
					try_order(s, hh.cell)
				else:
					rest_squad(s)
				continue
		if landed.is_empty():
			if not house_list.is_empty():
				goal = house_list[i % house_list.size()].cell
		else:
			var threat = landed[0]
			var best_d := INF
			for e in landed:
				var h = nearest_intact_house(e.position)
				var d := _flat_dist(e.position, h.position) if h != null else 0.0
				# 분대마다 조금 다른 적을 고르도록 거리 기준을 섞음
				d += _flat_dist(e.position, s.anchor_pos()) * 0.5
				if d < best_d:
					best_d = d
					threat = e
			var tc := world_to_cell(threat.position)
			if s.type_id() == "archer":
				goal = _best_archer_cell(tc)
			else:
				goal = tc
			if _flat_dist(cell_center(goal), s.anchor_pos()) < 1.2:
				goal = NO_CELL
		if goal != NO_CELL and goal != s.anchor_cell:
			if not try_order(s, goal):
				# 그 칸이 막혔으면 바로 옆 빈칸이라도
				for d in GridNav.DIRS8:
					if try_order(s, goal + d):
						break


func _best_archer_cell(near: Vector2i) -> Vector2i:
	var best := near
	var best_score := -INF
	for c in island.tiles.keys():
		var d := Vector2(c - near).length()
		if d < 1.5 or d > 3.0 or not island.is_walkable(c):
			continue
		var score := float(height_steps(c)) * 2.0 - d
		if score > best_score:
			best_score = score
			best = c
	return best
