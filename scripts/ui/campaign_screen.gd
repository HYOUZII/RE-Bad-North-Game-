extends Control
## 원정 지도 화면 (이웃 섬 고르기)
##
## 왼쪽: 섬 지도. 밝게 빛나는 섬(지금 갈 수 있는 섬)을 누르면 그 섬을 지키러 가서 전투가 시작됩니다.
## 오른쪽: 이번에 데려갈 분대 요약. 지휘관 관리(레벨업, 기술, 장비, 상점)는 본 섬 화면(home_screen.gd)에서 합니다.

signal battle_requested(node_id: int)
signal home_requested

const UnitDefs := preload("res://scripts/battle/unit_defs.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const MAP_MARGIN := Vector2(70, 90)

var _map_area: Control
var _deploy_box: VBoxContainer
var _gold_label: Label
var _info_label: Label
var _node_buttons: Dictionary = {}


func _ready() -> void:
	# 부모가 Control이 아니어서 화면 크기를 직접 맞춤
	get_viewport().size_changed.connect(_fit_to_screen)
	_fit_to_screen()
	# 못 누르는(회색) 버튼 글씨도 읽히게
	theme = Theme.new()
	theme.set_color("font_disabled_color", "Button", Color(0.72, 0.72, 0.72))
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.20, 0.27)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_map_area = Control.new()
	_map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_area.size_flags_stretch_ratio = 2.0
	_map_area.draw.connect(_draw_links)
	_map_area.resized.connect(_layout_nodes)
	root.add_child(_map_area)

	var side := PanelContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size = Vector2(460, 0)
	root.add_child(side)
	var scroll := ScrollContainer.new()
	side.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)

	var title := _label("원정 지도", 28)
	vb.add_child(title)
	_gold_label = _label("", 22)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vb.add_child(_gold_label)
	_info_label = _label("", 16)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info_label)
	vb.add_child(HSeparator.new())
	vb.add_child(_label("데려갈 분대", 20))
	_deploy_box = VBoxContainer.new()
	_deploy_box.add_theme_constant_override("separation", 4)
	vb.add_child(_deploy_box)
	vb.add_child(HSeparator.new())
	var home := Button.new()
	home.text = "← 본 섬으로 돌아가 정비"
	home.custom_minimum_size = Vector2(0, 48)
	home.add_theme_font_size_override("font_size", 18)
	home.pressed.connect(func(): home_requested.emit())
	vb.add_child(home)

	var map_title := _label("지켜 줄 이웃 섬을 고르세요. 오른쪽 끝 [%s]을 지키면 원정 성공!" % Game.ISLAND_NAMES[-1], 20)
	map_title.position = Vector2(24, 20)
	_map_area.add_child(map_title)

	for node in Game.map_nodes:
		var b := Button.new()
		b.custom_minimum_size = Vector2(120, 56)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on_node_pressed.bind(int(node["id"])))
		_map_area.add_child(b)
		_node_buttons[int(node["id"])] = b

	Game.changed.connect(_refresh)
	_refresh()
	_layout_nodes.call_deferred()


func _fit_to_screen() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _node_pos(node: Dictionary) -> Vector2:
	var area := _map_area.size - MAP_MARGIN * 2.0
	var x := MAP_MARGIN.x + area.x * float(node["col"]) / float(Game.COLUMNS - 1)
	var y := MAP_MARGIN.y + area.y * Game._row_pos(node)
	return Vector2(x, y)


func _layout_nodes() -> void:
	for node in Game.map_nodes:
		var b: Button = _node_buttons[int(node["id"])]
		b.position = _node_pos(node) - b.custom_minimum_size * 0.5
	_map_area.queue_redraw()


func _draw_links() -> void:
	var reach := Game.reachable_nodes()
	for node in Game.map_nodes:
		for t in node["links"]:
			var a := _node_pos(node)
			var b := _node_pos(Game.map_nodes[t])
			var active: bool = int(node["id"]) == Game.current_node and (t in reach)
			var col := Color(1.0, 0.9, 0.4, 0.9) if active else Color(1, 1, 1, 0.18)
			_map_area.draw_line(a, b, col, 4.0 if active else 2.0, true)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var reach := Game.reachable_nodes()
	for node in Game.map_nodes:
		var id := int(node["id"])
		var b: Button = _node_buttons[id]
		var tags := ""
		if bool(node["recruit"]):
			tags += " +지휘관"
		var mark := "✔ " if bool(node["cleared"]) else ("✖ " if bool(node.get("lost", false)) else "")
		b.text = "%s%s\n위험 %d%s" % [mark, str(node["name"]), int(node["difficulty"]), tags]
		b.disabled = not (id in reach)
		if id == Game.current_node:
			b.modulate = Color(0.6, 1.0, 0.6)
		elif id in reach:
			b.modulate = Color(1.0, 0.95, 0.6)
		elif bool(node["cleared"]):
			b.modulate = Color(0.7, 0.8, 0.7)
		else:
			b.modulate = Color(0.9, 0.9, 0.95)
	_gold_label.text = "골드: %d" % Game.gold
	_info_label.text = "지켜 낸 섬 %d개.\n지킨 섬은 남은 집마다 골드로 보답합니다. 집이 모두 불타면 그 섬을 잃습니다(보상 없음, ✖).\n분대가 전멸하면 지휘관은 영영 돌아오지 않습니다.\n'+지휘관' 섬을 지키면 새 지휘관(민병)이 합류합니다." % Game.islands_cleared

	for c in _deploy_box.get_children():
		c.queue_free()
	for c in Game.deployed_commanders():
		var line := "%s  %s Lv%d  병사 %d명" % [str(c["name"]), UnitDefs.display_name(str(c["cls"])), int(c["level"]), Game.soldiers_for(c)]
		if bool(c.get("skill", false)):
			line += "  기술:" + Catalog.skill_name(str(c["cls"]))
		if str(c.get("item", "")) != "":
			line += "  장비:" + Catalog.item_name(str(c["item"]))
		var l := _label(line, 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_deploy_box.add_child(l)
	_map_area.queue_redraw()


func _on_node_pressed(id: int) -> void:
	if id in Game.reachable_nodes():
		battle_requested.emit(id)
