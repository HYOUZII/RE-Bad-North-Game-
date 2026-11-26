extends RefCounted
## 섬 지형을 "한 덩어리 바위"처럼 그리는 메시 생성기 (칸 상자 대신)
##
## 생각 방식:
##   높이 단계 L(1, 2, 3 …)마다 "높이가 L 이상인 땅"의 모양을 구합니다.
##   그 모양의 윗면(풀밭)을 높이 L*step 에 깔고, 둘레를 따라 한 단짜리 바위 벽을 세웁니다.
##   높은 단의 벽이 낮은 단 위에 차곡차곡 쌓이면 절벽이 한 덩어리로 이어져 보입니다.
##
## 외곽선을 부드럽게 만드는 방법 (마칭 스퀘어):
##   1) 칸마다 "안쪽 정도" 값을 정합니다. 안쪽이면 1, 바깥이면 0 인데, 이웃 8칸 평균을 조금 섞어서
##      모서리 칸은 값이 조금 작아집니다 → 외곽선이 모서리에서 둥글게 깎입니다.
##   2) 칸 중심 4개를 꼭짓점으로 하는 작은 네모마다 값이 0.5 가 되는 곳을 이어서 외곽선을 그립니다.
##   3) 외곽선 점은 위치에 따라 살짝 흔들어서(노이즈) 자로 그은 듯한 느낌을 없앱니다.
##
## 중요: 그림만 바뀝니다. 걷기·계단 규칙은 island_generator.gd 의 tiles/stairs 그대로입니다.

const SELF_W := 0.7          # 칸 자신의 값 비중 (나머지는 이웃 평균). 작을수록 더 둥글지만 좁은 능선이 얇아짐
const JITTER := 0.07         # 외곽선 흔들림(m)
const WALL_BULGE := 0.13     # 벽 기둥마다 안쪽으로 들어가는 깊이(최대, m). 바위가 세로 판자처럼 갈라져 보이게
const SLAB_W := 0.34         # 바위 기둥 한 개의 대략 폭(m)
const LIP := 0.07            # 윗면 가장자리를 비스듬히 깎는 높이(m). 풀밭 테두리가 둥글게 보임
const SEA_DEPTH := 0.35      # 바닷가 벽이 물속으로 내려가는 깊이

# 색: 밝은 파스텔 풀 + 흰빛 바위. 바위 면의 명암은 주로 햇빛 방향이 만듦
const GRASS := Color(0.49, 0.71, 0.46)
const GRASS_HIGH := Color(0.55, 0.76, 0.51)
const SAND := Color(0.86, 0.80, 0.62)
const ROCK := Color(0.82, 0.84, 0.82)
const ROCK_DARK := Color(0.60, 0.63, 0.63)
const CAVE_DARK := Color(0.22, 0.22, 0.26)

## 동굴 지붕 칸 (지붕 윗면을 풀 대신 바위색으로 칠해서 "위로는 못 걷는 곳"이 보이게)
static var _roof: Dictionary = {}
const FOAM := Color(0.93, 0.95, 0.94)
const FOAM_ISO := 0.16       # 물결선: 섬 외곽선보다 조금 바깥(값이 작을수록 넓음)


## 섬 지형 메시 하나를 만들어 돌려줍니다.
## tiles: Vector2i -> 높이 단계(1 이상), step: 한 단 높이(m), sand: 모래로 칠할 칸 -> true
## caves: 동굴 칸 -> 지붕 높이 단계. 동굴 칸의 바닥은 tiles 높이(걷는 높이)이고,
##        바닥과 지붕 사이는 비워 두고(통로), 맨 위 한 단(지붕 높이)만 바위로 채웁니다.
##        예) 바닥 1, 지붕 4 → 2·3단은 뚫린 통로(높이 1.6m), 4단은 지붕.
## stairs: 계단 자리 "x,z|x,z" 키 사전. 계단이 놓인 곳은 절벽 면이 정확히 두 칸 경계에 오게 맞춤(계단이 벽에 딱 붙도록)
static func build(tiles: Dictionary, step: float, sand: Dictionary, caves: Dictionary = {}, stairs: Dictionary = {}) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof = {}
	for c in caves.keys():
		_roof[c] = int(caves[c])  # 이 높이의 윗면은 지붕
	var max_h := 0
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in tiles.keys():
		max_h = maxi(max_h, int(tiles[c]))
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	for level in range(1, max_h + 1):
		var field := _field(tiles, level, lo, hi, caves)
		_pin_stairs(field, tiles, stairs, level)
		var y_top := level * step
		var y_bot := (level - 1) * step if level > 1 else -SEA_DEPTH
		# 칸 중심 4개로 이루어진 네모 (왼쪽 위 칸 = (x, z))
		for x in range(lo.x - 1, hi.x + 1):
			for z in range(lo.y - 1, hi.y + 1):
				_square(st, field, x, z, level, y_top, y_bot, sand, max_h)
	# 동굴: 통로 천장(아래를 보는 어두운 면)과 어두운 바닥
	for c in caves.keys():
		var floor_y := int(tiles[c]) * step
		var ceil_y := (int(caves[c]) - 1) * step - 0.005
		# 둥글게 깎인 벽/지붕 안쪽에 숨도록 칸보다 조금 작게 (1칸 그대로면 지붕 밖으로 검은 조각이 삐져나옴)
		var r := 0.36
		var sq: Array = [Vector2(c.x - r, c.y - r), Vector2(c.x + r, c.y - r), Vector2(c.x + r, c.y + r), Vector2(c.x - r, c.y + r)]
		for k in [[0, 1, 2], [0, 2, 3]]:
			for i in k:
				st.set_color(CAVE_DARK)
				st.set_normal(Vector3.DOWN)
				st.add_vertex(Vector3(sq[i].x, ceil_y, sq[i].y))
		for k in [[0, 1, 2], [0, 2, 3]]:
			for i in k:
				st.set_color(GRASS.darkened(0.3))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(sq[i].x, floor_y + 0.004, sq[i].y))
	# 해안 물결선: 섬보다 조금 넓은 흰 띠를 수면 바로 위에 깔고, 섬이 그 위를 덮음
	var f1 := _field(tiles, 1, lo, hi, caves)
	for x in range(lo.x - 1, hi.x + 1):
		for z in range(lo.y - 1, hi.y + 1):
			_square(st, f1, x, z, 1, 0.035, 0.0, sand, max_h, FOAM_ISO, true)
	var mi := MeshInstance3D.new()
	mi.name = "IslandTerrain"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 면 방향과 상관없이 보이게 (빛 방향은 아래에서 직접 정함)
	mi.material_override = mat
	return mi


## 계단 양쪽 칸 값을 1과 0으로 고정 → 외곽선이 두 칸 사이 한가운데(칸 경계)를 지나감
static func _pin_stairs(f: Dictionary, tiles: Dictionary, stairs: Dictionary, level: int) -> void:
	for key in stairs.keys():
		var parts: PackedStringArray = str(key).split("|")
		var pa := parts[0].split(",")
		var pb := parts[1].split(",")
		var a := Vector2i(int(pa[0]), int(pa[1]))
		var b := Vector2i(int(pb[0]), int(pb[1]))
		var high := a if int(tiles.get(a, 0)) > int(tiles.get(b, 0)) else b
		var low := b if high == a else a
		if int(tiles.get(high, 0)) == level and f.has(high) and f.has(low):
			f[high] = 1.0
			f[low] = 0.0


## 칸마다 "높이 level 이상인 땅의 안쪽 정도" (0~1)
static func _field(tiles: Dictionary, level: int, lo: Vector2i, hi: Vector2i, caves: Dictionary = {}) -> Dictionary:
	var ind := {}
	for x in range(lo.x - 2, hi.x + 3):
		for z in range(lo.y - 2, hi.y + 3):
			var c := Vector2i(x, z)
			var h := int(tiles.get(c, 0))
			var solid := h >= level
			if caves.has(c) and level == int(caves[c]):
				solid = true  # 동굴 지붕 (맨 위 한 단)
			ind[c] = 1.0 if solid else 0.0
	var f := {}
	for x in range(lo.x - 1, hi.x + 2):
		for z in range(lo.y - 1, hi.y + 2):
			var c := Vector2i(x, z)
			var s := 0.0
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx != 0 or dz != 0:
						s += float(ind[Vector2i(x + dx, z + dz)])
			var v: float = float(ind[c]) * SELF_W + (s / 8.0) * (1.0 - SELF_W)
			# 진짜 땅 칸은 반드시 안쪽(0.5 초과), 바다/낮은 칸은 반드시 바깥이 되게 → 칸 중심이 뒤집히지 않음
			if ind[c] > 0.5:
				v = maxf(v, 0.55)
			else:
				v = minf(v, 0.45)
			f[c] = v
	return f


## 네모 하나: 안쪽 부분 윗면 + 외곽선 벽
static func _square(st: SurfaceTool, f: Dictionary, x: int, z: int, level: int, y_top: float, y_bot: float, sand: Dictionary, max_h: int, iso: float = 0.5, foam: bool = false) -> void:
	# 꼭짓점 순서: 왼쪽 위(x,z) → 오른쪽 위(x+1,z) → 오른쪽 아래(x+1,z+1) → 왼쪽 아래(x,z+1)
	var cs: Array[Vector2i] = [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
	var vals: Array[float] = []
	var any_in := false
	var all_in := true
	for c in cs:
		var v: float = f.get(c, 0.0)
		vals.append(v)
		if v > iso:
			any_in = true
		else:
			all_in = false
	if not any_in:
		return
	# 변 위의 교차점 (값이 0.5 가 되는 곳)
	var cross := {}
	for i in range(4):
		var j := (i + 1) % 4
		if (vals[i] > iso) != (vals[j] > iso):
			var t := (iso - vals[i]) / (vals[j] - vals[i])
			var p := Vector2(cs[i]).lerp(Vector2(cs[j]), t)
			cross[i] = _jitter(p)
	# 1) 윗면: 꼭짓점과 교차점을 차례로 이은 다각형 (안장 모양이면 둘로 나눔)
	var polys: Array = []
	var inside_n := 0
	for v in vals:
		if v > iso:
			inside_n += 1
	var saddle := inside_n == 2 and (vals[0] > iso) == (vals[2] > iso)
	var center_in := (vals[0] + vals[1] + vals[2] + vals[3]) * 0.25 > iso
	if saddle and not center_in:
		for i in [0, 2] if vals[0] > iso else [1, 3]:
			var prev: int = (int(i) + 3) % 4
			polys.append([cross[prev], Vector2(cs[i]), cross[i]])
	else:
		var poly: Array = []
		for i in range(4):
			if vals[i] > iso:
				poly.append(Vector2(cs[i]))
			if cross.has(i):
				poly.append(cross[i])
		polys.append(poly)
	for poly in polys:
		_cap(st, poly, y_top, level, sand, max_h, foam)
	if foam:
		return  # 물결선은 바닥 면만
	# 2) 벽: 외곽선 조각마다 (안쪽이 왼쪽에 오도록 방향을 맞춰) 한 단짜리 바위 벽
	if all_in:
		return
	# 조각마다 [시작점, 끝점, 땅 쪽 기준점]
	var segs: Array = []
	var center := Vector2(x + 0.5, z + 0.5)
	if saddle:
		for i in range(4):
			if center_in and vals[i] <= iso:
				# 가운데가 이어짐: 바깥 꼭짓점 i 만 잘라냄 → 땅은 네모 가운데 쪽
				segs.append([cross[(i + 3) % 4], cross[i], center])
			elif not center_in and vals[i] > iso:
				# 떨어진 두 조각: 안쪽 꼭짓점 i 둘레만 땅
				segs.append([cross[i], cross[(i + 3) % 4], Vector2(cs[i])])
	else:
		var pts: Array = []
		var ref := Vector2.ZERO
		var n_in := 0
		for i in range(4):
			if cross.has(i):
				pts.append(cross[i])
			if vals[i] > iso:
				ref += Vector2(cs[i])
				n_in += 1
		segs.append([pts[0], pts[1], ref / float(n_in)])
	for sg in segs:
		_wall(st, sg[0], sg[1], y_top, y_bot, sg[2])


static func _cap(st: SurfaceTool, poly: Array, y: float, level: int, sand: Dictionary, max_h: int, foam: bool = false) -> void:
	if poly.size() < 3:
		return
	for k in range(1, poly.size() - 1):
		# Godot 은 위에서 볼 때 시계 방향이 앞면 → 0, k, k+1 순서
		for p in [poly[0], poly[k], poly[k + 1]]:
			st.set_color(FOAM if foam else _ground_color(p, level, sand, max_h))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.y))


static func _ground_color(p: Vector2, level: int, sand: Dictionary, max_h: int) -> Color:
	var cell := Vector2i(int(round(p.x)), int(round(p.y)))
	var n := _hash01(p * 3.1)
	if _roof.has(cell) and level >= int(_roof[cell]):
		return ROCK.lerp(ROCK_DARK, 0.3 * n)
	if level == 1 and sand.has(cell):
		return SAND.lerp(SAND.darkened(0.08), n)
	var base := GRASS.lerp(GRASS_HIGH, float(level - 1) / maxf(1.0, float(max_h - 1)))
	return base.lerp(base.darkened(0.1), n)


## 벽 한 조각 (a~b 선분). inside_ref 쪽이 땅(안쪽).
## 선분을 폭 SLAB_W 정도의 기둥 여러 개로 나누고, 기둥마다 안쪽으로 들어간 깊이를 다르게 해서
## 세로로 갈라진 바위 느낌을 냅니다. 맨 위는 비스듬히 깎아(LIP) 풀밭 테두리가 둥글게 보이게 합니다.
static func _wall(st: SurfaceTool, a: Vector2, b: Vector2, y_top: float, y_bot: float, inside_ref: Vector2) -> void:
	var d := (b - a)
	var length := d.length()
	if length < 0.0001:
		return
	var inward := Vector2(-d.y, d.x) / length
	if inward.dot(inside_ref - (a + b) * 0.5) < 0.0:
		# 바깥에서 봤을 때 면이 앞을 보도록 a, b 를 바꿈
		var tmp := a
		a = b
		b = tmp
		d = b - a
		inward = -inward
	var outward := Vector3(-inward.x, 0.0, -inward.y)
	var y_lip := y_top - minf(LIP, (y_top - y_bot) * 0.3)
	var n_cols := maxi(1, int(round(length / SLAB_W)))
	var prev_inset := 0.0
	for j in range(n_cols):
		var p0 := a.lerp(b, float(j) / n_cols)
		var p1 := a.lerp(b, float(j + 1) / n_cols)
		# 기둥 깊이: 위치로 정해지는 값이라 매번 같은 모양
		var inset := WALL_BULGE * (0.15 + 0.85 * _hash01((p0 + p1) * 2.3))
		var shade := 0.25 * _hash01((p0 + p1) * 5.7)  # 기둥마다 아주 조금 다른 밝기
		var top_c := ROCK.lerp(ROCK_DARK, shade)
		var bot_c := ROCK_DARK.lerp(ROCK, shade * 0.5)
		var q0 := p0 + inward * inset
		var q1 := p1 + inward * inset
		# 기둥 앞면 (y_lip ~ y_bot)
		_quad(st, Vector3(q0.x, y_lip, q0.y), Vector3(q1.x, y_lip, q1.y), Vector3(q1.x, y_bot, q1.y), Vector3(q0.x, y_bot, q0.y), top_c, bot_c, outward)
		# 비스듬한 윗 테두리 (외곽선 → 기둥 앞면 위)
		var lip_n := (outward * (y_top - y_lip) + Vector3.UP * inset).normalized()
		_quad(st, Vector3(p0.x, y_top, p0.y), Vector3(p1.x, y_top, p1.y), Vector3(q1.x, y_lip, q1.y), Vector3(q0.x, y_lip, q0.y), ROCK, top_c, lip_n)
		# 앞 기둥과의 단차 (옆면 + 테두리 틈 메우기)
		var side_dir := Vector3(d.x, 0.0, d.y).normalized()
		var side_n := -side_dir if inset > prev_inset else side_dir
		var e0 := p0 + inward * prev_inset
		_quad(st, Vector3(e0.x, y_lip, e0.y), Vector3(q0.x, y_lip, q0.y), Vector3(q0.x, y_bot, q0.y), Vector3(e0.x, y_bot, e0.y), top_c, bot_c, side_n)
		_tri(st, [Vector3(p0.x, y_top, p0.y), Vector3(e0.x, y_lip, e0.y), Vector3(q0.x, y_lip, q0.y)], [ROCK, top_c, top_c], lip_n)
		prev_inset = inset
	# 마지막 기둥 끝 → 외곽선 끝점까지 닫기 (이웃 벽 조각과 틈이 안 보이게)
	var eb := b + inward * prev_inset
	var side_dir2 := Vector3(d.x, 0.0, d.y).normalized()
	_quad(st, Vector3(eb.x, y_lip, eb.y), Vector3(b.x, y_lip, b.y), Vector3(b.x, y_bot, b.y), Vector3(eb.x, y_bot, eb.y), ROCK_DARK, ROCK_DARK, side_dir2)
	_tri(st, [Vector3(b.x, y_top, b.y), Vector3(eb.x, y_lip, eb.y), Vector3(b.x, y_lip, b.y)], [ROCK, ROCK, ROCK], side_dir2)


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, c_top: Color, c_bot: Color, n: Vector3) -> void:
	_tri(st, [p0, p3, p2], [c_top, c_bot, c_bot], n)
	_tri(st, [p0, p2, p1], [c_top, c_bot, c_top], n)


static func _tri(st: SurfaceTool, pts: Array, cols: Array, n: Vector3) -> void:
	for i in range(3):
		st.set_color(cols[i])
		st.set_normal(n)
		st.add_vertex(pts[i])


## 같은 자리는 항상 같은 만큼 흔들림 (이웃 네모와 점이 어긋나지 않게)
static func _jitter(p: Vector2) -> Vector2:
	var key := Vector2(snappedf(p.x, 0.001), snappedf(p.y, 0.001))
	var jx := _hash01(key) * 2.0 - 1.0
	var jz := _hash01(key + Vector2(17.3, 5.1)) * 2.0 - 1.0
	return p + Vector2(jx, jz) * JITTER


static func _hash01(p: Vector2) -> float:
	var h := sin(p.x * 127.1 + p.y * 311.7) * 43758.5453
	return h - floor(h)
