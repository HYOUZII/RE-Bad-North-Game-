extends Node
## 모델 불러오기 담당 (자동 로드 이름: Assets)
##
## 사용법: var node := Assets.get_model("house")
## - res://assets/models/house.glb 가 있으면 그 모델을 씁니다.
## - 없으면 아래 PLACEHOLDERS 표에 적힌 임시 도형을 만들어 줍니다.
## 그래서 나중에 .glb 파일을 폴더에 넣기만 하면 코드 수정 없이 그래픽이 바뀝니다.

const MODEL_DIR := "res://assets/models/"

## 임시 도형 정의. shape: "box" | "capsule" | "cylinder" | "cone" | "sphere"
## size: 가로(x) / 높이(y) / 세로(z), 단위는 미터(타일 1칸 = 1m)
const PLACEHOLDERS := {
	"house":    {"shape": "box",      "size": Vector3(0.55, 0.45, 0.55), "color": Color(0.90, 0.62, 0.40)},
	"infantry": {"shape": "capsule",  "size": Vector3(0.18, 0.45, 0.18), "color": Color(0.30, 0.50, 0.85)},
	"archer":   {"shape": "capsule",  "size": Vector3(0.16, 0.42, 0.16), "color": Color(0.35, 0.75, 0.45)},
	"pikeman":  {"shape": "capsule",  "size": Vector3(0.18, 0.48, 0.18), "color": Color(0.85, 0.80, 0.35)},
	"raider":   {"shape": "capsule",  "size": Vector3(0.20, 0.45, 0.20), "color": Color(0.80, 0.25, 0.25)},
	"boat":     {"shape": "box",      "size": Vector3(0.70, 0.25, 1.60), "color": Color(0.45, 0.30, 0.20)},
	"tree":     {"shape": "cone",     "size": Vector3(0.35, 0.70, 0.35), "color": Color(0.25, 0.50, 0.30)},
	"bush":     {"shape": "sphere",   "size": Vector3(0.16, 0.20, 0.16), "color": Color(0.38, 0.58, 0.40)},
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
	"rock":          {"shape": "sphere",   "size": Vector3(0.40, 0.55, 0.40), "color": Color(0.70, 0.72, 0.71)},
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
	# 절벽 벽 한 단 (앞면 -Z가 낮은 쪽/바깥). 파일이 있을 때만 섬에 붙음(없으면 상자 절벽 그대로)
	"terrace":       {"shape": "box",      "size": Vector3(1.00, 0.50, 0.12), "color": Color(0.55, 0.50, 0.44)},
	# 절벽 바위 조각 (섬 외곽선을 따라 세움). 앞(바위 얼굴) -Z 가 바깥, 원점 = 바닥 가운데.
	# 실제 크기는 놓을 자리에 맞춰 늘려 맞춤(get_rock_piece). 파일은 assets/models/rock_kit/<id>_01.glb 처럼 번호를 붙여 여러 개 가능
	"cliff":            {"shape": "rock", "size": Vector3(1.00, 1.00, 0.47), "color": Color(0.70, 0.71, 0.67)},
	"cliff_tall":       {"shape": "rock", "size": Vector3(1.00, 2.00, 0.47), "color": Color(0.70, 0.71, 0.67)},
	"cliff_corner_out": {"shape": "rock", "size": Vector3(0.71, 1.00, 0.47), "color": Color(0.70, 0.71, 0.67)},
	"cliff_corner_in":  {"shape": "rock", "size": Vector3(0.71, 1.00, 0.47), "color": Color(0.70, 0.71, 0.67)},
	"shore_rock":       {"shape": "rock", "size": Vector3(1.00, 0.65, 0.47), "color": Color(0.70, 0.71, 0.67)},
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
	"stairs": {"fit": "stretch", "turn": PI, "size": Vector3(0.62, 0.50, 0.50), "color": Color(0.78, 0.78, 0.74)},  # 절벽 바위와 같은 밝은 돌색
	"house": {"size": Vector3(0.72, 0.60, 0.72)},
	# 절벽 벽은 칸 한 면을 정확히 덮어야 해서 늘려 맞춤
	"terrace": {"fit": "stretch"},
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

## 뼈대와 동작(애니메이션)이 있는 3D 병사 (assets/characters/). .glb 모델이 없으면 그림보다 먼저 씀.
## 지금은 무료(CC0) KayKit 캐릭터를 임시로 씁니다. 출처·라이선스: assets/characters/kaykit/LICENSE.txt
## - file: 캐릭터 파일   - anims: 아래 RIG_ANIMS의 동작 묶음 이름
## - gear: 보이게 할 장비(무기·방패·모자). 몸(Body/Head/Arm/Leg)은 항상 보이고, 나머지 장비는 숨김
## - veteran / elite: 그 단계에서 더 붙는 장비   - leader: 분대장일 때만 보이는 장비(망토)
## - height: 게임 속 키(m). 없으면 PLACEHOLDERS 높이
## - tint: 전체 색 곱하기(팀 구분용). 적은 붉게 물들여 아군(은빛 기사)과 한눈에 구분되게
const RIG_DIR := "res://assets/characters/"
const RIGS := {
	"infantry": {"file": "kaykit/Knight.glb", "anims": "sword", "gear": ["1H_Sword", "Round_Shield"],
		"veteran": ["Knight_Helmet"], "elite": ["Knight_Helmet", "Badge_Shield"], "leader": ["Knight_Cape"]},
	"militia": {"file": "kaykit/Knight.glb", "anims": "sword", "gear": ["1H_Sword"], "leader": ["Knight_Cape"],
		"tint": Color(0.82, 0.80, 0.76), "height": 0.42},
	"pikeman": {"file": "kaykit/Knight.glb", "anims": "spear", "gear": ["2H_Sword"],
		"veteran": ["Knight_Helmet"], "elite": ["Knight_Helmet"], "leader": ["Knight_Cape"], "tint": Color(1.0, 0.95, 0.80)},
	"archer": {"file": "kaykit/Rogue_Hooded.glb", "anims": "bow", "gear": ["2H_Crossbow"], "leader": ["Rogue_Cape"]},
	"raider": {"file": "kaykit/Barbarian.glb", "anims": "sword", "gear": ["1H_Axe", "Barbarian_Hat"],
		"elite": ["1H_Axe_Offhand"], "tint": Color(0.95, 0.62, 0.55)},
	"shield_raider": {"file": "kaykit/Barbarian.glb", "anims": "sword", "gear": ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"],
		"tint": Color(0.82, 0.55, 0.50)},
	"raider_archer": {"file": "kaykit/Rogue.glb", "anims": "bow", "gear": ["1H_Crossbow"], "tint": Color(1.0, 0.55, 0.50)},
	"brute": {"file": "kaykit/Barbarian.glb", "anims": "axe2h", "gear": ["2H_Axe", "Barbarian_Hat"], "tint": Color(0.72, 0.45, 0.42)},
}
## 동작 묶음: 동작 종류 -> 애니메이션 이름 후보(여러 개면 무작위로 섞어 씀)
## 직접 만든 모델(Mixamo 등)은 이 이름이 없어도 rig_actor.gd가 "walk", "attack" 같은 단어로 찾아 줍니다.
const RIG_ANIMS := {
	"sword": {"idle": ["Idle"], "walk": ["Walking_A"], "run": ["Running_A"],
		"attack": ["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Chop"],
		"hit": ["Hit_A", "Hit_B"], "block": ["Block_Hit"], "death": ["Death_A", "Death_B"],
		"fall": ["Jump_Idle"], "cheer": ["Cheer"]},
	"spear": {"idle": ["2H_Melee_Idle"], "walk": ["Walking_B"], "run": ["Running_A"],
		"attack": ["2H_Melee_Attack_Stab"], "hit": ["Hit_A", "Hit_B"], "death": ["Death_A", "Death_B"],
		"fall": ["Jump_Idle"], "cheer": ["Cheer"]},
	"axe2h": {"idle": ["2H_Melee_Idle"], "walk": ["Walking_C"], "run": ["Running_B"],
		"attack": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice"], "hit": ["Hit_B"], "death": ["Death_B"],
		"fall": ["Jump_Idle"], "cheer": ["Cheer"]},
	"bow": {"idle": ["Idle"], "walk": ["Walking_A"], "run": ["Running_A"],
		"attack": ["1H_Melee_Attack_Stab"], "aim": ["2H_Ranged_Aiming"], "shoot": ["2H_Ranged_Shoot"],
		"hit": ["Hit_A", "Hit_B"], "death": ["Death_A", "Death_B"], "fall": ["Jump_Idle"], "cheer": ["Cheer"]},
}
## 몸 부분 메시 이름에 들어 있는 단어 (항상 보임)
const RIG_BODY_WORDS := ["_Body", "_Head", "_Arm", "_Leg"]
const RigActor := preload("res://scripts/core/rig_actor.gd")
var _tint_cache: Dictionary = {}
const SpriteActor := preload("res://scripts/core/sprite_actor.gd")

var _material_cache: Dictionary = {}


func has_custom_model(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + id + ".glb")


## 모델 하나를 새로 만들어 돌려줍니다. 원점(0,0,0)은 모델의 바닥 중앙입니다.
## 찾는 순서: assets/models/<id>.glb → assets/characters/ 움직이는 3D 병사 → assets/sprites/ 병사 그림 → 임시 도형
## tier: 병사 그림 단계("basic", "veteran", "elite"). 그림이 없는 대상은 무시됩니다.
func get_model(id: String, tier: String = "basic") -> Node3D:
	var path := MODEL_DIR + id + ".glb"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var inst := scene.instantiate() as Node3D
			# 직접 만든 병사 모델에 동작(애니메이션)이 들어 있으면 움직이는 병사로 만듦
			if RIGS.has(id) and not inst.find_children("*", "AnimationPlayer", true, false).is_empty():
				return _wrap_rig(id, _fit_model(id, inst), _fit_scale_of(id, inst), {}, [])
			return _fit_model(id, inst)
		push_warning("모델을 불러오지 못했습니다: " + path)
	var rig := _make_rig(id, tier)
	if rig != null:
		return rig
	var sprite := _make_sprite(id, tier)
	if sprite != null:
		return sprite
	return _make_placeholder(id)


## 3D 캐릭터 파일이 있으면 움직이는 병사(rig_actor.gd)를 만들어 돌려줍니다. 없으면 null.
func _make_rig(id: String, tier: String) -> Node3D:
	if not RIGS.has(id):
		return null
	var spec: Dictionary = RIGS[id]
	var path := RIG_DIR + str(spec["file"])
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	var show: Array = spec.get("gear", []).duplicate()
	show.append_array(spec.get(tier, []))
	var leader_names: Array = spec.get("leader", [])
	var leader_nodes: Array = []
	var tint: Color = spec.get("tint", Color.WHITE)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var is_body := false
		for w in RIG_BODY_WORDS:
			if str(w) in mi.name:
				is_body = true
		if mi.name in leader_names:
			leader_nodes.append(mi)
		mi.visible = is_body or (mi.name in show)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if tint != Color.WHITE:
			_tint_mesh(mi, tint)
	# 키 맞추기: 몸 부분만 재서(무기 길이는 빼고) 원하는 키가 되게
	var body := _body_bounds(inst)
	var height: float = float(spec.get("height", _placeholder_box(id).y if PLACEHOLDERS.has(id) else 0.45))
	var k: float = height / max(body.size.y, 0.0001)
	var fit := Node3D.new()
	fit.name = "Fit"
	fit.scale = Vector3(k, k, k)
	fit.rotation.y = PI  # 파일 속 캐릭터는 +Z를 봄. 게임은 -Z가 앞
	fit.position.y = -body.position.y * k
	fit.add_child(inst)
	return _wrap_rig(id, fit, k, RIG_ANIMS.get(str(spec.get("anims", "")), {}), leader_nodes)


func _wrap_rig(id: String, model: Node3D, model_scale: float, anims: Dictionary, leader_nodes: Array) -> Node3D:
	var actor := RigActor.new()
	actor.name = id.capitalize()
	actor.setup(model, anims, model_scale, leader_nodes)
	return actor


## .glb 병사 모델이 _fit_model에서 받게 될 크기 배율(걷는 속도 맞춤용)
func _fit_scale_of(id: String, model: Node3D) -> float:
	var box := _mesh_bounds(model, Transform3D.IDENTITY)
	var target: Vector3 = MODEL_FIT.get(id, {}).get("size", _placeholder_box(id))
	if box.size.x <= 0.0001 or box.size.z <= 0.0001:
		return 1.0
	return min(target.x / box.size.x, target.z / box.size.z)


## 몸(Body/Head/Arm/Leg) 메시만 감싸는 상자
func _body_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var has := false
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var is_body := false
		for w in RIG_BODY_WORDS:
			if str(w) in mi.name:
				is_body = true
		if not is_body or mi.mesh == null:
			continue
		var b := mi.mesh.get_aabb()
		box = b if not has else box.merge(b)
		has = true
	if not has:
		return _mesh_bounds(model, Transform3D.IDENTITY)
	return box


## 메시의 원래 재질에 색을 곱한 복사본을 입힘 (같은 재질·색은 재사용)
func _tint_mesh(mi: MeshInstance3D, tint: Color) -> void:
	if mi.mesh == null:
		return
	for i in range(mi.mesh.get_surface_count()):
		var base := mi.mesh.surface_get_material(i)
		if not (base is StandardMaterial3D):
			continue
		var key := "%d:%s" % [base.get_instance_id(), tint.to_html()]
		if not _tint_cache.has(key):
			var mat := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.albedo_color = mat.albedo_color * tint
			_tint_cache[key] = mat
		mi.set_surface_override_material(i, _tint_cache[key])


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


# ================================================================ 지형 조각 (섬 타일)
## assets/models/terrain/ 폴더의 .glb 를 파일 이름으로 알아봅니다.
## 이름에 아래 단어가 들어 있으면 그 모양으로 씁니다(대소문자 무시). 예: "Terrain_Bay_02.glb" → bay
## 같은 모양 파일이 여러 개면 칸마다 골고루 섞어 씁니다.
## 모양 설명과 방향은 scripts/island/terrain_builder.gd 맨 위 주석, docs/ASSET_PIPELINE.md 참고.
const TERRAIN_DIR := "res://assets/models/terrain/"
const TERRAIN_KEYWORDS := {
	"beach":  ["beach", "sand", "coast", "해변", "모래"],
	"canyon": ["canyon", "gorge", "ravine", "valley", "협곡", "골짜기"],
	"bay":    ["bay", "cove", "inner", "inlet", "concave", "만"],
	"cape":   ["cape", "peninsula", "tip", "point", "end", "곶"],
	"islet":  ["islet", "pillar", "single", "isolated", "solo", "외딴", "기둥"],
	"narrow": ["narrow", "ridge", "bridge", "isthmus", "strip", "능선", "다리"],
	"corner": ["corner", "outer", "convex", "모서리"],
	"edge":   ["edge", "cliff", "side", "straight", "shore", "절벽", "가장자리"],
	"flat":   ["flat", "plain", "grass", "meadow", "plateau", "center", "full", "평지", "풀"],
}
## 위 표를 이 순서로 확인 (예: "cliff_corner" 는 edge보다 corner 가 먼저 맞음)
const TERRAIN_ORDER := ["beach", "canyon", "bay", "cape", "islet", "narrow", "corner", "edge", "flat"]
## 모양별로 모델이 반대쪽을 보고 있으면 여기서 돌림(90도 단위 횟수). 예: {"bay": 2}
const TERRAIN_TURN := {}

var _terrain_kit: Dictionary = {}   # 모양 -> 파일 경로 목록
var _terrain_scanned := false
var _terrain_unknown: Array[String] = []


## 폴더를 한 번 훑어서 모양별 파일 목록을 만듭니다.
func _scan_terrain() -> void:
	if _terrain_scanned:
		return
	_terrain_scanned = true
	_terrain_kit.clear()
	var dir := DirAccess.open(TERRAIN_DIR)
	if dir == null:
		return
	var names: Array[String] = []
	for f in dir.get_files():
		# 내보낸 게임에서는 "x.glb.import" / "x.glb.remap" 으로 보임
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if name.get_extension().to_lower() == "glb" and not (name in names):
			names.append(name)
	names.sort()
	for name in names:
		var kind := terrain_kind_of(name)
		if kind == "":
			_terrain_unknown.append(name)
			continue
		if not _terrain_kit.has(kind):
			_terrain_kit[kind] = []
		_terrain_kit[kind].append(TERRAIN_DIR + name)
	if not _terrain_unknown.is_empty():
		push_warning("지형 조각 이름을 알아보지 못했습니다(파일 이름에 bay, cape 같은 단어를 넣어 주세요): " + ", ".join(_terrain_unknown))
	if not _terrain_kit.is_empty():
		print("지형 조각: ", _terrain_kit.keys())


## 파일 이름 → 모양 이름 ("" = 모름)
## 이름을 단어로 나눠서 비교합니다: "Terrain_Bay-02" → terrain, bay, 02 / "CliffCorner2" → cliff, corner, 2
static func terrain_kind_of(file_name: String) -> String:
	var base := file_name.get_basename()
	var spaced := ""
	for i in range(base.length()):
		var ch := base[i]
		# 소문자 다음 대문자, 글자와 숫자 사이에서 단어를 끊음
		if i > 0:
			var prev := base[i - 1]
			var up_after_low := ch != ch.to_lower() and prev != prev.to_upper()
			var digit_edge := ch.is_valid_int() != prev.is_valid_int()
			if up_after_low or digit_edge:
				spaced += "_"
		spaced += ch
	var words := spaced.to_lower().replace("-", "_").replace(" ", "_").replace(".", "_").split("_", false)
	for kind in TERRAIN_ORDER:
		for kw in TERRAIN_KEYWORDS[kind]:
			if str(kw) in words:
				return kind
	return ""


## 지형 조각이 하나라도 있는가 (없으면 섬은 예전처럼 상자로만 그림)
func has_terrain_kit() -> bool:
	_scan_terrain()
	return not _terrain_kit.is_empty()


func has_terrain_kind(kind: String) -> bool:
	_scan_terrain()
	return _terrain_kit.has(kind)


## 칸 맨 위 한 단(가로 1 × 높이 step × 세로 1)을 덮는 지형 조각. 없으면 null.
## 그 모양 파일이 없으면 평지(flat) 조각으로 대신하고, 그것도 없으면 null(상자로 그림).
func get_terrain_piece(kind: String, pick: int, step: float) -> Node3D:
	_scan_terrain()
	var k := kind
	if not _terrain_kit.has(k):
		k = "flat"
		if not _terrain_kit.has(k):
			return null
	var files: Array = _terrain_kit[k]
	var path := str(files[pick % files.size()])
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	# 1) 필요하면 돌리고  2) 바닥 가운데를 원점으로  3) 칸 한 개를 딱 덮도록 늘림(조각끼리 틈이 없게)
	var turned := Node3D.new()
	turned.rotation.y = float(int(TERRAIN_TURN.get(k, 0))) * PI * 0.5
	turned.add_child(scene.instantiate() as Node3D)
	var box := _mesh_bounds(turned, Transform3D.IDENTITY)
	if box.size.x <= 0.0001 or box.size.z <= 0.0001:
		turned.free()
		return null
	var centered := Node3D.new()
	centered.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	centered.add_child(turned)
	var scaled := Node3D.new()
	scaled.name = "Fit"
	scaled.scale = Vector3(1.0 / box.size.x, step / max(box.size.y, 0.0001), 1.0 / box.size.z)
	scaled.add_child(centered)
	var root := Node3D.new()
	root.add_child(scaled)
	return root


# ================================================================ 절벽 바위 조각 (rock_kit)
## assets/models/rock_kit/ 폴더의 .glb. 파일 이름 = 조각 id (+ 번호). 예: cliff_01.glb, cliff_02.glb, cliff_tall_01.glb
## 조각 id 와 크기·방향 약속은 scripts/island/rock_kit.gd 맨 위, docs/TERRAIN_KIT.md 참고.
const ROCK_KIT_DIR := "res://assets/models/rock_kit/"
const RockKit := preload("res://scripts/island/rock_kit.gd")
## 파일 모델에도 공용 바위 셰이더(지층 줄, 이끼, 각진 면)를 입힘. false 면 파일의 원래 색/텍스처를 씀
const ROCK_SHADER_ON_FILES := true
## 이 id 파일이 없을 때 대신 쓸 id (예: 두 단 절벽이 없으면 한 단 절벽을 늘려 씀)
const ROCK_FALLBACK := {
	"cliff_tall": "cliff",
	"cliff_corner_out": "cliff",
	"cliff_corner_in": "cliff",
	"shore_rock": "cliff",
}

var _rock_files: Dictionary = {}   # id -> 파일 경로 목록
var _rock_scanned := false


func _scan_rock_kit() -> void:
	if _rock_scanned:
		return
	_rock_scanned = true
	var dir := DirAccess.open(ROCK_KIT_DIR)
	if dir == null:
		return
	var names: Array[String] = []
	for f in dir.get_files():
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if name.get_extension().to_lower() == "glb" and not (name in names):
			names.append(name)
	names.sort()
	# 긴 id 부터 맞춤 ("cliff_tall_01" 이 "cliff" 로 잘못 잡히지 않게)
	var ids: Array = RockKit.KINDS.keys()
	ids.sort_custom(func(a, b): return str(a).length() > str(b).length())
	for name in names:
		var base := name.get_basename().to_lower().replace("-", "_").replace(" ", "_")
		var found := ""
		for id in ids:
			var rest := base.trim_prefix(str(id))
			if base.begins_with(str(id)) and (rest == "" or rest.begins_with("_") and rest.trim_prefix("_").is_valid_int()):
				found = str(id)
				break
		if found == "":
			push_warning("바위 조각 이름을 알아보지 못했습니다(예: cliff_01.glb): " + name)
			continue
		if not _rock_files.has(found):
			_rock_files[found] = []
		_rock_files[found].append(ROCK_KIT_DIR + name)
	if not _rock_files.is_empty():
		print("바위 조각: ", _rock_files.keys())


## 바위 조각 하나. size = (가로, 높이, 앞뒤 깊이). 원점 = 바닥 가운데, 앞(-Z) = 바깥.
## 파일이 있으면 그 크기에 맞춰 늘리고, 없으면 임시 바위를 그 크기로 만듦. pick 으로 여러 파일 중 하나를 고름
func get_rock_piece(id: String, pick: int, size: Vector3) -> Node3D:
	_scan_rock_kit()
	var k := id
	while not _rock_files.has(k) and ROCK_FALLBACK.has(k):
		k = str(ROCK_FALLBACK[k])
	if _rock_files.has(k):
		var files: Array = _rock_files[k]
		var scene := load(str(files[pick % files.size()])) as PackedScene
		if scene != null:
			var fitted := _fit_rock_file(scene.instantiate() as Node3D, size)
			if fitted != null:
				return fitted
	return _rock_placeholder(id, pick % 4, size)


## 파일 모델을 size 상자에 맞춤: 가로·높이는 딱 맞게, 앞뒤는 앞쪽이 FRONT_OUT 만큼만 튀어나오게
## 파일 약속: Blender 정면 보기(숫자패드 1)에서 바위 얼굴이 보이게 만든 모델 = 파일 안에서 얼굴이 +Z.
## 게임 안에서는 얼굴이 -Z(바깥)여야 해서 반 바퀴 돌려서 씀.
func _fit_rock_file(model: Node3D, size: Vector3) -> Node3D:
	var turned := Node3D.new()
	turned.rotation.y = PI
	turned.add_child(model)
	var box := _mesh_bounds(turned, Transform3D.IDENTITY)
	if box.size.x <= 0.0001 or box.size.y <= 0.0001 or box.size.z <= 0.0001:
		turned.free()
		return null
	model = turned
	var sc := Vector3(size.x * RockKit.OVERLAP / box.size.x, size.y / box.size.y, size.z / box.size.z)
	var inner := Node3D.new()
	inner.name = "Fit"
	inner.scale = sc
	# 가로 가운데, 바닥 = 0, 앞면(z 최소) = -FRONT_OUT
	inner.position = Vector3(-box.get_center().x * sc.x, -box.position.y * sc.y, -RockKit.FRONT_OUT - box.position.z * sc.z)
	inner.add_child(model)
	if ROCK_SHADER_ON_FILES:
		_paint_all(model, RockKit.rock_material())
	var root := Node3D.new()
	root.add_child(inner)
	return root


func _rock_placeholder(id: String, variant: int, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = id.capitalize()
	var mi := MeshInstance3D.new()
	mi.mesh = RockKit.placeholder_mesh(id, variant, size)
	mi.material_override = RockKit.rock_material()
	root.add_child(mi)
	return root


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
		"sphere":
			var m := SphereMesh.new()
			m.radius = size.x
			m.height = size.y
			m.radial_segments = 8
			m.rings = 4
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
	if str(spec["shape"]) == "rock":
		return _rock_placeholder(id, 0, size)
	var root := Node3D.new()
	root.name = id.capitalize()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = get_color_material(spec["color"])
	mi.position.y = size.y * 0.5  # 바닥이 원점에 오도록 올림
	root.add_child(mi)
	return root
