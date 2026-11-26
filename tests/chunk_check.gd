extends Node
## 개발용 검사: 지형 덩어리가 놓인 섬에서 덩어리 칸 높이가 tiles.json 과 같은지, 모두 길로 이어지는지
const IG := preload("res://scripts/island/island_generator.gd")
const TC := preload("res://scripts/island/terrain_chunks.gd")
func _ready() -> void:
	await get_tree().process_frame
	var defs := TC.defs(0.5)
	var stats := {}
	var bad := 0
	var total := 0
	for seed in range(1, 61):
		var ig = IG.new()
		ig.radius = [6, 7, 8, 9][seed % 4]
		add_child(ig)
		ig.generate(seed, 3)
		var start: Vector2i = ig._center_cell()
		for c in ig.tiles.keys():
			if ig.is_walkable(c) and (not ig.is_walkable(start) or Vector2(c).length() < Vector2(start).length()):
				start = c
		var reach: Dictionary = ig._flood(start)
		for ch in ig.chunks:
			total += 1
			stats[ch["name"]] = int(stats.get(ch["name"], 0)) + 1
			for local in defs[ch["name"]]["cells"].keys():
				var c: Vector2i = ch["anchor"] + TC.rotate_cell(local, ch["turn"])
				var want: int = defs[ch["name"]]["cells"][local]
				var got: int = ig.tiles.get(c, 0)
				if want != got or (got > 0 and not reach.has(c) and not ig.blocked.has(c)):
					bad += 1
					print("BAD seed=%d %s %s want=%d got=%d reach=%s" % [seed, ch["name"], c, want, got, reach.has(c)])
		ig.free()
	print("CHUNKS placed=", total, " ", stats, " bad=", bad)
	get_tree().quit()
