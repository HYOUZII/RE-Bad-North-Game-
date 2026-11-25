extends Node3D
## 게임 시작점. 지금(1단계)은 섬 하나를 만들고 카메라로 둘러볼 수 있게만 합니다.
## - R: 새 섬 생성
## - 화면 왼쪽 위에 조작법과 AI 연결 상태 표시

const IslandGenerator := preload("res://scripts/island/island_generator.gd")
const OrbitCamera := preload("res://scripts/camera/orbit_camera.gd")

@export var island_seed: int = 0  # 0이면 매번 랜덤

var island: Node3D
var _label: Label


func _ready() -> void:
	_setup_world()
	island = IslandGenerator.new()
	island.name = "Island"
	add_child(island)
	_new_island()

	var cam := OrbitCamera.new()
	cam.name = "OrbitCamera"
	add_child(cam)

	_setup_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_new_island()


func _new_island() -> void:
	var s := island_seed if island_seed != 0 else randi()
	island.generate(s)
	if _label:
		_update_hud(s)


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.90)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.78, 0.86)
	env.fog_density = 0.01
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	# 바다: 섬 아래 넓은 평면
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	sea.mesh = plane
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color(0.24, 0.49, 0.65)
	sea_mat.roughness = 0.3
	sea.material_override = sea_mat
	sea.position.y = 0.02
	sea.name = "Sea"
	add_child(sea)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)
	_update_hud(0)


func _update_hud(seed_value: int) -> void:
	var ai_state := "꺼짐" if not AI.is_enabled() else "%s (%s)" % [AI.provider, AI.model]
	_label.text = "Isle Defense - 1단계 뼈대\n우클릭 드래그 / Q,E: 회전   휠: 확대·축소   R: 새 섬\n섬 시드: %d   AI: %s" % [seed_value, ai_state]
