extends Node3D
## 지켜야 할 마을 집. 전투가 끝날 때 멀쩡한 집 수만큼 골드를 받습니다.
## 아군 분대가 멀쩡한 집 칸에 서 있으면 병사가 회복됩니다.

var cell := Vector2i.ZERO
var max_hp := 60.0
var hp := 60.0
var intact := true
var gold := 2
var _model: Node3D
var _label: Label3D


func setup(p_cell: Vector2i, p_gold: int, rot_steps: int) -> void:
	cell = p_cell
	gold = p_gold
	_model = Assets.get_model("house")
	_model.rotation.y = rot_steps * PI * 0.5
	add_child(_model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.85
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)
	_refresh_label()


## 피해를 받고, 이번 공격으로 불탔으면 true
func take_damage(dmg: float) -> bool:
	if not intact:
		return false
	hp = max(0.0, hp - dmg)
	if hp <= 0.0:
		intact = false
		_model.queue_free()
		_model = Assets.get_model("house_burned")
		add_child(_model)
		_refresh_label()
		return true
	_refresh_label()
	return false


func _refresh_label() -> void:
	if not intact:
		_label.text = "불탐"
		_label.modulate = Color(0.6, 0.6, 0.6)
	elif hp < max_hp:
		_label.text = "%dG  %d%%" % [gold, int(round(hp / max_hp * 100.0))]
		_label.modulate = Color(1.0, 0.55, 0.35)
	else:
		_label.text = "%dG" % gold
		_label.modulate = Color(1.0, 0.88, 0.35)
