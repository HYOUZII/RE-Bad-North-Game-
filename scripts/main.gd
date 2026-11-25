extends Node3D
## 게임 시작점. 화면 전환만 담당합니다.
##
## 흐름: 타이틀 → 원정 지도 → 섬 전투 → (승리) 원정 지도 → ... → 최종 섬 승리 또는 전멸
## 각 화면은 따로 만든 스크립트가 맡고, 여기서는 갈아 끼우기만 합니다.

const Battle := preload("res://scripts/battle/battle.gd")
const CampaignScreen := preload("res://scripts/ui/campaign_screen.gd")

var _current: Node


func _ready() -> void:
	_show_title()


func _swap(n: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = n
	add_child(n)


func _show_title() -> void:
	_swap(_message_screen(
		"Isle Defense",
		"작은 섬들을 침략자로부터 지키며 바다 끝 성채까지 나아가세요.\n\n분대를 골라 칸을 클릭하면 이동합니다. 전투는 자동으로 벌어집니다.\n높은 곳은 유리하고, 적을 바다로 밀어내면 즉사합니다.\n보병은 화살을 막고, 궁수는 배를 쏘고, 창병은 거한을 잡습니다.",
		"새 원정 시작",
		func():
			Game.new_run()
			_show_campaign()))


func _show_campaign() -> void:
	var s := CampaignScreen.new()
	s.battle_requested.connect(_start_battle)
	_swap(s)


func _start_battle(node_id: int) -> void:
	var b := Battle.new()
	b.setup(Game.map_nodes[node_id], Game.roster)
	b.battle_ended.connect(_on_battle_ended.bind(node_id))
	_swap(b)


func _on_battle_ended(result: Dictionary, node_id: int) -> void:
	Game.apply_battle_result(node_id, result)
	if Game.run_over:
		if Game.run_won:
			_swap(_message_screen("원정 성공!", "바다 끝 성채를 지켜 냈습니다.\n지킨 섬 %d개, 살아남은 지휘관 %d명" % [Game.islands_cleared, Game.roster.size()], "처음으로", _show_title))
		else:
			_swap(_message_screen("원정 실패", "모든 지휘관을 잃었습니다.\n지킨 섬 %d개" % Game.islands_cleared, "처음으로", _show_title))
	else:
		_show_campaign()


func _message_screen(title: String, body: String, button_text: String, on_press: Callable) -> Control:
	var root := Control.new()
	# 부모가 Control이 아니어서 화면 크기를 직접 맞춤
	root.size = get_viewport().get_visible_rect().size
	var root_ref: WeakRef = weakref(root)
	get_viewport().size_changed.connect(func():
		var r = root_ref.get_ref()
		if r != null:
			r.size = get_viewport().get_visible_rect().size)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.20, 0.27)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	center.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 48)
	vb.add_child(t)
	var b := Label.new()
	b.text = body
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 20)
	vb.add_child(b)
	var ai_state := "AI: 꺼짐" if not AI.is_enabled() else "AI: %s (%s)" % [AI.provider, AI.model]
	var a := Label.new()
	a.text = ai_state
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.add_theme_font_size_override("font_size", 14)
	a.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(a)
	var btn := Button.new()
	btn.text = button_text
	btn.custom_minimum_size = Vector2(260, 56)
	btn.add_theme_font_size_override("font_size", 24)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(on_press)
	vb.add_child(btn)
	return root
