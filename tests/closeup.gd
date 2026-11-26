extends Node
## 병사 동작 확인용 가까이 찍기 (개발용). 창 모드로 실행:
## godot --path . res://tests/closeup.tscn -- --out=/tmp/close
## 자동 전투 중 아군과 적이 맞붙은 곳을 찾아 카메라를 가까이 대고 연속으로 찍습니다.

const Battle := preload("res://scripts/battle/battle.gd")

var out_dir := "user://close"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	Game.new_run(777)
	var b := Battle.new()
	b.auto_play = true
	b.setup(Game.map_nodes[3], Game.deployed_commanders())
	add_child(b)
	await _frames(5)
	# 1) 출발 직후: 행군하는 분대
	var s0 = b.squads[0]
	_look(b, s0.centroid(), 3.2)
	await _frames(2)
	_save("march_0")
	await _wait(b, 1.0)
	_look(b, s0.centroid(), 3.2)
	_save("march_1")
	# 2) 궁수 분대
	var deaths: Array = []
	b.unit_died.connect(func(u, cause):
		if cause != "drown" and cause != "retreat":
			deaths.append(u.position))
	if b.squads.size() > 1:
		await _wait(b, 6.0)
		_look(b, b.squads[1].centroid(), 2.6)
		await _frames(1)
		_save("archers")
	# 3) 맞붙은 곳 찾기 / 막 쓰러진 곳
	var shot := 0
	while shot < 10 and not b.finished and b.elapsed < 90.0:
		await _wait(b, 0.7)
		var spot = _fight_spot(b)
		if not deaths.is_empty() and shot % 2 == 1:
			spot = deaths.pop_back()
			deaths.clear()
		if spot == null:
			continue
		_look(b, spot, 2.6)
		await _frames(1)
		_save("fight_%d" % shot)
		shot += 1
	get_tree().quit()


func _fight_spot(b):
	for u in b.units:
		if u.team != 0 or u.state != u.State.ACTIVE:
			continue
		for e in b.units:
			if e.team == 1 and e.state == e.State.ACTIVE and u.position.distance_to(e.position) < 0.7:
				return (u.position + e.position) * 0.5
	return null


func _look(b, p: Vector3, dist: float) -> void:
	b.camera_rig.position = p
	b.camera_rig.distance = dist
	b.camera_rig.min_distance = 1.0
	b.camera_rig._update_transform()


func _wait(b, sec: float) -> void:
	var t0: float = b.elapsed
	while b.elapsed < t0 + sec and not b.finished:
		await get_tree().process_frame


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
