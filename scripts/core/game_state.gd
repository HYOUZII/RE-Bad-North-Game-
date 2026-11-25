extends Node
## 원정(한 판의 로그라이크 진행) 상태 (자동 로드 이름: Game)
##
## - roster: 살아 있는 지휘관 목록. 분대가 전멸하면 그 지휘관은 영영 사라집니다(퍼마데스).
## - gold: 섬을 지키고 받은 골드. 지휘관 승급/레벨업에 씁니다.
## - map_nodes: 캠페인 지도의 섬들. 왼쪽에서 오른쪽으로 나아가며, 맨 끝 섬을 지키면 승리.
## - 골드 쓰는 곳: 레벨업, 민병 승급, 병종 기술 배우기, 장비 사기, 지휘관 고용 (가격은 catalog.gd)
## - 한 섬에는 최대 4명까지 출전. 나머지는 쉬면서 기다립니다.
## 화면은 changed 신호를 받아 다시 그립니다.

signal changed

const UnitDefs := preload("res://scripts/battle/unit_defs.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const COLUMNS := 7               # 지도 열 수 (마지막 열 = 최종 섬)
const MAX_LEVEL := 4
const MAX_ROSTER := 6
const MAX_DEPLOY := 4            # 한 섬에 데려갈 수 있는 최대 분대 수
const SHOP_SIZE := 3             # 섬을 지킬 때마다 상점에 새로 들어오는 장비 수
const PROMOTE_COST := 4          # 민병 → 병종 승급 비용
const BASE_SOLDIERS := 6         # 레벨 1 분대 = 6 + 1 = 7명

const COMMANDER_NAMES := ["하랑", "도윤", "서진", "이안", "무열", "청아", "단비", "가온", "루다", "태오", "미르", "소을", "윤슬", "새봄"]
const ISLAND_NAMES := ["안개곶", "갈매기섬", "붉은바위", "소금언덕", "바람목", "등대섬", "검은모래", "이끼섬", "고래등", "서리곶", "외딴섬", "솔숲섬", "물새목", "조약돌섬", "마지막 성채"]

var gold := 0
var roster: Array = []           # [{id, name, cls, level, skill, item}]
var deploy_ids: Array = []       # 다음 전투에 출전할 지휘관 id
var inventory: Array = []        # 아직 아무에게도 달지 않은 장비 id
var shop: Array = []             # 상점에서 팔고 있는 장비 id
var map_nodes: Array = []        # [{id, col, row, rows, name, difficulty, seed, radius, houses, links, recruit, final, cleared}]
var current_node := -1           # 마지막으로 지킨 섬 (-1 = 출발 전)
var run_seed := 0
var run_over := false
var run_won := false
var islands_cleared := 0

var _next_cid := 1
var _name_pool: Array = []
var _ai_request := -1


func new_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	gold = 0
	roster.clear()
	current_node = -1
	run_over = false
	run_won = false
	islands_cleared = 0
	_next_cid = 1
	_name_pool = COMMANDER_NAMES.duplicate()
	_shuffle(_name_pool, rng)
	for cls in UnitDefs.PLAYER_CLASSES:
		_add_commander(cls)
	inventory.clear()
	deploy_ids.clear()
	for c in roster:
		deploy_ids.append(c["id"])
	_build_map(rng)
	_refresh_shop(rng)
	_request_island_names()
	changed.emit()


# ---------------------------------------------------------------- 지휘관

func _add_commander(cls: String) -> Dictionary:
	var nm: String = _name_pool.pop_back() if not _name_pool.is_empty() else "지휘관%d" % _next_cid
	var c := {"id": _next_cid, "name": nm, "cls": cls, "level": 1, "skill": false, "item": ""}
	_next_cid += 1
	roster.append(c)
	if deploy_ids.size() < MAX_DEPLOY:
		deploy_ids.append(c["id"])
	return c


func find_commander(cid: int) -> Dictionary:
	for c in roster:
		if int(c["id"]) == cid:
			return c
	return {}


func soldiers_for(c: Dictionary) -> int:
	return BASE_SOLDIERS + int(c.get("level", 1)) + (2 if c.get("item", "") == "banner" else 0)


func hp_mult(c: Dictionary) -> float:
	return (1.0 + 0.15 * float(int(c.get("level", 1)) - 1)) * (1.3 if c.get("item", "") == "armor" else 1.0)


func speed_mult(c: Dictionary) -> float:
	return 1.3 if c.get("item", "") == "boots" else 1.0


func dmg_mult(c: Dictionary) -> float:
	return 1.0 + 0.10 * float(int(c.get("level", 1)) - 1)


func level_cost(c: Dictionary) -> int:
	return 5 * int(c.get("level", 1))


func can_level_up(c: Dictionary) -> bool:
	return str(c["cls"]) != "militia" and int(c["level"]) < MAX_LEVEL and gold >= level_cost(c)


func level_up(cid: int) -> bool:
	var c := find_commander(cid)
	if c.is_empty() or not can_level_up(c):
		return false
	gold -= level_cost(c)
	c["level"] = int(c["level"]) + 1
	changed.emit()
	return true


func can_promote(c: Dictionary) -> bool:
	return str(c["cls"]) == "militia" and gold >= PROMOTE_COST


func promote(cid: int, cls: String) -> bool:
	var c := find_commander(cid)
	if c.is_empty() or not can_promote(c) or not (cls in UnitDefs.PLAYER_CLASSES):
		return false
	gold -= PROMOTE_COST
	c["cls"] = cls
	changed.emit()
	return true


# ---------------------------------------------------------------- 기술, 장비, 고용, 출전

func can_buy_skill(c: Dictionary) -> bool:
	return Catalog.SKILLS.has(str(c["cls"])) and not bool(c.get("skill", false)) and gold >= Catalog.SKILL_COST


func buy_skill(cid: int) -> bool:
	var c := find_commander(cid)
	if c.is_empty() or not can_buy_skill(c):
		return false
	gold -= Catalog.SKILL_COST
	c["skill"] = true
	changed.emit()
	return true


func can_buy_item(item: String) -> bool:
	return item in shop and gold >= Catalog.ITEM_COST


func buy_item(item: String) -> bool:
	if not can_buy_item(item):
		return false
	gold -= Catalog.ITEM_COST
	shop.erase(item)
	inventory.append(item)
	changed.emit()
	return true


## 창고의 장비를 지휘관에게 답니다. 한 번 달면 뗄 수 없습니다.
func equip(cid: int, item: String) -> bool:
	var c := find_commander(cid)
	if c.is_empty() or str(c.get("item", "")) != "" or not (item in inventory):
		return false
	inventory.erase(item)
	c["item"] = item
	changed.emit()
	return true


func can_recruit() -> bool:
	return roster.size() < MAX_ROSTER and gold >= Catalog.RECRUIT_COST


func recruit() -> bool:
	if not can_recruit():
		return false
	gold -= Catalog.RECRUIT_COST
	_add_commander("militia")
	changed.emit()
	return true


func is_deployed(cid: int) -> bool:
	return cid in deploy_ids


func toggle_deploy(cid: int) -> void:
	if cid in deploy_ids:
		if deploy_ids.size() > 1:
			deploy_ids.erase(cid)
	elif deploy_ids.size() < MAX_DEPLOY:
		deploy_ids.append(cid)
	changed.emit()


## 이번 전투에 나갈 지휘관 목록 (지도 화면에서 고른 순서대로)
func deployed_commanders() -> Array:
	var out: Array = []
	for c in roster:
		if c["id"] in deploy_ids:
			out.append(c)
	if out.is_empty() and not roster.is_empty():
		out.append(roster[0])
	return out


func _refresh_shop(rng: RandomNumberGenerator = null) -> void:
	var ids: Array = Catalog.ITEMS.keys()
	shop.clear()
	# 겹치지 않게 SHOP_SIZE개 뽑기
	for _i in range(min(SHOP_SIZE, ids.size())):
		var k: int = rng.randi_range(0, ids.size() - 1) if rng != null else randi() % ids.size()
		shop.append(ids[k])
		ids.remove_at(k)


# ---------------------------------------------------------------- 지도

func _build_map(rng: RandomNumberGenerator) -> void:
	map_nodes.clear()
	var names: Array = ISLAND_NAMES.duplicate()
	names.pop_back()  # 마지막 이름은 최종 섬 전용
	_shuffle(names, rng)
	var cols: Array = []
	var nid := 0
	for col in range(COLUMNS):
		var count := 1 if (col == 0 or col == COLUMNS - 1) else rng.randi_range(2, 3)
		var ids: Array = []
		for row in range(count):
			var final := col == COLUMNS - 1
			var difficulty := col
			var node := {
				"id": nid, "col": col, "row": row, "rows": count,
				"name": ISLAND_NAMES[-1] if final else str(names[nid % names.size()]),
				"difficulty": difficulty,
				"seed": rng.randi_range(1, 1 << 30),
				"radius": clampi(9 + difficulty / 2, 9, 12),
				"houses": clampi(4 + difficulty / 2 + rng.randi_range(0, 1), 4, 7),
				"links": [],
				"recruit": (not final) and col >= 1 and rng.randf() < 0.4,
				"final": final,
				"cleared": false,
				"lost": false,
			}
			map_nodes.append(node)
			ids.append(nid)
			nid += 1
		cols.append(ids)
	# 다음 열과 잇기: 세로 위치가 가까운 섬 1~2개
	for col in range(COLUMNS - 1):
		var here: Array = cols[col]
		var nxt: Array = cols[col + 1]
		for id in here:
			var y := _row_pos(map_nodes[id])
			var sorted := nxt.duplicate()
			sorted.sort_custom(func(a, b): return abs(_row_pos(map_nodes[a]) - y) < abs(_row_pos(map_nodes[b]) - y))
			map_nodes[id]["links"].append(sorted[0])
			if sorted.size() > 1 and rng.randf() < 0.6:
				map_nodes[id]["links"].append(sorted[1])
		# 들어오는 길이 없는 섬이 없게
		for t in nxt:
			var has_in := false
			for id in here:
				if t in map_nodes[id]["links"]:
					has_in = true
			if not has_in:
				var best = here[0]
				for id in here:
					if abs(_row_pos(map_nodes[id]) - _row_pos(map_nodes[t])) < abs(_row_pos(map_nodes[best]) - _row_pos(map_nodes[t])):
						best = id
				map_nodes[best]["links"].append(t)


## 열 안에서의 세로 위치 (0~1)
func _row_pos(node: Dictionary) -> float:
	return (float(node["row"]) + 0.5) / float(node["rows"])


func reachable_nodes() -> Array:
	if run_over:
		return []
	if current_node < 0:
		return map_nodes.filter(func(n): return int(n["col"]) == 0).map(func(n): return n["id"])
	return map_nodes[current_node]["links"].duplicate()


# ---------------------------------------------------------------- 전투 결과

func apply_battle_result(node_id: int, result: Dictionary) -> void:
	var wiped: Array = result.get("wiped", [])
	roster = roster.filter(func(c): return not (c["id"] in wiped))
	deploy_ids = deploy_ids.filter(func(id): return not (id in wiped))
	if roster.is_empty():
		run_over = true
		run_won = false
		changed.emit()
		return
	if deploy_ids.is_empty():
		for c in roster:
			if deploy_ids.size() < MAX_DEPLOY:
				deploy_ids.append(c["id"])
	if not bool(result.get("won", false)):
		# 섬을 잃음(집이 모두 불탔거나 출전 분대 전멸): 골드·보상 없이 그 섬을 지나 다음으로.
		# 같은 섬을 다시 시도할 수는 없고, 마지막 섬을 잃으면 원정 실패.
		var lost_node: Dictionary = map_nodes[node_id]
		lost_node["lost"] = true
		current_node = node_id
		if bool(lost_node["final"]):
			run_over = true
			run_won = false
		changed.emit()
		return
	gold += int(result.get("gold", 0))
	var node: Dictionary = map_nodes[node_id]
	node["cleared"] = true
	current_node = node_id
	islands_cleared += 1
	if bool(node["recruit"]) and roster.size() < MAX_ROSTER:
		_add_commander("militia")
	_refresh_shop()
	if bool(node["final"]):
		run_over = true
		run_won = true
	changed.emit()


# ---------------------------------------------------------------- AI로 섬 이름 짓기 (선택)

## AI가 켜져 있으면 섬 이름을 새로 지어 달라고 부탁합니다. 꺼져 있거나 실패하면 기본 이름 그대로.
func _request_island_names() -> void:
	if not AI.is_enabled():
		return
	if not AI.response_received.is_connected(_on_ai_names):
		AI.response_received.connect(_on_ai_names)
	var count := map_nodes.size() - 1
	_ai_request = AI.ask(
		"바다 위 작은 섬 %d개의 한국어 이름을 지어 줘. 각 이름은 2~5글자. JSON 문자열 배열만 출력해." % count,
		"너는 판타지 전술 게임의 지명 작가야. 설명 없이 JSON만 답해.")


func _on_ai_names(request_id: int, text: String) -> void:
	if request_id != _ai_request:
		return
	var start := text.find("[")
	var end := text.rfind("]")
	if start < 0 or end <= start:
		return
	var data = JSON.parse_string(text.substr(start, end - start + 1))
	if typeof(data) != TYPE_ARRAY:
		return
	var i := 0
	for node in map_nodes:
		if bool(node["final"]) or i >= data.size():
			continue
		var nm := str(data[i]).strip_edges()
		if nm.length() >= 1 and nm.length() <= 8:
			node["name"] = nm
		i += 1
	changed.emit()


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
