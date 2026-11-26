extends Node
## 섬 지형만 여러 장 찍어 보는 개발용 스크립트 (전투는 시작하자마자 멈춤)
## 실행: godot --path . res://tests/terrain_shots.tscn -- --out=/tmp/shots --seeds=11,22,33
## 화면이 있어야 해서 headless가 아니라 창 모드(또는 xvfb)로 실행합니다.

const Battle := preload("res://scripts/battle/battle.gd")

var out_dir := "user://terrain_shots"
var seeds: Array = [101, 202, 303, 404]
var radius := 10


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--seeds="):
			seeds = Array(a.substr(8).split(",")).map(func(s): return int(s))
		elif a.begins_with("--radius="):
			radius = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Game.new_run(777)
	for s in seeds:
		var node := {"name": "test", "difficulty": 1, "seed": s, "radius": radius, "houses": 3}
		var b := Battle.new()
		b.auto_play = false
		b.setup(node, Game.deployed_commanders())
		add_child(b)
		await _frames(8)
		get_tree().paused = true
		await _frames(2)
		_save("island_%d" % s)
		# 가까이서 한 장 (절벽 모양 확인용)
		b.camera_rig.distance = 15.0
		b.camera_rig.pitch_deg = -32.0
		b.camera_rig.yaw += PI * 0.6
		b.camera_rig._update_transform()
		await _frames(2)
		_save("island_%d_close" % s)
		# 동굴이 있으면 동굴 입구 가까이에서 한 장
		if not b.island.caves.is_empty():
			var cc: Vector2i = b.island.caves.keys()[0]
			b.camera_rig.position = Vector3(cc.x, 0.0, cc.y)
			b.camera_rig.distance = 9.0
			b.camera_rig._update_transform()
			await _frames(2)
			_save("island_%d_cave" % s)
		get_tree().paused = false
		b.queue_free()
		await _frames(2)
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
