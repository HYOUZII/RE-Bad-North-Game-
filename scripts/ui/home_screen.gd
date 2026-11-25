extends Node3D
## 본 섬(내가 다스리는 섬) 정비 화면 - 3D
##
## 전투와 전투 사이에 돌아오는 곳입니다. 섬 위의 건물을 클릭해서 분대를 관리합니다.
##   - 병영(보병) / 궁술장(궁수) / 창술장(창병): 그 병과 지휘관 훈련(레벨업), 기술 배우기, 장비 달기,
##     민병을 그 병과로 승급
##   - 시장: 장비 사기 (산 장비는 창고에 들어가고, 병과 건물에서 지휘관에게 달아 줌)
##   - 모집소: 새 지휘관(민병) 고용
##   - 항구: 출항 → 원정 지도
## 지휘관이 늘어날수록 섬이 커지고, 지휘관마다 천막이 하나씩 생깁니다.
## 왼쪽 목록에서 다음 전투에 데려갈 분대(출전)를 고릅니다.

signal sail_requested

const UnitDefs := preload("res://scripts/battle/unit_defs.gd")
const Catalog := preload("res://scripts/core/catalog.gd")
const OrbitCamera := preload("res://scripts/camera/orbit_camera.gd")

const GRASS := Color(0.40, 0.62, 0.32)
const SAND := Color(0.74, 0.64, 0.42)
const PICK_RADIUS := 70.0  # 화면에서 건물 중심과 이 픽셀 거리 안을 누르면 그 건물

## 건물 정의. cls가 있으면 병과 건물. angle = 섬 중심에서 본 방향(도)
const BUILDINGS := {
	"barracks": {"name": "병영", "model": "bld_barracks", "cls": "infantry", "angle": 200.0},
	"archery": {"name": "궁술장", "model": "bld_archery", "cls": "archer", "angle": 320.0},
	"pikehall": {"name": "창술장", "model": "bld_pikehall", "cls": "pikeman", "angle": 80.0},
	"market": {"name": "시장", "model": "bld_market", "cls": "", "angle": 140.0},
	"recruit": {"name": "모집소", "model": "bld_recruit", "cls": "", "angle": 20.0},
	"harbor": {"name": "항구", "model": "bld_harbor", "cls": "", "angle": 260.0},
}

const CLASS_DESC := {
	"militia": "민병: 아직 병종이 없는 분대. 병과 건물에서 보병·궁수·창병으로 승급할 수 있습니다.",
	"infantry": "보병: 방패로 화살을 막고, 적의 길을 막는 데 좋습니다.",
	"archer": "궁수: 멀리서 화살을 쏩니다. 배에 탄 적도 맞힐 수 있지만 근접전에 약합니다.",
	"pikeman": "창병: 넉백이 강해 적을 바다로 밀어냅니다. 방패병과 거한에 강하고 화살에 약합니다.",
}

var camera_rig: Node3D
var radius := 4
var _world: Node3D
var _bld_pos: Dictionary = {}     # 건물 id -> 위치(Vector3)
var _bld_labels: Dictionary = {}  # 건물 id -> Label3D
var _built_for := ""              # 섬을 만들 때의 지휘관 목록 요약 (병과·레벨이 바뀌어도 다시 만듦)
var _open := ""                   # 지금 열린 건물 id ("" = 없음)
var _hover := ""
var _first_build := true

# 화면 UI
var _gold_label: Label
var _info_label: Label
var _roster_box: VBoxContainer
var _panel: PanelContainer
var _panel_title: Label
var _panel_body: VBoxContainer
var _sail_btn: Button


func _ready() -> void:
	_setup_env()
	camera_rig = OrbitCamera.new()
	camera_rig.name = "OrbitCamera"
	add_child(camera_rig)
	_setup_ui()
	Game.changed.connect(_refresh)
	_refresh()


# ================================================================ 섬 만들기

## 지휘관 수에 맞춘 섬 반지름 (작게 시작해서 커짐)
static func island_radius(commanders: int) -> int:
	return clampi(2 + commanders, 4, 8)


func _rebuild_world() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node3D.new()
	_world.name = "HomeIsland"
	add_child(_world)
	_bld_pos.clear()
	_bld_labels.clear()
	var old_radius := radius
	radius = island_radius(Game.roster.size())
	_built_for = _roster_key()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# 타일: 둥근 섬, 가장자리는 모래
	var cells: Array = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			var d := Vector2(x, z).length()
			if d <= float(radius) + 0.3:
				cells.append(Vector2i(x, z))
				var mi := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(1.0, 0.5, 1.0)
				mi.mesh = mesh
				mi.material_override = Assets.get_color_material(SAND if d > float(radius) - 0.9 else GRASS)
				mi.position = Vector3(x, 0.25, z)
				_world.add_child(mi)

	# 건물: 섬 중심 둘레에 놓음 (항구는 바닷가)
	var used := {}
	for id in BUILDINGS.keys():
		var b: Dictionary = BUILDINGS[id]
		var a := deg_to_rad(float(b["angle"]))
		var r := float(radius) * (0.95 if id == "harbor" else 0.55)
		var cell := Vector2i(int(round(cos(a) * r)), int(round(sin(a) * r)))
		used[cell] = true
		var pos := Vector3(cell.x, 0.5, cell.y)
		var m := Assets.get_model(str(b["model"]))
		m.position = pos
		m.rotation.y = -a + PI * 0.5  # 정면이 섬 중심 쪽
		_world.add_child(m)
		_bld_pos[id] = pos
		var lb := Label3D.new()
		lb.text = str(b["name"])
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 56
		lb.pixel_size = 0.008
		lb.outline_size = 14
		lb.no_depth_test = true
		lb.position = pos + Vector3(0, 1.5, 0)
		_world.add_child(lb)
		_bld_labels[id] = lb

	# 천막: 지휘관마다 하나, 자기 병과 건물 옆 (민병은 섬 가운데)
	var per_spot := {}
	for c in Game.roster:
		var anchor := Vector3.ZERO
		for id in BUILDINGS.keys():
			if str(BUILDINGS[id]["cls"]) == str(c["cls"]):
				anchor = _bld_pos[id]
		var key := str(anchor)
		var k: int = per_spot.get(key, 0)
		per_spot[key] = k + 1
		var ang := float(k) * 1.3 + 0.6
		var off := Vector3(cos(ang), 0.0, sin(ang)) * (1.25 if anchor != Vector3.ZERO else 0.9)
		var tent := Assets.get_model("tent")
		tent.position = Vector3(anchor.x, 0.5, anchor.z) + off
		_world.add_child(tent)
		used[Vector2i(int(round(tent.position.x)), int(round(tent.position.z)))] = true
		var nl := Label3D.new()
		nl.text = "%s Lv%d" % [str(c["name"]), int(c["level"])]
		nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nl.font_size = 44
		nl.pixel_size = 0.008
		nl.outline_size = 10
		nl.modulate = Color(1, 1, 1, 0.85)
		nl.position = tent.position + Vector3(0, 0.75, 0)
		_world.add_child(nl)

	# 나무 장식 (건물·천막이 없는 바깥쪽 풀밭)
	for c in cells:
		var d := Vector2(c).length()
		if used.has(c) or d < 1.5 or d > float(radius) - 0.9:
			continue
		if rng.randf() < 0.10:
			var t := Assets.get_model("tree")
			t.position = Vector3(c.x + rng.randf_range(-0.2, 0.2), 0.5, c.y + rng.randf_range(-0.2, 0.2))
			_world.add_child(t)

	if old_radius != radius or camera_rig.max_distance <= 0.0 or _first_build:
		camera_rig.distance = 6.0 + float(radius) * 2.2
		camera_rig.max_distance = 6.0 + float(radius) * 2.2 + 10.0
		_first_build = false
	camera_rig._update_transform()
	_update_camera_offset()


## 지휘관 이름·병과·레벨 요약. 바뀌면 천막과 이름표를 다시 그림
func _roster_key() -> String:
	var parts: PackedStringArray = []
	for c in Game.roster:
		parts.append("%d:%s:%d" % [int(c["id"]), str(c["cls"]), int(c["level"])])
	return ",".join(parts)


## 오른쪽 건물 창이 열리면 섬이 왼쪽으로 보이게 카메라를 옆으로 밂 (창 뒤 건물도 누를 수 있게)
func _update_camera_offset() -> void:
	if camera_rig == null or camera_rig.camera == null:
		return
	camera_rig.camera.h_offset = camera_rig.distance * 0.2 if _open != "" else 0.0


func _setup_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.85)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	sea.mesh = plane
	sea.material_override = Assets.get_color_material(Color(0.13, 0.33, 0.50))
	sea.position.y = 0.02
	add_child(sea)


# ================================================================ 입력 (건물 클릭)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _pick_building((event as InputEventMouseMotion).position)
		_update_label_colors()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var id := _pick_building(mb.position)
			if id != "":
				open_building(id)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		open_building("")


func _pick_building(screen_pos: Vector2) -> String:
	if camera_rig == null or camera_rig.camera == null:
		return ""
	var cam: Camera3D = camera_rig.camera
	var best := ""
	var best_d := PICK_RADIUS
	for id in _bld_pos.keys():
		var wp: Vector3 = _bld_pos[id] + Vector3(0, 0.5, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = id
	return best


## 건물 화면 열기 ("" = 닫기). 테스트에서도 부름.
func open_building(id: String) -> void:
	_open = id
	_update_label_colors()
	_update_camera_offset()
	_build_panel()


## 건물의 화면 좌표 (테스트용)
func building_screen_pos(id: String) -> Vector2:
	return camera_rig.camera.unproject_position(_bld_pos[id] + Vector3(0, 0.5, 0))


func _update_label_colors() -> void:
	for id in _bld_labels.keys():
		var lb: Label3D = _bld_labels[id]
		if id == _open:
			lb.modulate = Color(0.35, 0.9, 1.0)
		elif id == _hover:
			lb.modulate = Color(1.0, 0.9, 0.4)
		else:
			lb.modulate = Color(1, 1, 1)


# ================================================================ 화면 UI

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 빈 곳 클릭은 섬(건물)으로 전달
	root.theme = Theme.new()
	root.theme.set_color("font_disabled_color", "Button", Color(0.72, 0.72, 0.72))
	layer.add_child(root)

	# 왼쪽 위: 제목, 골드, 안내
	var top := VBoxContainer.new()
	top.position = Vector2(16, 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.add_child(_label("본 섬 - 정비", 28))
	_gold_label = _label("", 24)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	top.add_child(_gold_label)
	_info_label = _label("", 15)
	top.add_child(_info_label)

	# 왼쪽 아래: 지휘관 목록 + 출전 체크
	var left := PanelContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 12
	left.offset_right = 372
	left.offset_bottom = -12
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(_label("지휘관 (출전 체크, 최대 %d명)" % Game.MAX_DEPLOY, 17))
	_roster_box = VBoxContainer.new()
	lv.add_child(_roster_box)

	# 오른쪽 아래: 출항 버튼
	_sail_btn = Button.new()
	_sail_btn.anchor_left = 1.0
	_sail_btn.anchor_right = 1.0
	_sail_btn.anchor_top = 1.0
	_sail_btn.anchor_bottom = 1.0
	_sail_btn.offset_left = -260
	_sail_btn.offset_right = -16
	_sail_btn.offset_top = -72
	_sail_btn.offset_bottom = -16
	_sail_btn.add_theme_font_size_override("font_size", 22)
	_sail_btn.pressed.connect(func(): sail_requested.emit())
	root.add_child(_sail_btn)

	# 오른쪽: 건물 창 (건물을 누르면 열림)
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -480
	_panel.offset_right = -12
	_panel.offset_top = 44
	_panel.offset_bottom = -84
	_panel.visible = false
	var sb := StyleBoxFlat.new()  # 뒤의 섬 글씨가 비치지 않게 불투명 배경
	sb.bg_color = Color(0.12, 0.16, 0.20, 0.97)
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)
	var pv := VBoxContainer.new()
	_panel.add_child(pv)
	var head := HBoxContainer.new()
	pv.add_child(head)
	_panel_title = _label("", 24)
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_panel_title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(func(): open_building(""))
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_panel_body)

	var help := _label("건물을 클릭하세요   우클릭 드래그 / Q,E: 회전   휠: 확대·축소", 14)
	help.anchor_left = 0.5
	help.anchor_right = 0.5
	help.offset_left = -260
	help.offset_right = 260
	help.offset_top = 12
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.8)
	root.add_child(help)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _wrap(text: String, font_size: int) -> Label:
	var l := _label(text, font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh() -> void:
	if not is_inside_tree():
		return
	if _roster_key() != _built_for:
		_rebuild_world()
	var deployed := Game.deployed_commanders().size()
	_gold_label.text = "골드 %d" % Game.gold
	_info_label.text = "이웃 섬들이 침략자로부터 지켜 달라고 도움을 청합니다.\n지켜 낸 이웃 섬 %d개   지휘관 %d명" % [Game.islands_cleared, Game.roster.size()]
	_sail_btn.text = "출항 → 원정 지도" if deployed > 0 else "출전할 분대를 고르세요"
	_sail_btn.disabled = deployed == 0

	for c in _roster_box.get_children():
		c.queue_free()
	for c in Game.roster:
		var row := HBoxContainer.new()
		var cid := int(c["id"])
		var cb := CheckBox.new()
		cb.button_pressed = Game.is_deployed(cid)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(_on): Game.toggle_deploy(cid))
		row.add_child(cb)
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s  %s Lv%d  병사 %d" % [str(c["name"]), UnitDefs.display_name(str(c["cls"])), int(c["level"]), Game.soldiers_for(c)]
		btn.tooltip_text = "누르면 이 지휘관의 병과 건물이 열립니다"
		btn.pressed.connect(func(): open_building(_building_for(str(c["cls"]))))
		row.add_child(btn)
		_roster_box.add_child(row)
	_build_panel()


func _building_for(cls: String) -> String:
	for id in BUILDINGS.keys():
		if str(BUILDINGS[id]["cls"]) == cls:
			return id
	return "recruit"  # 민병은 모집소


func _build_panel() -> void:
	if _panel == null:
		return
	_panel.visible = _open != ""
	for c in _panel_body.get_children():
		c.queue_free()
	if _open == "":
		return
	var b: Dictionary = BUILDINGS[_open]
	_panel_title.text = str(b["name"])
	var cls := str(b["cls"])
	if cls != "":
		_class_panel(cls)
	elif _open == "market":
		_market_panel()
	elif _open == "recruit":
		_recruit_panel()
	elif _open == "harbor":
		_harbor_panel()


# ---------------------------------------------------------------- 병과 건물

func _class_panel(cls: String) -> void:
	_panel_body.add_child(_wrap(str(CLASS_DESC.get(cls, "")), 15))
	if Catalog.SKILLS.has(cls):
		var sk: Dictionary = Catalog.SKILLS[cls]
		var sl := _wrap("병과 기술 [F] %s: %s" % [sk["name"], sk["desc"]], 14)
		sl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		_panel_body.add_child(sl)
	_panel_body.add_child(HSeparator.new())
	var mine: Array = Game.roster.filter(func(c): return str(c["cls"]) == cls)
	if mine.is_empty():
		_panel_body.add_child(_wrap("아직 이 병과 지휘관이 없습니다. 아래에서 민병을 승급시키세요.", 15))
	for c in mine:
		_panel_body.add_child(_commander_card(c))
	var militia: Array = Game.roster.filter(func(c): return str(c["cls"]) == "militia")
	if not militia.is_empty():
		_panel_body.add_child(HSeparator.new())
		_panel_body.add_child(_label("민병 승급 → %s (%dG)" % [UnitDefs.display_name(cls), Game.PROMOTE_COST], 18))
		for c in militia:
			var cid := int(c["id"])
			var pb := Button.new()
			pb.text = "%s Lv%d 을(를) %s(으)로 승급" % [str(c["name"]), int(c["level"]), UnitDefs.display_name(cls)]
			pb.disabled = not Game.can_promote(c)
			pb.pressed.connect(func(): Game.promote(cid, cls))
			_panel_body.add_child(pb)


func _commander_card(c: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	var cls := str(c["cls"])
	var cid := int(c["id"])
	vb.add_child(_label("%s  Lv%d%s%s" % [str(c["name"]), int(c["level"]),
		" (최고)" if int(c["level"]) >= Game.MAX_LEVEL else "", "   [출전]" if Game.is_deployed(cid) else ""], 19))
	vb.add_child(_label("병사 %d명   체력 x%.2f   공격 x%.2f   이동 x%.2f" % [
		Game.soldiers_for(c), Game.hp_mult(c), Game.dmg_mult(c), Game.speed_mult(c)], 15))
	vb.add_child(_label("전적: 출전 %d회, 지켜 낸 섬 %d개" % [int(c.get("battles", 0)), int(c.get("saved", 0))], 14))
	vb.add_child(_label("기술: " + (Catalog.skill_name(cls) if bool(c.get("skill", false)) else "없음"), 14))
	var item := str(c.get("item", ""))
	if item != "":
		var il := _wrap("장비 %s%s: %s" % ["[G] " if Catalog.item_active(item) else "", Catalog.item_name(item), Catalog.item_desc(item)], 14)
		il.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		vb.add_child(il)
	else:
		vb.add_child(_label("장비: 없음 (한 명에 하나, 한 번 달면 못 뗌)", 14))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	vb.add_child(row)
	if int(c["level"]) < Game.MAX_LEVEL:
		var b := Button.new()
		b.text = "훈련 (%dG): 레벨업, 병사 +1" % Game.level_cost(c)
		b.disabled = not Game.can_level_up(c)
		b.pressed.connect(func(): Game.level_up(cid))
		row.add_child(b)
	if Catalog.SKILLS.has(cls) and not bool(c.get("skill", false)):
		var b2 := Button.new()
		b2.text = "기술 배우기 (%dG)" % Catalog.SKILL_COST
		b2.tooltip_text = str(Catalog.SKILLS[cls]["desc"])
		b2.disabled = not Game.can_buy_skill(c)
		b2.pressed.connect(func(): Game.buy_skill(cid))
		row.add_child(b2)
	if item == "":
		var seen := {}
		for inv_item in Game.inventory:
			if seen.has(inv_item):
				continue
			seen[inv_item] = true
			var b3 := Button.new()
			b3.text = "%s 달기" % Catalog.item_name(inv_item)
			b3.tooltip_text = Catalog.item_desc(inv_item) + " (한 번 달면 뗄 수 없음)"
			b3.pressed.connect(func(): Game.equip(cid, inv_item))
			row.add_child(b3)
		if Game.inventory.is_empty():
			row.add_child(_label("(창고에 장비 없음: 시장에서 사기)", 13))
	return panel


# ---------------------------------------------------------------- 시장, 모집소, 항구

func _market_panel() -> void:
	_panel_body.add_child(_wrap("장비를 사면 창고에 들어갑니다. 병과 건물에서 지휘관에게 달아 주세요.\n물건은 이웃 섬을 지킬 때마다 바뀝니다.", 15))
	for item in Game.shop:
		var b := Button.new()
		b.text = "%s (%dG)\n%s" % [Catalog.item_name(item), Catalog.ITEM_COST, Catalog.item_desc(item)]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Game.can_buy_item(item)
		b.pressed.connect(func(): Game.buy_item(item))
		_panel_body.add_child(b)
	if Game.shop.is_empty():
		_panel_body.add_child(_label("다 팔렸습니다.", 15))
	var names: PackedStringArray = []
	for it in Game.inventory:
		names.append(Catalog.item_name(it))
	_panel_body.add_child(HSeparator.new())
	_panel_body.add_child(_wrap("창고: " + (", ".join(names) if not names.is_empty() else "비어 있음"), 15))


func _recruit_panel() -> void:
	_panel_body.add_child(_wrap("새 지휘관(민병 분대)을 고용합니다. 지휘관이 늘면 본 섬도 커집니다.\n민병은 병과 건물(병영·궁술장·창술장)에서 승급시킬 수 있습니다.", 15))
	var r := Button.new()
	r.text = "지휘관 고용 (%dG)   지금 %d/%d명" % [Catalog.RECRUIT_COST, Game.roster.size(), Game.MAX_ROSTER]
	r.disabled = not Game.can_recruit()
	r.pressed.connect(func(): Game.recruit())
	_panel_body.add_child(r)
	var militia: Array = Game.roster.filter(func(c): return str(c["cls"]) == "militia")
	for c in militia:
		_panel_body.add_child(_label("민병 %s Lv%d  병사 %d명" % [str(c["name"]), int(c["level"]), Game.soldiers_for(c)], 15))


func _harbor_panel() -> void:
	_panel_body.add_child(_wrap("배를 띄워 도움을 청한 이웃 섬으로 갑니다. 데려갈 분대는 왼쪽 목록에서 체크하세요.", 15))
	for c in Game.deployed_commanders():
		_panel_body.add_child(_label("%s  %s Lv%d  병사 %d명" % [str(c["name"]), UnitDefs.display_name(str(c["cls"])), int(c["level"]), Game.soldiers_for(c)], 15))
	var b := Button.new()
	b.text = "출항 → 원정 지도"
	b.custom_minimum_size = Vector2(0, 48)
	b.disabled = Game.deployed_commanders().is_empty()
	b.pressed.connect(func(): sail_requested.emit())
	_panel_body.add_child(b)
