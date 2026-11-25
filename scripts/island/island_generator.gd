extends Node3D
## 절차적 섬 생성기
##
## 정사각형 격자 위에 노이즈로 높이를 정하고, 가장자리로 갈수록 낮춰서 섬 모양을 만듭니다.
## tiles 사전: Vector2i(x, z) -> 높이(1 이상의 정수). 높이 0 이하는 바다라서 저장하지 않습니다.
## 나중에 유닛 이동(길찾기)과 적 상륙 지점 계산이 이 데이터를 씁니다.

@export var radius: int = 7
@export var max_height: int = 3
@export var tile_size: float = 1.0
@export var step_height: float = 0.5  # 높이 1단계당 실제 높이(m)

const GRASS := Color(0.49, 0.69, 0.41)
const SAND := Color(0.86, 0.80, 0.60)
const ROCK := Color(0.55, 0.55, 0.58)

var tiles: Dictionary = {}
var house_cells: Array[Vector2i] = []


func generate(seed_value: int) -> void:
	for c in get_children():
		c.queue_free()
	tiles.clear()
	house_cells.clear()

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.15
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			var d := Vector2(x, z).length() / float(radius)
			if d > 1.0:
				continue
			var n := (noise.get_noise_2d(x, z) + 1.0) * 0.5  # 0~1
			var v := n * 1.2 - d * d * 1.1 + 0.35
			var h := int(round(v * max_height))
			if Vector2i(x, z) == Vector2i.ZERO:
				h = max(h, 1)  # 중앙은 항상 땅
			if h <= 0:
				continue
			tiles[Vector2i(x, z)] = min(h, max_height)

	_build_tiles()
	_place_houses(rng, 3)
	_place_trees(rng, 6)


## 격자 좌표 -> 월드 좌표 (타일 윗면 중앙)
func cell_to_world(cell: Vector2i) -> Vector3:
	var h: int = tiles.get(cell, 0)
	return Vector3(cell.x * tile_size, h * step_height, cell.y * tile_size)


## 바다와 맞닿은 칸 = 적이 상륙할 수 있는 해안
func get_shore_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in tiles.keys():
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not tiles.has(cell + dir):
				result.append(cell)
				break
	return result


func _build_tiles() -> void:
	var shore := get_shore_cells()
	for cell in tiles.keys():
		var h: int = tiles[cell]
		var mesh := BoxMesh.new()
		var height := h * step_height
		mesh.size = Vector3(tile_size, height, tile_size)
		var mi := MeshInstance3D.new()
		mi.name = "Tile_%d_%d" % [cell.x, cell.y]
		mi.mesh = mesh
		var color := GRASS
		if h == 1 and cell in shore:
			color = SAND
		elif h >= max_height:
			color = ROCK
		mi.material_override = Assets.get_color_material(color)
		mi.position = Vector3(cell.x * tile_size, height * 0.5, cell.y * tile_size)
		add_child(mi)


func _place_houses(rng: RandomNumberGenerator, count: int) -> void:
	var candidates: Array = tiles.keys().filter(func(c): return tiles[c] < max_height)
	candidates.shuffle()
	for cell in candidates:
		if house_cells.size() >= count:
			break
		if cell in get_shore_cells():
			continue  # 집은 해안에서 한 칸 이상 안쪽
		house_cells.append(cell)
		var house := Assets.get_model("house")
		house.position = cell_to_world(cell)
		house.rotation.y = rng.randi_range(0, 3) * PI * 0.5
		add_child(house)


func _place_trees(rng: RandomNumberGenerator, count: int) -> void:
	var placed := 0
	var cells: Array = tiles.keys()
	for i in range(count * 4):
		if placed >= count:
			break
		var cell: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if cell in house_cells:
			continue
		var tree := Assets.get_model("tree")
		tree.position = cell_to_world(cell) + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		add_child(tree)
		placed += 1
