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
	b._select(b.squads[0])
	b._hover_cell = b.squads[0].anchor_cell + Vector2i(1, 0)
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
