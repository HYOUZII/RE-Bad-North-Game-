extends RefCounted
## 여러 칸짜리 지형 덩어리(만, 곶, 고개, 층단, 협곡) 정보
##
## assets/models/terrain_chunks/tiles.json 에 덩어리마다 칸별 높이(surface_y, m)와 역할이 적혀 있습니다.
## 섬 생성기는 이 높이를 그대로 섬 격자에 찍고(높이 0.5m = 1단), 그 자리에 덩어리 모델을 놓습니다.
## 그래서 모델 모양과 이동 규칙(같은 높이 또는 계단)이 정확히 맞습니다.
## tiles.json 이나 .glb 가 없으면 아무 덩어리도 쓰지 않습니다(예전 섬 그대로).

const DIR := "res://assets/models/terrain_chunks/"

## 섬 생성에 쓰는 덩어리. coastal = 바닷가에 두고 앞쪽(-Z)이 바다를 봄 / inland = 섬 안쪽
const USE := {
	"cove": "coastal",
	"spit": "coastal",
	"saddle": "inland",
	"terraces": "inland",
	"ravine": "inland",
}

## 덩어리 안에 꼭 놓을 계단 (덩어리 안 좌표 두 칸). 고개 가운데 칸이 한 단 높아서 통로가 끊기지 않게.
const PASS_STAIRS := {
	"saddle": [[Vector2i(0, -1), Vector2i(0, 0)], [Vector2i(0, 0), Vector2i(0, 1)]],
}

static var _defs: Dictionary = {}
static var _loaded := false


## 쓸 수 있는 덩어리 이름 -> {"kind": coastal/inland, "cells": {Vector2i(x,z): 높이 단계(0 이하는 바다)}, "size": 한 변 칸 수}
static func defs(step: float) -> Dictionary:
	if _loaded:
		return _defs
	_loaded = true
	var path := DIR + "tiles.json"
	if not FileAccess.file_exists(path):
		return _defs
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("assets"):
		push_warning("tiles.json 을 읽지 못했습니다")
		return _defs
	for chunk_name in USE.keys():
		if not data["assets"].has(chunk_name) or not ResourceLoader.exists(DIR + chunk_name + ".glb"):
			continue
		var cells := {}
		var half := 0
		for c in data["assets"][chunk_name]["cells"]:
			var key := Vector2i(int(c["x"]), int(c["z"]))
			half = maxi(half, maxi(absi(key.x), absi(key.y)))
			var sy = c.get("surface_y")
			if sy == null or str(c.get("role", "walk")) != "walk":
				cells[key] = 0
			else:
				cells[key] = maxi(1, int(round(float(sy) / step)))
		# 표에 없는 칸(만 안쪽 물, 곶 양옆)은 바다
		for x in range(-half, half + 1):
			for z in range(-half, half + 1):
				if not cells.has(Vector2i(x, z)):
					cells[Vector2i(x, z)] = 0
		_defs[chunk_name] = {"kind": USE[chunk_name], "cells": cells, "half": half}
	if not _defs.is_empty():
		print("지형 덩어리: ", _defs.keys())
	return _defs


## 덩어리 안 좌표를 k번(90도씩) 돌림. Godot 의 rotation.y = k * 90도 와 같은 방향.
static func rotate_cell(v: Vector2i, k: int) -> Vector2i:
	var r := v
	for i in range(posmod(k, 4)):
		r = Vector2i(r.y, -r.x)
	return r
