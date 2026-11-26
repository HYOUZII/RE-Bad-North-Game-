extends RefCounted
## 섬 지형 그리기: "윗면(풀밭)은 코드로 한 장, 절벽은 바위 조각을 골라 세우기"
##
## 순서:
##   1) 높이 단계 L(1, 2, 3)마다 "높이가 L 이상인 땅"을 0/1 로 표시합니다.
##   2) 칸 중심 4개로 이루어진 작은 네모마다 안/밖 모양(16가지)을 봅니다 (마칭 스퀘어).
##      - 윗면: 안쪽 부분을 풀밭 다각형으로 깝니다. 외곽선은 칸 경계 한가운데를 지나고,
##        모서리는 45도로 깎여서 상자 모양이 아니라 둥글게 깎인 바위처럼 보입니다.
##      - 절벽: 외곽선 한 토막마다 모양에 맞는 바위 조각을 고릅니다.
##          곧은 면 → cliff / cliff_tall, 튀어나온 모서리 → cliff_corner_out,
##          파인 모서리 → cliff_corner_in, 바닷가 낮은 땅 → shore_rock
##   3) 위아래 단의 외곽선이 같은 자리면 조각 하나를 길게(두 단 높이로) 세웁니다.
##      → 얇은 줄이 겹겹이 쌓인 "등고선" 대신 큰 절벽 한 면이 됩니다.
##   4) 조각마다 크기·각도·색을 조금씩 다르게 해서 반복이 눈에 덜 띄게 합니다.
##   5) 조각 사이 틈으로 하늘이 보이지 않게 뒤에 어두운 벽(뒷벽)을 한 장 깝니다.
##
## 중요: 그림만 바뀝니다. 걷기·계단 규칙은 island_generator.gd 의 tiles/stairs 그대로입니다.

const RockKit := preload("res://scripts/island/rock_kit.gd")

const SEA_DEPTH := 0.35       # 바닷가 벽이 물속으로 내려가는 깊이
const BACK_INSET := 0.06      # 뒷벽은 외곽선보다 이만큼 안쪽
const SELF_W := 0.7           # 물결선 모양 다듬기 비중

# 색: 채도를 낮춘 풀과 모래 (눈부시지 않게)
const GRASS := Color(0.39, 0.52, 0.34)
const GRASS_HIGH := Color(0.43, 0.56, 0.37)
const SAND := Color(0.74, 0.69, 0.55)
const ROCK_ROOF := Color(0.58, 0.60, 0.57)
const BACK_WALL := Color(0.30, 0.32, 0.32)
const CAVE_DARK := Color(0.16, 0.16, 0.19)
const USE_SAND := false     # 바닷가 칸을 모래색으로 (칸 경계에서 삼각형 얼룩이 생겨서 끔)
const FOAM := Color(0.66, 0.72, 0.71)
const FOAM_ISO := 0.26       # 물결선: 섬 외곽선보다 조금 바깥(값이 작을수록 넓음)

## 동굴 지붕 칸 (지붕 윗면을 풀 대신 바위색으로 칠해서 "위로는 못 걷는 곳"이 보이게)
static var _roof: Dictionary = {}


## 섬 지형을 만들어 돌려줍니다 (Node3D 하나 아래에 윗면 메시 + 바위 조각들).
## tiles: Vector2i -> 높이 단계(1 이상), step: 한 단 높이(m), sand: 모래로 칠할 칸 -> true
## caves: 동굴 칸 -> 지붕 높이 단계. 동굴 칸의 바닥은 tiles 높이(걷는 높이)이고,
##        바닥과 지붕 사이는 비워 두고(통로), 맨 위 한 단(지붕 높이)만 바위로 채웁니다.
## stairs: 계단 자리 "x,z|x,z" 키 사전. 계단이 기대는 면에는 바위 조각을 세우지 않음(계단과 겹치지 않게)
## base: 높이 1의 실제 높이(m). 음수면 step 과 같음(예전 방식: 높이 L = L*step)
static func build(tiles: Dictionary, step: float, sand: Dictionary, caves: Dictionary = {}, stairs: Dictionary = {}, base: float = -1.0) -> Node3D:
	if base < 0.0:
		base = step
	var ly := func(l: int) -> float: return 0.0 if l <= 0 else base + float(l - 1) * step
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof = {}
	var max_h := 0
	for c in caves.keys():
		_roof[c] = int(caves[c])
		max_h = maxi(max_h, int(caves[c]))  # 동굴 지붕이 가장 높은 땅보다 높을 수도 있음
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in tiles.keys():
		max_h = maxi(max_h, int(tiles[c]))
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var root := Node3D.new()
	root.name = "IslandTerrain"
	var cliffs := Node3D.new()
	cliffs.name = "Cliffs"
	root.add_child(cliffs)
	# 단마다 0/1 표
	var solid: Array = [{}]
	for level in range(1, max_h + 2):
		solid.append(_solid(tiles, level, lo, hi, caves))
	for level in range(1, max_h + 1):
		var y_top: float = ly.call(level)
		for x in range(lo.x - 1, hi.x + 1):
			for z in range(lo.y - 1, hi.y + 1):
				var pat := _pattern(solid[level], x, z)
				if pat == 0:
					continue
				_cap(st, x, z, pat, y_top, level, sand, max_h)
				if pat == 15:
					continue
				# 바로 위 단의 모양이 똑같으면 그 단의 조각이 여기까지 길게 내려오므로 건너뜀
				if level < max_h and _pattern(solid[level + 1], x, z) == pat:
					continue
				# 같은 모양이 아래로 몇 단 이어지는지 → 조각 높이
				var k := level
				while k > 1 and _pattern(solid[k - 1], x, z) == pat:
					k -= 1
				var y_bot: float = ly.call(k - 1) if k > 1 else -SEA_DEPTH
				for seg in _segments(x, z, pat):
					_back_wall(st, seg, y_top, y_bot)
					if _on_stairs(seg, stairs):
						continue
					_place_piece(cliffs, seg, pat, level, k, y_top, y_bot, tiles)
	# 동굴: 통로 천장(아래를 보는 어두운 면)과 어두운 바닥
	for c in caves.keys():
		var floor_y: float = ly.call(int(tiles[c]))
		var ceil_y: float = ly.call(int(caves[c]) - 1) - 0.005
		var r := 0.45
		var sq: Array = [Vector2(c.x - r, c.y - r), Vector2(c.x + r, c.y - r), Vector2(c.x + r, c.y + r), Vector2(c.x - r, c.y + r)]
		for k in [[0, 1, 2], [0, 2, 3]]:
			for i in k:
				st.set_color(CAVE_DARK)
				st.set_normal(Vector3.DOWN)
				st.add_vertex(Vector3(sq[i].x, ceil_y, sq[i].y))
		for k in [[0, 1, 2], [0, 2, 3]]:
			for i in k:
				st.set_color(GRASS.darkened(0.35))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(sq[i].x, floor_y + 0.004, sq[i].y))
	# 해안 물결선: 섬보다 조금 넓은 띠를 수면 바로 위에 깔고, 섬이 그 위를 덮음
	var f1 := _field(tiles, lo, hi)
	for x in range(lo.x - 1, hi.x + 1):
		for z in range(lo.y - 1, hi.y + 1):
			_foam(st, f1, x, z)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 면 방향과 상관없이 보이게 (빛 방향은 직접 정함)
	mi.material_override = mat
	root.add_child(mi)
	return root


## 높이 level 이상인 칸 (동굴은 지붕 한 단만 바위)
static func _solid(tiles: Dictionary, level: int, lo: Vector2i, hi: Vector2i, caves: Dictionary) -> Dictionary:
	var out := {}
	for c in tiles.keys():
		var on := int(tiles[c]) >= level
		if caves.has(c) and level == int(caves[c]):
			on = true
		if on:
			out[c] = true
	return out


## 네모 (x,z) 의 모양 번호: 꼭짓점 0 왼쪽 위(x,z) 1 오른쪽 위(x+1,z) 2 오른쪽 아래(x+1,z+1) 3 왼쪽 아래(x,z+1)
static func _pattern(s: Dictionary, x: int, z: int) -> int:
	var p := 0
	if s.has(Vector2i(x, z)):
		p |= 1
	if s.has(Vector2i(x + 1, z)):
		p |= 2
	if s.has(Vector2i(x + 1, z + 1)):
		p |= 4
	if s.has(Vector2i(x, z + 1)):
		p |= 8
	return p


static func _corners(x: int, z: int) -> Array[Vector2]:
	return [Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]


static func _inside(pat: int, i: int) -> bool:
	return (pat >> i) & 1 == 1


## 변 i(꼭짓점 i → i+1)의 가운데 점
static func _mid(cs: Array[Vector2], i: int) -> Vector2:
	return (cs[i] + cs[(i + 1) % 4]) * 0.5


## 윗면: 안쪽 꼭짓점과 경계 가운데 점을 차례로 이은 다각형
## (대각선 두 꼭짓점만 안쪽인 "안장" 모양은 가운데가 이어진 것으로 봄 → 길이 끊기지 않음)
static func _cap(st: SurfaceTool, x: int, z: int, pat: int, y: float, level: int, sand: Dictionary, max_h: int) -> void:
	var cs := _corners(x, z)
	var poly: Array[Vector2] = []
	for i in range(4):
		if _inside(pat, i):
			poly.append(cs[i])
		if _inside(pat, i) != _inside(pat, (i + 1) % 4):
			poly.append(_mid(cs, i))
	if poly.size() < 3:
		return
	for k in range(1, poly.size() - 1):
		for p in [poly[0], poly[k], poly[k + 1]]:
			st.set_color(_ground_color(p, level, sand, max_h))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.y))


## 외곽선 토막들: [시작점, 끝점, 바깥 방향(단위 벡터), 안쪽 꼭짓점 수]
static func _segments(x: int, z: int, pat: int) -> Array:
	var cs := _corners(x, z)
	var n_in := 0
	for i in range(4):
		if _inside(pat, i):
			n_in += 1
	var out: Array = []
	if n_in == 2 and pat != 5 and pat != 10:
		# 곧은 면: 경계가 지나는 두 변의 가운데 점을 이음. 바깥 = 바깥 꼭짓점 두 개 쪽
		var pts: Array[Vector2] = []
		var out_ref := Vector2.ZERO
		for i in range(4):
			if _inside(pat, i) != _inside(pat, (i + 1) % 4):
				pts.append(_mid(cs, i))
			if not _inside(pat, i):
				out_ref += cs[i] * 0.5
		out.append([pts[0], pts[1], _outward(pts[0], pts[1], out_ref), 2])
		return out
	for i in range(4):
		var a := _mid(cs, (i + 3) % 4)
		var b := _mid(cs, i)
		if n_in == 1 and _inside(pat, i):
			# 튀어나온 모서리: 안쪽 꼭짓점 하나를 비스듬히 감쌈. 바깥 = 반대편 꼭짓점 쪽
			out.append([a, b, _outward(a, b, cs[(i + 2) % 4]), 1])
		elif n_in != 1 and not _inside(pat, i):
			# 파인 모서리(안쪽 셋) 또는 안장 모양: 바깥 꼭짓점마다 비스듬한 토막
			out.append([a, b, _outward(a, b, cs[i]), n_in])
	return out


static func _outward(a: Vector2, b: Vector2, out_ref: Vector2) -> Vector2:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	if n.dot(out_ref - (a + b) * 0.5) < 0.0:
		n = -n
	return n


## 계단이 기대는 면인가: 토막 양 끝(칸 경계 가운데)이 계단 경계면
static func _on_stairs(seg: Array, stairs: Dictionary) -> bool:
	if stairs.is_empty():
		return false
	for p in [seg[0], seg[1]]:
		var v: Vector2 = p
		# 가운데 점이 칸 경계 위: x 가 .5 면 좌우 두 칸, z 가 .5 면 위아래 두 칸
		var a: Vector2i
		var b: Vector2i
		if absf(v.x - round(v.x)) > 0.25:
			a = Vector2i(int(floor(v.x)), int(round(v.y)))
			b = a + Vector2i(1, 0)
		else:
			a = Vector2i(int(round(v.x)), int(floor(v.y)))
			b = a + Vector2i(0, 1)
		if stairs.has(_edge_key(a, b)):
			return true
	return false


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## 조각 하나 세우기
static func _place_piece(parent: Node3D, seg: Array, pat: int, level: int, k: int, y_top: float, y_bot: float, tiles: Dictionary) -> void:
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var outward: Vector2 = seg[2]
	var n_in: int = seg[3]
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var kind := "cliff"
	if level == 1:
		kind = "shore_rock"
	elif n_in == 1:
		kind = "cliff_corner_out"
	elif n_in == 3 or pat == 5 or pat == 10:
		kind = "cliff_corner_in"
	elif level - k >= 1:
		kind = "cliff_tall"
	var pick := _hash_i(mid)
	var rnd := _hash01(mid * 1.7)
	var height := y_top - y_bot
	var piece := Assets.get_rock_piece(kind, pick, Vector3(length, height, RockKit.FRONT_OUT + RockKit.BACK_IN))
	# 크기·각도 변화: 가로는 넓게(겹치게)만, 높이는 맨 위가 풀밭보다 올라가지 않게 아래로만 줄임
	var sx := 1.0 + rnd * 0.12
	var sz := 0.85 + _hash01(mid * 3.3) * 0.35
	piece.scale = Vector3(sx, 1.0, sz)
	piece.position = Vector3(mid.x, y_bot, mid.y)
	piece.rotation.y = atan2(-outward.x, -outward.y) + (rnd - 0.5) * 0.12
	piece.name = "Rock_%s_%d" % [kind, pick % 1000]
	# 조각마다 색을 아주 조금 다르게
	var tint := Vector3(1, 1, 1) * (0.92 + _hash01(mid * 5.1) * 0.14)
	_set_tint(piece, tint)
	parent.add_child(piece)


static func _set_tint(n: Node, tint: Vector3) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("tint", tint)
	for c in n.get_children():
		_set_tint(c, tint)


## 뒷벽: 외곽선보다 조금 안쪽에 세우는 어두운 판 (조각 사이 틈 가림)
static func _back_wall(st: SurfaceTool, seg: Array, y_top: float, y_bot: float) -> void:
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	var outward: Vector2 = seg[2]
	var ia := a - outward * BACK_INSET
	var ib := b - outward * BACK_INSET
	var n := Vector3(outward.x, 0.0, outward.y)
	var top := y_top - 0.03
	for tri in [[Vector3(ia.x, top, ia.y), Vector3(ib.x, top, ib.y), Vector3(ib.x, y_bot, ib.y)], [Vector3(ia.x, top, ia.y), Vector3(ib.x, y_bot, ib.y), Vector3(ia.x, y_bot, ia.y)]]:
		for p in tri:
			st.set_color(BACK_WALL)
			st.set_normal(n)
			st.add_vertex(p)


static func _ground_color(p: Vector2, level: int, sand: Dictionary, max_h: int) -> Color:
	var cell := Vector2i(int(round(p.x)), int(round(p.y)))
	var n := _smooth_noise(p * 0.45) * 0.7 + _hash01(p * 3.1) * 0.3  # 큰 얼룩 + 아주 약한 잔무늬
	if _roof.has(cell) and level >= int(_roof[cell]):
		return ROCK_ROOF.lerp(ROCK_ROOF.darkened(0.15), n)
	if level == 1 and USE_SAND and sand.has(cell):
		return SAND.lerp(SAND.darkened(0.08), n)
	var base := GRASS.lerp(GRASS_HIGH, float(level - 1) / maxf(1.0, float(max_h - 1)))
	return base.lerp(base.darkened(0.1), n)


## 물결선용 부드러운 값 (칸 값 + 이웃 평균)
static func _field(tiles: Dictionary, lo: Vector2i, hi: Vector2i) -> Dictionary:
	var f := {}
	for x in range(lo.x - 1, hi.x + 2):
		for z in range(lo.y - 1, hi.y + 2):
			var c := Vector2i(x, z)
			var s := 0.0
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if (dx != 0 or dz != 0) and tiles.has(Vector2i(x + dx, z + dz)):
						s += 1.0
			var v := (1.0 if tiles.has(c) else 0.0) * SELF_W + (s / 8.0) * (1.0 - SELF_W)
			f[c] = v
	return f


## 물결선 한 네모 (수면 바로 위 흰 띠)
static func _foam(st: SurfaceTool, f: Dictionary, x: int, z: int) -> void:
	var cs := _corners(x, z)
	var vals: Array[float] = []
	for c in cs:
		vals.append(float(f.get(Vector2i(c), 0.0)))
	var poly: Array[Vector2] = []
	for i in range(4):
		var j := (i + 1) % 4
		if vals[i] > FOAM_ISO:
			poly.append(cs[i])
		if (vals[i] > FOAM_ISO) != (vals[j] > FOAM_ISO):
			var t := (FOAM_ISO - vals[i]) / (vals[j] - vals[i])
			poly.append(cs[i].lerp(cs[j], t))
	if poly.size() < 3:
		return
	for k in range(1, poly.size() - 1):
		for p in [poly[0], poly[k], poly[k + 1]]:
			st.set_color(FOAM)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.035, p.y))


## 부드러운 값 노이즈 (0~1). 이웃 점끼리 값이 비슷해서 큰 얼룩이 됨
static func _smooth_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash01(i)
	var b := _hash01(i + Vector2(1, 0))
	var c := _hash01(i + Vector2(0, 1))
	var d := _hash01(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _hash_i(p: Vector2) -> int:
	return int(_hash01(p * 0.917 + Vector2(3.1, 7.7)) * 100000.0)


static func _hash01(p: Vector2) -> float:
	var h := sin(p.x * 127.1 + p.y * 311.7) * 43758.5453
	return h - floor(h)
