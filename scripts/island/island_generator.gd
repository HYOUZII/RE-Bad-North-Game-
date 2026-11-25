extends Node3D
## 절차적 섬 생성기
##
## 1) 노이즈로 높이를 정하고 가장자리로 갈수록 낮춰서 섬 모양을 만듭니다.
## 2) 높이가 다른 칸 사이는 모두 "절벽"이라 걸어서 넘을 수 없습니다.
## 3) 같은 높이로 이어진 땅(고원)끼리 "계단"을 몇 군데만 놓아 길을 만듭니다.
##    → 병사는 계단과 평지로만 돌아서 이동하므로, 계단이 길목(요충지)이 됩니다.
## 4) 바위 칸은 아무도 지나갈 수 없습니다(길을 막아 길목을 더 만듦).
##
## tiles 사전: Vector2i(x, z) -> 높이(1 이상의 정수). 높이 0 이하는 바다라서 저장하지 않습니다.
## stairs 사전: 계단이 놓인 두 칸 묶음 키("x,z|x,z") -> true
## blocked 사전: 바위가 있어 못 지나가는 칸 -> true

@export var radius: int = 10
@export var max_height: int = 4
@export var tile_size: float = 1.0
@export var step_height: float = 0.5  # 높이 1단계당 실제 높이(m)

const GRASS := Color(0.49, 0.69, 0.41)
const SAND := Color(0.86, 0.80, 0.60)
const ROCK := Color(0.55, 0.55, 0.58)
const TerrainBuilder := preload("res://scripts/island/terrain_builder.gd")
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tiles: Dictionary = {}
var stairs: Dictionary = {}
var blocked: Dictionary = {}
var house_cells: Array[Vector2i] = []

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int, house_count: int = 3) -> void:
	for c in get_children():
		c.queue_free()
	tiles.clear()
	stairs.clear()
	blocked.clear()
	house_cells.clear()
	_rng.seed = seed_value

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.11
	var shape := FastNoiseLite.new()
	shape.seed = seed_value + 77
	shape.frequency = 0.12

	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			# 해안선을 울퉁불퉁하게: 거리에 노이즈를 섞음
			var d := Vector2(x, z).length() / float(radius) + shape.get_noise_2d(x, z) * 0.18
			if d > 1.0:
				continue
			var n := (noise.get_noise_2d(x, z) + 1.0) * 0.5  # 0~1
			var v := n * 1.25 - d * d * 0.9 + 0.35
			var h := clampi(int(round(v * max_height)), 1, max_height)
			if d > 0.9:
				h = 1  # 바깥 테두리는 낮은 땅(상륙 가능한 해변)
			tiles[Vector2i(x, z)] = h

	_smooth_plateaus()
	_connect_with_stairs()
	_place_rocks(radius / 2 + 1)
	_build_tiles()
	_place_houses(house_count)
	_place_trees(4 + radius / 2)


# ================================================================ 이동 규칙 (길찾기에서 사용)

static func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


func is_walkable(c: Vector2i) -> bool:
	return tiles.has(c) and not blocked.has(c)


func has_stairs(a: Vector2i, b: Vector2i) -> bool:
	return stairs.has(edge_key(a, b))


## 옆 칸(상하좌우)으로 걸어서 갈 수 있는가: 같은 높이이거나 계단이 있어야 함
func can_cross(a: Vector2i, b: Vector2i) -> bool:
	if not is_walkable(a) or not is_walkable(b):
		return false
	if int(tiles[a]) == int(tiles[b]):
		return true
	return has_stairs(a, b)


## 격자 좌표 -> 월드 좌표 (타일 윗면 중앙)
func cell_to_world(cell: Vector2i) -> Vector3:
	var h: int = tiles.get(cell, 0)
	return Vector3(cell.x * tile_size, h * step_height, cell.y * tile_size)


## 실제 지면 높이. 계단이 있는 칸은 계단 쪽으로 갈수록 경사를 따라 올라갑니다.
func ground_height(p: Vector3) -> float:
	var c := Vector2i(int(round(p.x)), int(round(p.z)))
	if not tiles.has(c):
		return 0.0
	var h := float(int(tiles[c]))
	for d in DIRS4:
		var n: Vector2i = c + d
		if tiles.has(n) and int(tiles[n]) > int(tiles[c]) and has_stairs(c, n):
			# 칸 중심 0 → 경계 0.5 까지 경사
			var t: float = (p.x - c.x) * d.x + (p.z - c.y) * d.y
			if t > 0.0:
				h += (float(int(tiles[n])) - h) * clamp(t / 0.5, 0.0, 1.0)
	return h * step_height


## 바다와 맞닿은 칸
func get_shore_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in tiles.keys():
		for dir in DIRS4:
			if not tiles.has(cell + dir):
				result.append(cell)
				break
	return result


## 배가 댈 수 있는 해변 = 높이 1인 해안 칸 (바위 제외)
func get_beach_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in get_shore_cells():
		if int(tiles[c]) == 1 and not blocked.has(c):
			result.append(c)
	return result


# ================================================================ 지형 다듬기

## 주변과 높이가 다른 외톨이 칸을 주변 높이로 맞춰서 넓은 고원을 만듭니다.
func _smooth_plateaus() -> void:
	for _pass in range(3):
		var changes := {}
		for c in tiles.keys():
			var counts := {}
			for d in DIRS4:
				var n: Vector2i = c + d
				if tiles.has(n):
					counts[tiles[n]] = int(counts.get(tiles[n], 0)) + 1
			var same := int(counts.get(tiles[c], 0))
			if same <= 1:
				var best_h = tiles[c]
				var best_n := 0
				for k in counts.keys():
					if int(counts[k]) > best_n:
						best_n = counts[k]
						best_h = k
				changes[c] = best_h
		for c in changes.keys():
			tiles[c] = changes[c]


## 같은 높이로 이어진 덩어리(고원)마다 번호를 붙입니다.
func _regions() -> Dictionary:
	var region := {}
	var next := 0
	for start in tiles.keys():
		if region.has(start):
			continue
		var h: int = tiles[start]
		var stack: Array[Vector2i] = [start]
		region[start] = next
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in DIRS4:
				var n: Vector2i = c + d
				if tiles.has(n) and not region.has(n) and int(tiles[n]) == h:
					region[n] = next
					stack.append(n)
		next += 1
	return region


## 고원끼리 계단으로 연결합니다. 모든 땅이 한 덩어리로 이어지도록(신장 트리) 하고, 고리 몇 개를 더 만듭니다.
func _connect_with_stairs() -> void:
	for _attempt in range(max_height + 2):
		stairs.clear()
		var region := _regions()
		# 고원 쌍마다 계단 후보(높이 차이 1인 경계)
		var cands := {}
		for c in tiles.keys():
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if not tiles.has(n):
					continue
				var ra: int = region[c]
				var rb: int = region[n]
				if ra == rb or abs(int(tiles[c]) - int(tiles[n])) != 1:
					continue
				var key := "%d-%d" % [min(ra, rb), max(ra, rb)]
				if not cands.has(key):
					cands[key] = {"a": min(ra, rb), "b": max(ra, rb), "edges": []}
				cands[key]["edges"].append([c, n])
		var pairs: Array = cands.values()
		_shuffle(pairs)
		# 경계가 긴 쌍을 먼저 (자연스러운 큰 길)
		pairs.sort_custom(func(p, q): return p["edges"].size() > q["edges"].size())
		var parent := {}
		var find := func(x):
			while parent.get(x, x) != x:
				x = parent[x]
			return x
		var extra: Array = []
		for p in pairs:
			var ra = find.call(p["a"])
			var rb = find.call(p["b"])
			if ra != rb:
				parent[ra] = rb
				_add_stair(p["edges"])
			else:
				extra.append(p)
		# 고리 몇 개 (길이 하나뿐이면 너무 답답하므로)
		for p in extra:
			if _rng.randf() < 0.3:
				_add_stair(p["edges"])
		# 모두 이어졌는지 확인, 안 이어진 고원은 한 단 낮춰서 다시 시도
		var reach := _flood(_center_cell())
		var unreached: Array = tiles.keys().filter(func(c): return not reach.has(c))
		if unreached.is_empty():
			return
		for c in unreached:
			if int(tiles[c]) > 1:
				tiles[c] = int(tiles[c]) - 1
	# 그래도 못 가는 칸은 바다로
	var reach_final := _flood(_center_cell())
	for c in tiles.keys():
		if not reach_final.has(c):
			tiles.erase(c)


func _add_stair(edges: Array) -> void:
	var e: Array = edges[_rng.randi_range(0, edges.size() - 1)]
	stairs[edge_key(e[0], e[1])] = true


func _center_cell() -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := INF
	for c in tiles.keys():
		var d := Vector2(c).length()
		if d < best_d:
			best_d = d
			best = c
	return best


func _flood(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in DIRS4:
			var n: Vector2i = c + d
			if not seen.has(n) and can_cross(c, n):
				seen[n] = true
				queue.append(n)
	return seen


## 바위: 길을 끊지 않는 곳에만 놓습니다.
func _place_rocks(count: int) -> void:
	var shore := get_shore_cells()
	var cells: Array = tiles.keys()
	_shuffle(cells)
	var placed := 0
	for c in cells:
		if placed >= count:
			break
		if c in shore or _touches_stairs(c):
			continue
		blocked[c] = true
		var start: Vector2i = _center_cell() if c != _center_cell() else c + Vector2i(1, 0)
		if not is_walkable(start):
			blocked.erase(c)
			continue
		var walkable := 0
		for t in tiles.keys():
			if is_walkable(t):
				walkable += 1
		if _flood(start).size() < walkable:
			blocked.erase(c)  # 이 바위가 길을 끊으면 취소
			continue
		placed += 1


func _touches_stairs(c: Vector2i) -> bool:
	for d in DIRS4:
		if has_stairs(c, c + d):
			return true
	return false


# ================================================================ 그리기

func _build_tiles() -> void:
	# 칸 색 (지형 조각 .glb가 없을 때 쓰는 상자 색)
	var shore := get_shore_cells()
	var colors := {}
	for cell in tiles.keys():
		var h: int = tiles[cell]
		var color := GRASS
		if h == 1 and cell in shore:
			color = SAND
		elif h >= max_height:
			color = GRASS.darkened(0.12)
		colors[cell] = color
	# 그리기만 terrain_builder 가 맡음. 이동 규칙(tiles·stairs)은 그대로.
	TerrainBuilder.build(self, tiles, step_height, stairs, colors)
	for cell in blocked.keys():
		var rock := Assets.get_model("rock")
		rock.position = cell_to_world(cell)
		rock.rotation.y = _rng.randf() * TAU
		add_child(rock)
	# 계단: 낮은 칸 쪽 절반에 경사로를 놓음
	for key in stairs.keys():
		var parts: PackedStringArray = str(key).split("|")
		var a := _parse_cell(parts[0])
		var b := _parse_cell(parts[1])
		var low := a if int(tiles[a]) < int(tiles[b]) else b
		var high := b if low == a else a
		var dir := Vector2(high - low)
		var st := Assets.get_model("stairs")
		var base := cell_to_world(low)
		# 낮은 칸의 높은 칸 쪽 절반에 반 단짜리 디딤돌을 놓아 계단처럼 보이게 함
		st.position = base + Vector3(dir.x * 0.25, 0.0, dir.y * 0.25)
		st.rotation.y = atan2(-dir.x, -dir.y)
		add_child(st)


func _parse_cell(s: String) -> Vector2i:
	var p := s.split(",")
	return Vector2i(int(p[0]), int(p[1]))


## 집 위치만 정합니다. 집 모델과 체력은 전투(battle.gd)가 만듭니다.
func _place_houses(count: int) -> void:
	var shore := get_shore_cells()
	var candidates: Array = tiles.keys().filter(func(c): return is_walkable(c) and not (c in shore) and not _touches_stairs(c))
	_shuffle(candidates)
	for min_gap in [4, 3, 2, 1]:
		for cell in candidates:
			if house_cells.size() >= count:
				return
			if cell in house_cells:
				continue
			var ok := true
			for hc in house_cells:
				if abs(hc.x - cell.x) + abs(hc.y - cell.y) < min_gap:
					ok = false
					break
			if ok:
				house_cells.append(cell)


func _place_trees(count: int) -> void:
	var placed := 0
	var cells: Array = tiles.keys()
	for i in range(count * 4):
		if placed >= count:
			break
		var cell: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
		if cell in house_cells or blocked.has(cell) or _touches_stairs(cell):
			continue
		var tree := Assets.get_model("tree")
		tree.position = cell_to_world(cell) + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
		add_child(tree)
		placed += 1


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
