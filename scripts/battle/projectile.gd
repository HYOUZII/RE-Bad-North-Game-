extends Node3D
## 화살 한 발: 쏜 순간 정한 지점으로 포물선을 그리며 날아가고, 떨어진 자리 근처의 적에게 맞습니다.
## 그래서 움직이는 적에게는 빗나갈 수도 있습니다.

var battle
var info: Dictionary = {}   # 쏜 유닛 정보(battle.attack_info) - 쏜 유닛이 죽어도 화살은 계속 날아감
var damage := 0.0
var start := Vector3.ZERO
var end := Vector3.ZERO
var _t := 0.0
var _dur := 1.0
var _arc := 0.5


func setup(p_battle, p_info: Dictionary, target_pos: Vector3, p_damage: float) -> void:
	battle = p_battle
	info = p_info
	damage = p_damage
	start = Vector3(info["pos"]) + Vector3(0, 0.35, 0)
	end = target_pos + Vector3(0, 0.2, 0)
	var d := Vector2(end.x - start.x, end.z - start.z).length()
	_dur = 0.35 + d * 0.09
	_arc = 0.3 + d * 0.12
	position = start
	add_child(Assets.get_model("arrow"))


func flight_time() -> float:
	return _dur


func tick(dt: float) -> void:
	_t += dt
	var k: float = clamp(_t / _dur, 0.0, 1.0)
	var p := start.lerp(end, k)
	p.y += sin(k * PI) * _arc
	var dir := p - position
	if dir.length() > 0.0005:
		# 진행 방향을 보게 회전 (-Z가 앞)
		var flat := Vector2(dir.x, dir.z).length()
		rotation = Vector3(atan2(dir.y, flat), atan2(-dir.x, -dir.z), 0.0)
	position = p
	if k >= 1.0:
		battle.arrow_impact(self)
