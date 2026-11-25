extends Sprite3D
## 8방향 그림 병사 (Assets.get_model이 병사 그림이 있을 때 만들어 줌)
##
## 그림 한 장(스프라이트 시트) = 가로 14칸 × 세로 8줄, 한 칸 144px.
## - 줄(세로): 병사가 보는 방향 8개. 0 = 카메라 쪽(정면), 2 = 화면 오른쪽, 4 = 뒷모습, 6 = 왼쪽
## - 칸(가로): 0~3 서 있기, 4~9 공격, 10~13 맞음
## 병사 노드(unit.gd)가 몸을 돌리면, 그 방향과 카메라 방향을 비교해서 알맞은 줄을 고릅니다.

const TILE := 144.0          # 한 칸 크기(px)
const FOOT_Y := 97.25        # 한 칸 안에서 발바닥 위치(px, 위에서부터)
const BODY_PX := 34.0        # 그림 속 병사 키(px)
const BODY_M := 0.45         # 게임 속 병사 키(m)
const IDLE_FPS := 5.0
const ACT_FPS := 10.0

var action := "idle"   # "idle" | "attack" | "hit"
var elapsed := 0.0
var phase := 0.0       # 병사마다 숨쉬기 박자를 조금씩 다르게


func setup(tex: Texture2D, body_scale: float, tint: Color) -> void:
	texture = tex
	hframes = 14
	vframes = 8
	billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 그림이 늘 카메라를 정면으로 봄(그림 자체가 45도 위에서 본 모습)
	shaded = false
	double_sided = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	alpha_scissor_threshold = 0.2
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	modulate = tint
	pixel_size = BODY_M * body_scale / BODY_PX
	# 발바닥이 노드 원점(땅)에 오도록 그림을 위로 올림
	centered = true
	offset = Vector2(0.0, FOOT_Y - TILE * 0.5)  # Sprite3D는 위쪽이 +
	phase = randf()


## 동작 재생: "attack" 또는 "hit"
func play(next: String) -> void:
	action = next
	elapsed = 0.0


func _process(dt: float) -> void:
	elapsed += dt
	var col := 0
	if action == "attack" and elapsed < 6.0 / ACT_FPS:
		col = 4 + mini(5, int(elapsed * ACT_FPS))
	elif action == "hit" and elapsed < 4.0 / ACT_FPS:
		col = 10 + mini(3, int(elapsed * ACT_FPS))
	else:
		action = "idle"
		col = int((elapsed + phase) * IDLE_FPS) % 4
	frame = _row() * 14 + col


## 병사가 보는 방향(부모 노드의 -Z)을 카메라 기준 8방향 줄 번호로 바꿈
func _row() -> int:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var body := get_parent_node_3d()
	if cam == null or body == null:
		return 0
	var heading := -body.global_basis.z
	heading.y = 0.0
	var right := cam.global_basis.x
	right.y = 0.0
	if heading.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return 0
	right = right.normalized()
	var toward_cam := right.cross(Vector3.UP)  # 카메라 쪽을 향하는 수평 방향
	var ang := atan2(heading.dot(right), heading.dot(toward_cam))
	return posmod(roundi(ang * 4.0 / PI), 8)
