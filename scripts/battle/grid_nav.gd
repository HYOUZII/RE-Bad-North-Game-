extends RefCounted
## 섬 격자 길찾기 (A* 알고리즘)
##
## 이웃 칸(대각선 포함)으로는 높이 차이 1단계까지만 오르내릴 수 있습니다.
## 대각선 이동은 양옆 두 칸도 지나갈 수 있을 때만 허용합니다(모서리 끼임 방지).

const DIRS8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var tiles: Dictionary = {}
var _astar := AStar2D.new()
var _ids: Dictionary = {}


func build(tile_heights: Dictionary) -> void:
	tiles = tile_heights
	_astar.clear()
	_ids.clear()
	var i := 0
	for c in tiles.keys():
		_ids[c] = i
		_astar.add_point(i, Vector2(c.x, c.y))
		i += 1
	for c in tiles.keys():
		for d in DIRS8:
			var n: Vector2i = c + d
			if can_step(c, n):
				_astar.connect_points(_ids[c], _ids[n], false)


func _height_ok(a: Vector2i, b: Vector2i) -> bool:
	return tiles.has(a) and tiles.has(b) and abs(int(tiles[a]) - int(tiles[b])) <= 1


## a 칸에서 바로 옆 b 칸으로 걸어갈 수 있는가
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return tiles.has(a)
	var d := b - a
	if abs(d.x) > 1 or abs(d.y) > 1:
		return false
	if not _height_ok(a, b):
		return false
	if d.x != 0 and d.y != 0:
		var o1 := Vector2i(a.x + d.x, a.y)
		var o2 := Vector2i(a.x, a.y + d.y)
		return _height_ok(a, o1) and _height_ok(o1, b) and _height_ok(a, o2) and _height_ok(o2, b)
	return true


## a에서 b까지의 칸 목록 (a 포함). 갈 수 없으면 빈 배열.
func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _ids.has(a) or not _ids.has(b):
		return out
	var pts := _astar.get_point_path(_ids[a], _ids[b])
	for p in pts:
		out.append(Vector2i(int(round(p.x)), int(round(p.y))))
	return out
