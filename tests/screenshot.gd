extends Node
## 화면 확인용 스크린샷 (개발용). 실제 렌더링이 필요해서 headless가 아닌 창 모드로 실행합니다.
## 실행: godot --path . res://tests/screenshot.tscn -- --out=/tmp/shots
## title.png, map.png, battle_*.png 를 저장합니다.

const Battle := preload("res://scripts/battle/battle.gd")
const CampaignScreen := preload("res://scripts/ui/campaign_screen.gd")

var out_dir := "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main = load("res://scripts/main.gd").new()
	add_child(main)
	await _frames(10)
	_save("title")
	main.queue_free()
	Game.new_run(777)
	Game.gold = 30
	Game._add_commander("militia")
	Game.roster[0]["skill"] = true
	Game.roster[0]["item"] = "bomb"
	Game.inventory.append("armor")
	Game.changed.emit()
	var home = load("res://scripts/ui/home_screen.gd").new()
	add_child(home)
	await _frames(10)
	_save("home")
	home.open_building("barracks")
	await _frames(5)
	_save("home_barracks")
	home.open_building("market")
	await _frames(5)
	_save("home_market")
	home.queue_free()
	var map := CampaignScreen.new()
	add_child(map)
	await _frames(10)
	_save("map")
	map.queue_free()

	var b := Battle.new()
	b.auto_play = true
	b.setup(Game.map_nodes[3], Game.deployed_commanders())
	add_child(b)
	await _frames(5)
	_save("battle_start")
	for t in [8.0, 14.0, 22.0]:
		while b.elapsed < t and not b.finished:
			await get_tree().process_frame
		_save("battle_%ds" % int(t))
	# 분대 선택 화면(마커 표시) 흉내
	b.auto_play = false
	# 흰 점선(행군 경로) 보이게: 분대 2를 먼 칸으로 보냄
	var far_cells: Array = b.island.tiles.keys().filter(func(c): return b.island.is_walkable(c))
	far_cells.sort_custom(func(x, y): return Vector2(x - b.squads[1].anchor_cell).length() > Vector2(y - b.squads[1].anchor_cell).length())
	for c in far_cells:
		if b.try_order(b.squads[1], c):
			break
	await _frames(20)
	# 노란 점선(미리보기): 분대 1 선택 + 몇 칸 떨어진 곳에 마우스
	b._select(b.squads[0])
	for c in far_cells:
		var dist := Vector2(c - b.squads[0].anchor_cell).length()
		if dist > 4.0 and dist < 7.0 and not b.order_path(b.squads[0], c).is_empty():
			b._hover_cell = c
			break
	await _frames(3)
	_save("battle_selected")
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
