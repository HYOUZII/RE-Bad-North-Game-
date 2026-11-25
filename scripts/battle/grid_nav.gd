extends RefCounted
## 섬 격자 길찾기 (A* 알고리즘)
##
## 상하좌우 이웃 칸: 같은 높이이거나 계단이 있을 때만 갈 수 있습니다(나머지는 절벽).
## 대각선: 네 칸이 모두 같은 높이의 평지일 때만 허용합니다(계단·절벽 모서리 끼임 방지).

const DIRS8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var tiles: Dictionary = {}
var island  # island_generator.gd (can_cross, is_walkable 사용)
var _astar := AStar2D.new()
var _ids: Dictionary = {}


func build(p_island) -> void:
	island = p_island
	tiles = island.tiles
	_astar.clear()
	_ids.clear()
	var i := 0
	for c in tiles.keys():
		if not island.is_walkable(c):
			continue
		_ids[c] = i
		_astar.add_point(i, Vector2(c.x, c.y))
		i += 1
	for c in _ids.keys():
		for d in DIRS8:
			var n: Vector2i = c + d
			if can_step(c, n):
				_astar.connect_points(_ids[c], _ids[n], false)


## a 칸에서 바로 옆 b 칸으로 걸어갈 수 있는가
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return island.is_walkable(a)
	var d := b - a
	if abs(d.x) > 1 or abs(d.y) > 1:
		return false
	if d.x == 0 or d.y == 0:
		return island.can_cross(a, b)
	var o1 := Vector2i(a.x + d.x, a.y)
	var o2 := Vector2i(a.x, a.y + d.y)
	for c in [b, o1, o2]:
		if not island.is_walkable(c) or int(tiles[c]) != int(tiles.get(a, -1)):
			return false
	return island.is_walkable(a)


## a에서 b까지의 칸 목록 (a 포함). 갈 수 없으면 빈 배열.
func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _ids.has(a) or not _ids.has(b):
		return out
	var pts := _astar.get_point_path(_ids[a], _ids[b])
	for p in pts:
		out.append(Vector2i(int(round(p.x)), int(round(p.y))))
	return out
