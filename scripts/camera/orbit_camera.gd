extends Node3D
## 섬 주위를 도는 카메라
## - 마우스 오른쪽 드래그 또는 Q/E: 회전
## - 마우스 휠: 확대/축소

@export var distance: float = 16.0
@export var min_distance: float = 8.0
@export var max_distance: float = 28.0
@export var pitch_deg: float = -45.0
@export var rotate_speed: float = 0.008
@export var key_rotate_speed: float = 1.8

var yaw: float = PI * 0.25
var camera: Camera3D
var _dragging := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.make_current()
	_update_transform()


func _process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_Q):
		dir += 1.0
	if Input.is_key_pressed(KEY_E):
		dir -= 1.0
	if dir != 0.0:
		yaw += dir * key_rotate_speed * delta
		_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance - 1.0)
			_update_transform()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance + 1.0)
			_update_transform()
	elif event is InputEventMouseMotion and _dragging:
		yaw -= (event as InputEventMouseMotion).relative.x * rotate_speed
		_update_transform()


func _update_transform() -> void:
	rotation = Vector3(deg_to_rad(pitch_deg), yaw, 0.0)
	if camera:
		camera.position = Vector3(0, 0, distance)
