extends Node3D
## 침략자의 배: 바다 멀리서 해안으로 다가와 병사를 내려놓고 돌아갑니다.
## 배에 탄 적은 아군 궁수의 화살에 맞을 수 있습니다(상륙 전에 줄이기).
## 배는 바다로만 다닙니다. 오는 길(approach_dir)은 battle.gd가 섬과 겹치지 않는 방향으로 골라 줍니다.

enum Phase { SAILING, UNLOADING, LEAVING }

const SPEED := 2.2
const SPAWN_DISTANCE := 13.0
const UNLOAD_INTERVAL := 0.35

var battle
var passengers: Array = []
var phase: int = Phase.SAILING
var shore_cell := Vector2i.ZERO
var land_pos := Vector3.ZERO
var out_dir := Vector3.FORWARD
var _unload_t := 0.6
var _leave_t := 0.0


## approach_dir: 배를 대는 곳(land)에서 바다 쪽으로 나가는 방향. 이 직선 위에는 섬이 없음.
func setup(p_battle, p_shore: Vector2i, sea_cell: Vector2i, types: Array, hp_mult: float, dmg_mult: float, approach_dir: Vector3) -> void:
	battle = p_battle
	shore_cell = p_shore
	add_child(Assets.get_model("boat"))
	land_pos = Vector3(sea_cell.x, 0.0, sea_cell.y)
	out_dir = approach_dir.normalized()
	position = land_pos + out_dir * SPAWN_DISTANCE
	_face(land_pos - position)
	for t in types:
		var u = battle.spawn_unit(str(t), 1, position, hp_mult, dmg_mult)
		u.state = u.State.BOAT
		passengers.append(u)
	_update_passengers()


func has_passengers() -> bool:
	return not passengers.is_empty()


func tick(dt: float) -> void:
	passengers = passengers.filter(func(u): return is_instance_valid(u) and u.state == u.State.BOAT)
	match phase:
		Phase.SAILING:
			var to := land_pos - position
			to.y = 0.0
			var d := to.length()
			if d < 0.05:
				phase = Phase.UNLOADING
				battle.boat_landed.emit(self)
			else:
				position += to / d * min(d, SPEED * dt)
				_face(to)
		Phase.UNLOADING:
			_unload_t -= dt
			if _unload_t <= 0.0:
				if passengers.is_empty():
					phase = Phase.LEAVING
				else:
					battle.land_unit(passengers.pop_front(), shore_cell)
					_unload_t = UNLOAD_INTERVAL
		Phase.LEAVING:
			position += out_dir * SPEED * dt
			_face(out_dir)
			_leave_t += dt
			if _leave_t > 6.0:
				battle.remove_boat(self)
				return
	_update_passengers()


func _update_passengers() -> void:
	for i in range(passengers.size()):
		var local := Vector3(0.15 if i % 2 == 0 else -0.15, 0.12, -0.5 + 0.33 * float(i / 2))
		passengers[i].position = position + transform.basis * local
		passengers[i].rotation.y = rotation.y


func _face(dir: Vector3) -> void:
	if dir.x * dir.x + dir.z * dir.z > 0.0001:
		rotation.y = atan2(-dir.x, -dir.z)
