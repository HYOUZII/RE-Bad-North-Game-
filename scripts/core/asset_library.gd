extends Node
## 모델 불러오기 담당 (자동 로드 이름: Assets)
##
## 사용법: var node := Assets.get_model("house")
## - res://assets/models/house.glb 가 있으면 그 모델을 씁니다.
## - 없으면 아래 PLACEHOLDERS 표에 적힌 임시 도형을 만들어 줍니다.
## 그래서 나중에 .glb 파일을 폴더에 넣기만 하면 코드 수정 없이 그래픽이 바뀝니다.

const MODEL_DIR := "res://assets/models/"

## 임시 도형 정의. shape: "box" | "capsule" | "cylinder" | "cone"
## size: 가로(x) / 높이(y) / 세로(z), 단위는 미터(타일 1칸 = 1m)
const PLACEHOLDERS := {
	"house":    {"shape": "box",      "size": Vector3(0.55, 0.45, 0.55), "color": Color(0.90, 0.62, 0.40)},
	"infantry": {"shape": "capsule",  "size": Vector3(0.18, 0.45, 0.18), "color": Color(0.30, 0.50, 0.85)},
	"archer":   {"shape": "capsule",  "size": Vector3(0.16, 0.42, 0.16), "color": Color(0.35, 0.75, 0.45)},
	"pikeman":  {"shape": "capsule",  "size": Vector3(0.18, 0.48, 0.18), "color": Color(0.85, 0.80, 0.35)},
	"raider":   {"shape": "capsule",  "size": Vector3(0.20, 0.45, 0.20), "color": Color(0.80, 0.25, 0.25)},
	"boat":     {"shape": "box",      "size": Vector3(0.70, 0.25, 1.60), "color": Color(0.45, 0.30, 0.20)},
	"tree":     {"shape": "cone",     "size": Vector3(0.35, 0.70, 0.35), "color": Color(0.25, 0.50, 0.30)},
	# 2단계(전투)에서 추가
	"militia":       {"shape": "capsule",  "size": Vector3(0.17, 0.42, 0.17), "color": Color(0.70, 0.70, 0.72)},
	"raider_archer": {"shape": "capsule",  "size": Vector3(0.17, 0.42, 0.17), "color": Color(0.60, 0.20, 0.35)},
	"brute":         {"shape": "capsule",  "size": Vector3(0.30, 0.70, 0.30), "color": Color(0.50, 0.12, 0.12)},
	"house_burned":  {"shape": "box",      "size": Vector3(0.55, 0.18, 0.55), "color": Color(0.20, 0.17, 0.15)},
	"arrow":         {"shape": "box",      "size": Vector3(0.03, 0.03, 0.35), "color": Color(0.95, 0.92, 0.80)},
	"cell_marker":   {"shape": "box",      "size": Vector3(0.92, 0.03, 0.92), "color": Color(0.35, 0.90, 1.00)},
	"hover_marker":  {"shape": "box",      "size": Vector3(0.80, 0.02, 0.80), "color": Color(1.00, 1.00, 1.00)},
	"shield_raider": {"shape": "capsule",  "size": Vector3(0.21, 0.45, 0.21), "color": Color(0.55, 0.35, 0.30)},
	"blast":         {"shape": "cylinder", "size": Vector3(1.40, 0.10, 1.40), "color": Color(1.00, 0.55, 0.15)},
	"stairs":        {"shape": "box",      "size": Vector3(0.62, 0.25, 0.50), "color": Color(0.60, 0.42, 0.25)},
	"rock":          {"shape": "box",      "size": Vector3(0.75, 0.55, 0.75), "color": Color(0.50, 0.50, 0.53)},
	"hover_marker_bad": {"shape": "box",   "size": Vector3(0.80, 0.02, 0.80), "color": Color(0.95, 0.25, 0.20)},
	"path_dot":      {"shape": "box",      "size": Vector3(0.09, 0.02, 0.09), "color": Color(1.00, 1.00, 1.00)},
	"path_dot_preview": {"shape": "box",   "size": Vector3(0.12, 0.03, 0.12), "color": Color(0.35, 0.90, 1.00)},
	"buff_ring":     {"shape": "cylinder", "size": Vector3(0.22, 0.03, 0.22), "color": Color(1.00, 0.95, 0.40)},
	# 본 섬 건물 (정면 = -Z 가 섬 중심 쪽)
	"bld_barracks":  {"shape": "box",      "size": Vector3(1.20, 0.80, 0.90), "color": Color(0.35, 0.50, 0.80)},
	"bld_archery":   {"shape": "box",      "size": Vector3(1.20, 0.60, 0.90), "color": Color(0.35, 0.70, 0.45)},
	"bld_pikehall":  {"shape": "box",      "size": Vector3(1.10, 0.90, 0.90), "color": Color(0.85, 0.78, 0.35)},
	"bld_market":    {"shape": "box",      "size": Vector3(1.00, 0.55, 1.00), "color": Color(0.90, 0.55, 0.30)},
	"bld_recruit":   {"shape": "cylinder", "size": Vector3(0.50, 0.90, 0.50), "color": Color(0.75, 0.72, 0.68)},
	"bld_harbor":    {"shape": "box",      "size": Vector3(0.80, 0.20, 1.80), "color": Color(0.50, 0.36, 0.24)},
	"tent":          {"shape": "cone",     "size": Vector3(0.32, 0.50, 0.32), "color": Color(0.92, 0.88, 0.75)},
	"commander":     {"shape": "capsule",  "size": Vector3(0.20, 0.55, 0.20), "color": Color(0.30, 0.38, 0.65)},
}

## .glb 모델 크기 맞춤 방법 (표에 없으면 "footprint")
## - "footprint": 바닥 넓이(가로·세로)가 위 PLACEHOLDERS 크기에 들어가게 비율을 유지한 채 키우거나 줄임.
##                높이는 비율대로 따라감(깃발·기둥이 있어도 납작해지지 않게).
## - "stretch": 가로·높이·세로를 각각 표 크기에 딱 맞춤(계단처럼 높이가 정확해야 하는 것).
## - "none": 파일 크기 그대로.
## turn: 모델이 반대쪽을 보고 있을 때 돌릴 각도(라디안). 계단 파일은 높은 쪽이 +Z라 반 바퀴 돌림.
## size: .glb일 때만 쓰는 크기(임시 도형 크기와 다르게 하고 싶을 때)
##   - 계단: 한 단(0.5m)을 다 올라가야 위 칸 가장자리와 맞음
##   - 집: 병사보다 확실히 크게 보이도록 조금 크게
## color: 모델 전체를 이 색으로 칠함 (계단 파일은 새하얘서 돌 색으로)
const MODEL_FIT := {
	"stairs": {"fit": "stretch", "turn": PI, "size": Vector3(0.62, 0.50, 0.50), "color": Color(0.62, 0.58, 0.52)},
	"house": {"size": Vector3(0.72, 0.60, 0.72)},
}

## 2D 병사 그림(8방향 스프라이트 시트). assets/sprites/<이름>.png
## .glb 모델이 없으면 이 그림을 씁니다. 단계(tier)별 그림: basic(기본) / veteran(숙련) / elite(정예)
## "%s" 자리에 단계 이름이 들어갑니다. scale = 키 배율(1 = 보통 병사 키 0.45m)
const SPRITES := {
	"infantry":      {"sheet": "ally-sword-%s", "scale": 1.0},
	"militia":       {"sheet": "ally-sword-%s", "scale": 0.95, "tint": Color(0.80, 0.80, 0.80)},
	"archer":        {"sheet": "ally-bow-%s", "scale": 1.0},
	"pikeman":       {"sheet": "ally-spear-%s", "scale": 1.05},
	"raider":        {"sheet": "enemy-sword-%s", "scale": 1.0},
	"shield_raider": {"sheet": "enemy-spear-%s", "scale": 1.0},
	"raider_archer": {"sheet": "enemy-bow-%s", "scale": 1.0},
	"brute":         {"sheet": "enemy-sword-elite", "scale": 1.5},
}
const SPRITE_DIR := "res://assets/sprites/"
const SpriteActor := preload("res://scripts/core/sprite_actor.gd")

var _material_cache: Dictionary = {}


func has_custom_model(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + id + ".glb")


## 모델 하나를 새로 만들어 돌려줍니다. 원점(0,0,0)은 모델의 바닥 중앙입니다.
## 찾는 순서: assets/models/<id>.glb → assets/sprites/ 병사 그림 → 임시 도형
## tier: 병사 그림 단계("basic", "veteran", "elite"). 그림이 없는 대상은 무시됩니다.
func get_model(id: String, tier: String = "basic") -> Node3D:
	var path := MODEL_DIR + id + ".glb"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			return _fit_model(id, scene.instantiate() as Node3D)
		push_warning("모델을 불러오지 못했습니다: " + path)
	var sprite := _make_sprite(id, tier)
	if sprite != null:
		return sprite
	return _make_placeholder(id)


## 병사 그림이 있으면 8방향 그림 병사를 만들어 돌려줍니다. 없으면 null.
func _make_sprite(id: String, tier: String) -> Node3D:
	if not SPRITES.has(id):
		return null
	var spec: Dictionary = SPRITES[id]
	var sheet := str(spec["sheet"])
	if sheet.contains("%s"):
		sheet = sheet % tier
	var path := SPRITE_DIR + sheet + ".png"
	if not ResourceLoader.exists(path):
		return null
	var actor := SpriteActor.new()
	actor.setup(load(path) as Texture2D, float(spec["scale"]), spec.get("tint", Color.WHITE))
	var root := Node3D.new()  # 병사(unit.gd)가 돌려도 그림은 항상 카메라를 봄
	root.name = id.capitalize()
	root.add_child(actor)
	return root


## .glb 모델의 크기·위치를 표(PLACEHOLDERS) 크기에 맞춥니다.
## 원점이 바닥 가운데가 아니어도, 크기가 제각각이어도 게임 안에서는 같은 자리·크기로 보이게 합니다.
func _fit_model(id: String, model: Node3D) -> Node3D:
	var opt: Dictionary = MODEL_FIT.get(id, {})
	var mode := str(opt.get("fit", "footprint"))
	if mode == "none" or not PLACEHOLDERS.has(id):
		return model
	var box := _mesh_bounds(model, Transform3D.IDENTITY)
	if box.size.x <= 0.0001 or box.size.z <= 0.0001:
		return model
	var target: Vector3 = opt.get("size", _placeholder_box(id))
	if opt.has("color"):
		_paint_all(model, get_color_material(opt["color"]))
	var sc: Vector3
	if mode == "stretch":
		sc = Vector3(target.x / box.size.x, target.y / max(box.size.y, 0.0001), target.z / box.size.z)
	else:
		var k: float = min(target.x / box.size.x, target.z / box.size.z)
		sc = Vector3(k, k, k)
	# 바닥 가운데를 원점으로 옮기는 안쪽 노드 + 크기 조절
	var inner := Node3D.new()
	inner.name = "Fit"
	inner.scale = sc
	inner.position = -Vector3(box.get_center().x * sc.x, box.position.y * sc.y, box.get_center().z * sc.z)
	inner.add_child(model)
	var root := Node3D.new()
	root.name = id.capitalize()
	root.add_child(inner)
	inner.rotation.y = float(opt.get("turn", 0.0))
	if inner.rotation.y != 0.0:
		inner.position = inner.position.rotated(Vector3.UP, inner.rotation.y)
	return root


## 모델의 모든 메시를 한 가지 색으로 칠함 (파일 색이 너무 하얗거나 비어 있을 때)
func _paint_all(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_paint_all(c, mat)


## 임시 도형의 실제 바깥 크기(캡슐·원기둥은 size.x가 반지름이라 두 배)
func _placeholder_box(id: String) -> Vector3:
	var spec: Dictionary = PLACEHOLDERS[id]
	var size: Vector3 = spec["size"]
	if str(spec["shape"]) in ["capsule", "cylinder", "cone"]:
		return Vector3(size.x * 2.0, size.y, size.x * 2.0)
	return size


## 노드 아래 모든 메시를 감싸는 상자(모델 자신의 좌표 기준)
func _mesh_bounds(n: Node, xf: Transform3D) -> AABB:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var box := AABB()
	var has := false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		box = t * (n as MeshInstance3D).mesh.get_aabb()
		has = true
	for c in n.get_children():
		var b := _mesh_bounds(c, t)
		if b.size == Vector3.ZERO:
			continue
		box = b if not has else box.merge(b)
		has = true
	return box


## UI 아이콘 그림 (assets/ui/<id>.png). 없으면 null → 글자만 보여 줌
const UI_DIR := "res://assets/ui/"
## 병과별 기술 아이콘
const SKILL_ICONS := {"infantry": "charge", "archer": "volley", "pikeman": "pikes"}


func get_icon(id: String) -> Texture2D:
	var path := UI_DIR + id + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## [아이콘 + 글자] 한 줄. 아이콘 그림이 없으면 글자만 들어 있음
func icon_row(icon_id: String, label: Control, icon_px: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := get_icon(icon_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(icon_px, icon_px)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	row.add_child(label)
	return row


## 색만 지정한 단순 재질. 같은 색은 재사용해서 메모리를 아낍니다.
func get_color_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		_material_cache[key] = mat
	return _material_cache[key]


func _make_placeholder(id: String) -> Node3D:
	var spec: Dictionary = PLACEHOLDERS.get(id, {"shape": "box", "size": Vector3(0.3, 0.3, 0.3), "color": Color.MAGENTA})
	var size: Vector3 = spec["size"]
	var mesh: Mesh
	match spec["shape"]:
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = size.x
			m.height = size.y
			mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = size.x
			m.bottom_radius = size.x
			m.height = size.y
			mesh = m
		"cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = size.x
			m.height = size.y
			mesh = m
		_:
			var m := BoxMesh.new()
			m.size = size
			mesh = m
	var root := Node3D.new()
	root.name = id.capitalize()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = get_color_material(spec["color"])
	mi.position.y = size.y * 0.5  # 바닥이 원점에 오도록 올림
	root.add_child(mi)
	return root
