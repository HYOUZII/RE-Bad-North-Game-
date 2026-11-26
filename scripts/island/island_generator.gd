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
## caves 사전: 동굴 통로 칸 -> 지붕 높이. 이 칸의 tiles 높이는 "통로 바닥" 높이라서
##   양쪽 입구와 같은 높이로 걸어 지나갑니다(이동 규칙은 그대로). 지붕은 그림일 뿐 위로는 못 걷습니다.

@export var radius: int = 10
@export var max_height: int = 3       # 땅 높이 단계 수 (1 = 바닷가 낮은 땅, 2·3 = 절벽 위 고원)
@export var tile_size: float = 1.0
@export var step_height: float = 1.0  # 절벽 한 단의 높이(m). 단 수를 줄인 대신 절벽 하나하나를 높게
@export var level_base: float = 0.3   # 높이 1(바닷가 땅)의 높이(m). 물 바로 위에 낮게 깔린 땅

const GRASS := Color(0.49, 0.69, 0.41)
const SAND := Color(0.86, 0.80, 0.60)
const ROCK := Color(0.55, 0.55, 0.58)
const TerrainBuilder := preload("res://scripts/island/terrain_builder.gd")
const MAX_CAVE_LEN := 5  # 동굴 통로 최대 길이(칸)
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var tiles: Dictionary = {}
var stairs: Dictionary = {}
var blocked: Dictionary = {}
var caves: Dictionary = {}
var house_cells: Array[Vector2i] = []

var _rng := RandomNumberGenerator.new()


func generate(seed_value: int, house_count: int = 3) -> void:
	for c in get_children():
		c.queue_free()
	tiles.clear()
	stairs.clear()
	blocked.clear()
	caves.clear()
	house_cells.clear()
	_rng.seed = seed_value

	_make_layout(seed_value)
	_smooth_plateaus()
	_carve_caves(1 + (1 if _rng.randf() < 0.35 else 0))
	_connect_with_stairs()
	_check_caves()
	_place_rocks(radius / 2 + 1)
	_build_tiles()
	_place_houses(house_count)
	_place_trees(4 + radius / 2)
	_place_bushes()


# ================================================================ 섬 모양 (배치)
## 섬 모양 만들기. 칸 하나하나를 따로 정하지 않고 "덩어리"로 정합니다.
##   1) 땅/바다: 둥근 모양을 노이즈로 비틀고, 주변 칸 다수결로 다듬어 해안선을 매끈하게
##   2) 고원(높이 2): 섬 가운데 쪽 + 큰 노이즈 점수가 높은 칸의 절반쯤. 가는 띠·한 칸 홈은 지움
##   3) 봉우리(높이 3): 고원 안에서 다시 점수가 높은 칸 일부
## 높이는 1~3 세 단뿐이라 계단식 등고선처럼 보이지 않고, 넓은 평지 + 높은 절벽이 됩니다.
func _make_layout(seed_value: int) -> void:
	var warp := FastNoiseLite.new()
	warp.seed = seed_value + 11
	warp.frequency = 0.09
	var shape := FastNoiseLite.new()
	shape.seed = seed_value + 77
	shape.frequency = 0.09
	var hill := FastNoiseLite.new()
	hill.seed = seed_value
	hill.frequency = 0.075
	var coast := FastNoiseLite.new()
	coast.seed = seed_value + 303
	coast.frequency = 0.1
	var r := float(radius)
	# 1) 땅/바다
	var land := {}
	for x in range(-radius - 2, radius + 3):
		for z in range(-radius - 2, radius + 3):
			var p := Vector2(x, z)
			var w := Vector2(warp.get_noise_2d(x, z), warp.get_noise_2d(x + 97.0, z - 61.0)) * 4.0
			# 각도마다 반지름을 다르게 해서 곶과 만이 생기게 (원·팔각형처럼 보이지 않게)
			var ang := atan2(float(z), float(x))
			var lobes := sin(ang * 3.0 + float(seed_value % 7)) * 0.12 + sin(ang * 5.0 + float(seed_value % 11)) * 0.07
			var d := (p + w).length() / r * (1.0 - lobes) + shape.get_noise_2d(x, z) * 0.3
			if d < 0.9:
				land[Vector2i(x, z)] = true
	land = _majority(land, 3, {})
	land = _largest_part(land)
	land = _fill_holes(land)
	# 2) 고원 점수: 가운데일수록 + 큰 언덕 노이즈
	var score := {}
	for c in land.keys():
		var centr := 1.0 - Vector2(c).length() / r
		score[c] = centr * 0.8 + hill.get_noise_2d(c.x, c.y) * 0.7
	# 바닷가 한 칸 띠는 대부분 낮은 땅으로 남김(배가 댈 곳). 일부(coast 노이즈가 큰 곳)만 바다 절벽 허용
	var inner := _erode(land)
	var allow2 := {}
	for c in land.keys():
		if inner.has(c) or coast.get_noise_2d(c.x, c.y) > 0.3:
			allow2[c] = true
	var lv2 := _top_share(score, allow2, 0.5)
	lv2 = _majority(lv2, 2, allow2)
	lv2 = _open_close(lv2, allow2)
	# 3) 봉우리: 고원 안 점수 상위. 고원 가장자리에 붙으면 2단 높이 큰 절벽이 생김
	var lv3 := _top_share(score, lv2, 0.38)
	lv3 = _majority(lv3, 2, lv2)
	lv3 = _open_close(lv3, lv2)
	for c in land.keys():
		var h := 1
		if lv2.has(c):
			h = 2
			if lv3.has(c) and max_height >= 3:
				h = 3
		tiles[c] = h


## 점수 상위 share 비율의 칸 (allowed 안에서만)
func _top_share(score: Dictionary, allowed: Dictionary, share: float) -> Dictionary:
	var cells: Array = allowed.keys()
	if cells.is_empty():
		return {}
	cells.sort_custom(func(a, b): return float(score.get(a, -9.0)) > float(score.get(b, -9.0)))
	var out := {}
	for i in range(int(round(cells.size() * share))):
		out[cells[i]] = true
	return out


## 주변 8칸 다수결로 모양 다듬기 (튀어나온 한 칸, 파인 한 칸이 사라짐). allowed 가 비어 있지 않으면 그 안에서만 땅
func _majority(mask: Dictionary, passes: int, allowed: Dictionary) -> Dictionary:
	var m := mask
	for _i in range(passes):
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := Vector2i(-(1 << 20), -(1 << 20))
		for c in m.keys():
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		var out := {}
		for x in range(lo.x - 1, hi.x + 2):
			for z in range(lo.y - 1, hi.y + 2):
				var c := Vector2i(x, z)
				var n := 0
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						if (dx != 0 or dz != 0) and m.has(Vector2i(x + dx, z + dz)):
							n += 1
				var on := m.has(c)
				if n >= 5:
					on = true
				elif n <= 3:
					on = false
				if on and (allowed.is_empty() or allowed.has(c)):
					out[c] = true
		m = out
	return m


## 한 칸 깎기: 상하좌우가 모두 안쪽인 칸만 남김
func _erode(mask: Dictionary) -> Dictionary:
	var out := {}
	for c in mask.keys():
		var ok := true
		for d in DIRS4:
			if not mask.has(c + d):
				ok = false
				break
		if ok:
			out[c] = true
	return out


## 한 칸 넓히기 (allowed 안에서만)
func _dilate(mask: Dictionary, allowed: Dictionary) -> Dictionary:
	var out := mask.duplicate()
	for c in mask.keys():
		for d in DIRS4:
			var n: Vector2i = c + d
			if allowed.has(n):
				out[n] = true
	return out


## 열기(깎고 넓히기: 두 칸보다 가는 띠 제거) → 닫기(넓히고 깎기: 한 칸짜리 홈 메움)
func _open_close(mask: Dictionary, allowed: Dictionary) -> Dictionary:
	var m := _dilate(_erode(mask), allowed)
	var closed := _erode(_dilate(m, allowed))
	# 닫기 때 allowed 바깥 경계에서 깎인 칸은 되살림
	for c in m.keys():
		closed[c] = true
	return closed


## 가장 큰 덩어리만 남김 (떨어진 작은 섬 제거)
func _largest_part(mask: Dictionary) -> Dictionary:
	var seen := {}
	var best := {}
	for start in mask.keys():
		if seen.has(start):
			continue
		var part := {start: true}
		seen[start] = true
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in DIRS4:
				var n: Vector2i = c + d
				if mask.has(n) and not seen.has(n):
					seen[n] = true
					part[n] = true
					stack.append(n)
		if part.size() > best.size():
			best = part
	return best


## 땅으로 둘러싸인 호수(바깥 바다와 안 이어진 물)는 땅으로 메움
func _fill_holes(mask: Dictionary) -> Dictionary:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in mask.keys():
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i(1, 1)
	hi += Vector2i(1, 1)
	var sea := {lo: true}
	var stack: Array[Vector2i] = [lo]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS4:
			var n: Vector2i = c + d
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y:
				continue
			if not mask.has(n) and not sea.has(n):
				sea[n] = true
				stack.append(n)
	var out := mask.duplicate()
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c := Vector2i(x, z)
			if not sea.has(c):
				out[c] = true
	return out


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


## 높이 단계 → 실제 높이(m). 높이 1은 물 바로 위(level_base), 그 위로 한 단마다 step_height.
func level_y(h: float) -> float:
	if h <= 0.0:
		return 0.0
	return level_base + (h - 1.0) * step_height


## 격자 좌표 -> 월드 좌표 (타일 윗면 중앙)
func cell_to_world(cell: Vector2i) -> Vector3:
	var h: int = tiles.get(cell, 0)
	return Vector3(cell.x * tile_size, level_y(h), cell.y * tile_size)


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
	return level_y(h)


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
				if caves.has(c) or caves.has(n):
					continue  # 동굴 안에는 계단 없음 (지붕에 머리가 닿음)
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
		# 경계가 긴 고원 사이에는 계단을 더 놓음 (한 군데만 있으면 너무 멀리 돌아가야 함)
		for p in pairs:
			var edges: Array = p["edges"]
			for _k in range(edges.size() / 10):
				_add_stair_far(edges)
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


## 동굴: 두 낮은 땅 사이를 가로막은 두꺼운 바위(높이가 입구보다 2단 이상 높음)를 뚫어 통로를 만듭니다.
## 통로 칸 높이를 입구 높이로 낮추고(걸을 수 있게), 원래 높이는 지붕 높이로 caves 에 적어 둡니다.
## 통로 양옆은 입구보다 높아야 합니다(옆으로 새지 않는 굴). 동굴 칸에는 계단을 놓지 않습니다.
func _carve_caves(max_count: int) -> void:
	var found: Array = []
	for start in tiles.keys():
		var floor_h := int(tiles[start])
		for d in DIRS4:
			# start(입구) → 통로 1~MAX_CAVE_LEN칸 → 반대쪽 입구(같은 높이)
			var run: Array[Vector2i] = []
			var c: Vector2i = start + d
			var ok := false
			while run.size() < MAX_CAVE_LEN and tiles.has(c):
				var h := int(tiles[c])
				if h == floor_h and run.size() > 0:
					ok = true
					break
				if h < floor_h + 1:
					break
				var side := Vector2i(d.y, d.x)
				if int(tiles.get(c + side, 0)) <= floor_h or int(tiles.get(c - side, 0)) <= floor_h:
					break
				run.append(c)
				c += d
			if ok:
				found.append({"run": run, "floor": floor_h})
	_shuffle(found)
	var made := 0
	for f in found:
		if made >= max_count:
			break
		var run: Array = f["run"]
		var clash := false
		for c in run:
			for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if caves.has(c + d):
					clash = true
		if clash:
			continue
		for c in run:
			# 지붕 높이 = 원래 높이. 한 단 높은 고원을 뚫으면 지붕 윗면이 고원과 같은 높이(얇은 지붕, cliff_mesh ROOF_T)
			caves[c] = int(tiles[c])
			tiles[c] = int(f["floor"])  # 걷는 높이 = 입구 높이
		made += 1


## 계단 연결 과정에서 높이가 바뀌어 동굴 조건이 깨지면 지붕을 없앰.
## 조건: 지붕이 바닥보다 2단 이상 높고, 통로 "양옆"(통로 방향과 직각인 두 칸)이 모두 바닥보다 높아야 함.
## 한 칸이라도 깨지면 그 동굴(이어진 동굴 칸 전체)을 통째로 없앰 → 반쪽짜리 지붕이 공중에 뜨지 않게.
func _check_caves() -> void:
	var done := {}
	for start in caves.keys():
		if done.has(start):
			continue
		var comp: Array[Vector2i] = [start]
		done[start] = true
		var i := 0
		while i < comp.size():
			for d in DIRS4:
				var n: Vector2i = comp[i] + d
				if caves.has(n) and not done.has(n):
					done[n] = true
					comp.append(n)
			i += 1
		var bad := false
		for c in comp:
			if not tiles.has(c) or int(caves[c]) < int(tiles[c]) + 1:
				bad = true
				break
			# 통로 방향: 옆 동굴 칸이 있는 쪽. 한 칸짜리면 양옆이 높은 쪽을 통로 방향으로 봄
			var along_x := caves.has(c + Vector2i(1, 0)) or caves.has(c - Vector2i(1, 0))
			var along_z := caves.has(c + Vector2i(0, 1)) or caves.has(c - Vector2i(0, 1))
			var fl := int(tiles[c])
			var walls_x := int(tiles.get(c + Vector2i(0, 1), 0)) > fl and int(tiles.get(c - Vector2i(0, 1), 0)) > fl
			var walls_z := int(tiles.get(c + Vector2i(1, 0), 0)) > fl and int(tiles.get(c - Vector2i(1, 0), 0)) > fl
			if along_x and not walls_x:
				bad = true
			elif along_z and not walls_z:
				bad = true
			elif not along_x and not along_z and not (walls_x or walls_z):
				bad = true
		if bad:
			for c in comp:
				caves.erase(c)


## 동굴 입구(동굴 칸 바로 옆 칸)인가
func _near_cave(c: Vector2i) -> bool:
	for d in DIRS4:
		if caves.has(c + d):
			return true
	return false


## 이미 놓인 계단에서 가장 먼 경계에 계단 하나 더
func _add_stair_far(edges: Array) -> void:
	var best: Array = []
	var best_d := -1.0
	for e in edges:
		var d := INF
		for key in stairs.keys():
			var parts: PackedStringArray = str(key).split("|")
			var q := _parse_cell(parts[0])
			d = minf(d, Vector2(e[0] - q).length())
		if d > best_d:
			best_d = d
			best = e
	if best.is_empty() or best_d < 4.0:
		return
	stairs[edge_key(best[0], best[1])] = true


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
		if c in shore or _touches_stairs(c) or caves.has(c) or _near_cave(c):  # 입구를 막으면 막다른 굴이 됨
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
	TerrainBuilder.build(self, tiles, step_height, stairs, colors, caves, level_base)
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
		st.scale.y = (level_y(int(tiles[high])) - level_y(int(tiles[low]))) / 0.5  # 계단 모델은 한 단 0.5m 기준이라 단 높이에 맞춰 늘림
		add_child(st)


func _parse_cell(s: String) -> Vector2i:
	var p := s.split(",")
	return Vector2i(int(p[0]), int(p[1]))


## 집 위치만 정합니다. 집 모델과 체력은 전투(battle.gd)가 만듭니다.
func _place_houses(count: int) -> void:
	var shore := get_shore_cells()
	var candidates: Array = tiles.keys().filter(func(c): return is_walkable(c) and not (c in shore) and not _touches_stairs(c) and not caves.has(c) and not _near_cave(c))
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
		if cell in house_cells or blocked.has(cell) or _touches_stairs(cell) or caves.has(cell):
			continue
		var tree := Assets.get_model("tree")
		tree.position = cell_to_world(cell) + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
		add_child(tree)
		placed += 1


## 덤불: 절벽 아래(옆 칸이 더 높은 곳)와 해안에 조금씩. 장식이라 지나갈 수 있음.
func _place_bushes() -> void:
	for c in tiles.keys():
		if c in house_cells or blocked.has(c) or caves.has(c):
			continue
		for d in DIRS4:
			var n: Vector2i = c + d
			var cliff := int(tiles.get(n, 0)) > int(tiles[c]) and not has_stairs(c, n)
			var coast := not tiles.has(n) and _rng.randf() < 0.25
			if not (cliff or coast) or _rng.randf() > 0.55:
				continue
			for _k in range(_rng.randi_range(1, 3)):
				var b := Assets.get_model("bush")
				var along := _rng.randf_range(-0.4, 0.4)
				var off := Vector3(d.x, 0, d.y) * (0.2 if cliff else 0.18) + Vector3(d.y, 0, d.x) * along
				b.position = cell_to_world(c) + off
				var sc := _rng.randf_range(0.7, 1.3)
				b.scale = Vector3(sc, sc * _rng.randf_range(0.8, 1.1), sc)
				add_child(b)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
