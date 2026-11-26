extends RefCounted
## 섬 타일 그리기 담당 (전투 섬, 본 섬 공용)
##
## 칸마다 "흙기둥(상자) + 맨 위 지형 조각" 으로 그립니다.
## - 지형 조각: assets/models/terrain/ 폴더의 .glb (만, 곶, 협곡 등). 없으면 상자만 그림(예전 모습 그대로).
## - 절벽 벽: assets/models/terrace.glb 가 있으면 절벽 면마다 한 단씩 붙임.
##
## 중요: 여기서 그리는 것은 "보이는 모습"뿐입니다. 어디로 걸어갈 수 있는지는
## 여전히 island_generator.gd 의 tiles / stairs 표가 정합니다(같은 높이 또는 계단으로만 이동).
## 그래서 모델 모양이 달라도 이동 규칙은 절대 바뀌지 않습니다.
##
## 칸 모양 판정 (위에서 내려다볼 때, 이웃 칸이 더 낮거나 바다면 그 쪽이 "열린 면"):
##   flat    열린 면 없음 (평지)
##   bay     열린 면은 없지만 대각선 한쪽이 낮음 (안쪽으로 파인 모서리, 만)
##   canyon  열린 면 없고 마주 보는 두 이웃이 더 높음 (협곡 바닥)
##   edge    열린 면 1개 (곧은 절벽/해안)
##   corner  이웃한 열린 면 2개 (바깥 모서리)
##   narrow  마주 보는 열린 면 2개 (좁은 능선)
##   cape    열린 면 3개 (곶, 튀어나온 끝)
##   islet   열린 면 4개 (외딴 기둥)
##   beach   높이 1인 바닷가 칸 (파일이 있을 때만, 바다 쪽이 -Z)

## 방향 순서: 북(-Z) → 서(-X) → 남(+Z) → 동(+X). 모델을 +90도 돌리면 한 칸씩 다음 방향으로 감.
const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]

## 각 모양의 "기본 방향"에서 열린 면 번호(SIDES 기준). 모델 파일은 이 방향으로 만들면 됨.
const CANON := {
	"edge": [0],          # 북쪽(-Z)이 절벽
	"corner": [0, 1],     # 북·서쪽(-Z, -X)이 절벽
	"narrow": [0, 2],     # 북·남쪽이 절벽
	"cape": [0, 1, 3],    # 북·서·동이 절벽, 끝이 북쪽(-Z)을 가리킴
	"islet": [0, 1, 2, 3],
}

const CliffMesh := preload("res://scripts/island/cliff_mesh.gd")

## 그리는 방식: "smooth" = 윗면은 한 장, 절벽은 바위 조각을 골라 세움(cliff_mesh.gd + rock_kit.gd)
##              "pieces" = 칸마다 상자 + 지형 조각 .glb (예전 방식)
const STYLE := "smooth"

const SOIL := Color(0.47, 0.40, 0.32)   # 지형 조각 아래 흙기둥 색
const SAND := Color(0.86, 0.80, 0.60)


## 칸 하나의 모양과 돌릴 각도. 반환: {"kind": 이름, "turn": 0~3 (90도 단위)}
## stair_faces: 계단 자리 사전. 계단이 놓인 면은 "막힌 면"으로 봐서, 계단 위 칸에 절벽 조각이 오지 않게 함
static func classify(tiles: Dictionary, cell: Vector2i, stair_faces: Dictionary = {}) -> Dictionary:
	var h := int(tiles[cell])
	var open: Array[int] = []
	var higher: Array[int] = []
	for i in range(4):
		var n: Vector2i = cell + SIDES[i]
		var nh := int(tiles.get(n, 0))
		if nh < h:
			if not stair_faces.has(_edge_key(cell, n)):
				open.append(i)
		elif nh > h:
			higher.append(i)
	if open.is_empty():
		# 협곡: 마주 보는 두 이웃이 더 높음 (기본: 서·동 벽, 길이 남북으로)
		if (1 in higher and 3 in higher):
			return {"kind": "canyon", "turn": 0}
		if (0 in higher and 2 in higher):
			return {"kind": "canyon", "turn": 1}
		# 만(안쪽 모서리): 대각선이 낮음 (기본: 북서쪽 대각선)
		for i in range(4):
			var diag: Vector2i = cell + SIDES[i] + SIDES[(i + 1) % 4]
			if int(tiles.get(diag, 0)) < h:
				return {"kind": "bay", "turn": i}
		return {"kind": "flat", "turn": 0}
	for kind in CANON.keys():
		var canon: Array = CANON[kind]
		if canon.size() != open.size():
			continue
		for k in range(4):
			var ok := true
			for i in canon:
				if not ((int(i) + k) % 4 in open):
					ok = false
					break
			if ok:
				return {"kind": kind, "turn": k}
	return {"kind": "flat", "turn": 0}


## 바다 쪽 면 번호 (없으면 -1)
static func sea_side(tiles: Dictionary, cell: Vector2i) -> int:
	for i in range(4):
		if not tiles.has(cell + SIDES[i]):
			return i
	return -1


## 칸들을 그려서 parent 아래에 붙입니다.
## tiles: Vector2i -> 높이, step: 한 단 높이(m), stair_faces: "x,z|x,z" 키 사전(계단 자리에는 절벽 벽을 안 붙임)
## colors: 칸 -> 상자 색 (지형 조각이 없을 때 쓰는 원래 색)
## caves: 동굴 통로 칸 -> 지붕 높이 (island_generator.gd 참고, 없으면 빈 사전)
## base: 높이 1의 실제 높이(m). 음수면 step 과 같음 (본 섬처럼 예전 방식)
static func build(parent: Node3D, tiles: Dictionary, step: float, stair_faces: Dictionary, colors: Dictionary, caves: Dictionary = {}, base: float = -1.0) -> void:
	if STYLE == "smooth":
		# 바다와 맞닿은 높이 1 칸은 모래
		var sand := {}
		for cell in tiles.keys():
			if int(tiles[cell]) == 1 and sea_side(tiles, cell) >= 0:
				sand[cell] = true
		parent.add_child(CliffMesh.build(tiles, step, sand, caves, stair_faces, base))
		return
	var use_kit := Assets.has_terrain_kit()
	var use_wall := Assets.has_custom_model("terrace")
	for cell in tiles.keys():
		var h := int(tiles[cell])
		var top := h * step
		var piece: Node3D = null
		var kind := "flat"
		if use_kit:
			var shape := classify(tiles, cell, stair_faces)
			kind = str(shape["kind"])
			var turn := int(shape["turn"])
			# 바다 쪽이 딱 한 면일 때만 해변 (모서리·곶은 원래 조각으로)
			if h == 1 and kind == "edge" and Assets.has_terrain_kind("beach"):
				var s := sea_side(tiles, cell)
				if s >= 0:
					kind = "beach"
					turn = s
			piece = Assets.get_terrain_piece(kind, _cell_hash(cell), step)
			if piece != null:
				piece.position = Vector3(cell.x, top - step, cell.y)
				piece.rotation.y = turn * PI * 0.5
				piece.name = "Terrain_%d_%d" % [cell.x, cell.y]
				parent.add_child(piece)
		# 흙기둥: 지형 조각이 있으면 그 아래만, 없으면 칸 전체
		var col_h := top - step if piece != null else top
		if col_h > 0.001:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.0, col_h, 1.0)
			var mi := MeshInstance3D.new()
			mi.name = "Tile_%d_%d" % [cell.x, cell.y]
			mi.mesh = mesh
			var col: Color = colors.get(cell, Color(0.49, 0.69, 0.41))
			mi.material_override = Assets.get_color_material(SOIL if piece != null else col)
			mi.position = Vector3(cell.x, col_h * 0.5, cell.y)
			parent.add_child(mi)
		if use_wall and kind != "beach":  # 해변은 모래 경사라 벽을 안 붙임
			_add_walls(parent, tiles, cell, step, stair_faces)


## 절벽 면마다 테라스(벽) 모델을 한 단씩 쌓음. 바다 쪽은 수면(높이 0)까지.
static func _add_walls(parent: Node3D, tiles: Dictionary, cell: Vector2i, step: float, stair_faces: Dictionary) -> void:
	var h := int(tiles[cell])
	for i in range(4):
		var n: Vector2i = cell + SIDES[i]
		var nh := int(tiles.get(n, 0))
		if nh >= h:
			continue
		if stair_faces.has(_edge_key(cell, n)):
			continue  # 계단이 기대는 면은 계단 모델이 덮음
		var d := Vector2(SIDES[i])
		for lv in range(nh, h):
			var w := Assets.get_model("terrace")
			# 칸 가장자리에 붙이고, 앞면(-Z)이 바깥(낮은 쪽)을 보게 돌림
			w.position = Vector3(cell.x + d.x * 0.56, lv * step, cell.y + d.y * 0.56)
			w.rotation.y = i * PI * 0.5
			w.name = "Wall_%d_%d_%d_%d" % [cell.x, cell.y, i, lv]
			parent.add_child(w)


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## 같은 칸은 항상 같은 조각(여러 개 있을 때)을 고르도록 하는 숫자
static func _cell_hash(c: Vector2i) -> int:
	return absi(c.x * 73856093 ^ c.y * 19349663)
