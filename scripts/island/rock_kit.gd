extends RefCounted
## 절벽 바위 조각 (임시 모델 만들기 + 공용 셰이더)
##
## 섬 그리기(cliff_mesh.gd)는 절벽 외곽선을 따라 "바위 조각"을 하나씩 세웁니다.
## 조각 모델은 Assets.get_rock_piece() 가 고릅니다:
##   assets/models/rock_kit/<종류>_01.glb 같은 파일이 있으면 그것(사용자가 Meshy/Tripo로 만든 것),
##   없으면 여기서 만든 임시 바위(각진 면 + 가로 지층 줄)를 씁니다.
##
## 조각 하나의 약속 (파일 모델도 똑같이 맞춰 넣음):
##   - 원점: 바닥 가운데. 가로(X) = 외곽선 한 토막 길이, 높이(Y) = 절벽 높이
##   - 앞(바위 얼굴) = -Z = 바깥(낮은 쪽). 뒤(+Z)는 땅 속이라 안 보임
##   - 맨 위는 풀밭 높이와 같음. 앞쪽으로 조금(최대 FRONT_OUT) 튀어나옴

## 조각 종류 → 설명. docs/TERRAIN_KIT.md 표와 같음
const KINDS := {
	"cliff": "곧은 절벽 한 단 (가로 1m)",
	"cliff_tall": "곧은 절벽 두 단 이상 (가로 1m)",
	"cliff_corner_out": "바깥 모서리(튀어나온 곳)를 비스듬히 깎은 면 (가로 0.71m)",
	"cliff_corner_in": "안쪽 모서리(파인 곳)를 비스듬히 잇는 면 (가로 0.71m)",
	"shore_rock": "바닷가 낮은 땅 가장자리 바위턱",
}

const FRONT_OUT := 0.13   # 앞으로 튀어나오는 최대 깊이(m). 크면 아래 칸 병사가 바위에 파묻혀 보임
const BACK_IN := 0.25     # 땅 속으로 들어가는 깊이(m)
const OVERLAP := 1.14     # 이웃 조각과 겹치게 가로를 조금 넓힘 (틈이 안 보이게)
const BAND_H := 0.28      # 지층 한 줄 높이(m)

const SHADER_PATH := "res://assets/shaders/terrain_rock.gdshader"

static var _mesh_cache: Dictionary = {}
static var _material: ShaderMaterial = null


## 모든 바위 조각이 함께 쓰는 재질 (윗면 이끼, 옆면 지층 줄, 물가 어두움)
static func rock_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH) as Shader
	return _material


## 임시 바위 조각 메시. 같은 (종류, 번호, 크기)는 한 번만 만들어 재사용
static func placeholder_mesh(kind: String, variant: int, size: Vector3) -> ArrayMesh:
	var key := "%s|%d|%.2f|%.2f" % [kind, variant, size.x, size.y]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var mesh := _build(kind, size, rng)
	_mesh_cache[key] = mesh
	return mesh


## 바위 얼굴 만들기
## 가로로 몇 칸, 세로로 지층 줄마다 점을 찍고, 점마다 앞뒤로 조금씩 밀어서 각진 면을 만듭니다.
## 지층 줄마다 "위는 들어가고 아래는 튀어나오게" 해서 켜켜이 쌓인 바위턱이 보이게 합니다.
static func _build(kind: String, size: Vector3, rng: RandomNumberGenerator) -> ArrayMesh:
	var w := size.x * OVERLAP
	var h := size.y
	var shore := kind == "shore_rock"
	var cols := maxi(3, int(round(w / 0.24)) + 1)
	# 세로 줄 높이 목록 (아래 → 위). 지층마다 [턱 아래, 턱 위] 두 줄
	var ys: Array[float] = [0.0]
	var y := 0.0
	var band := BAND_H * (0.7 if shore else 1.0)
	while y + band * 1.3 < h:
		y += band * rng.randf_range(0.75, 1.3)
		ys.append(y)
		ys.append(minf(y + 0.05, h - 0.05))
	ys.append(h - 0.07)   # 윗 테두리(살짝 둥근 턱)
	ys.append(h - 0.012)  # 풀밭보다 살짝 아래 (같은 높이면 깜빡임)
	# 점마다 앞으로 튀어나온 정도 (0 = 외곽선, 음수 Z = 바깥)
	var grid: Array = []
	for j in range(ys.size()):
		var row: Array[Vector3] = []
		var t := ys[j] / maxf(h, 0.01)
		var is_ledge := j > 0 and j < ys.size() - 2 and (j % 2 == 0)
		for i in range(cols):
			var u := float(i) / float(cols - 1)
			var x := lerpf(-w * 0.5, w * 0.5, u)
			if i > 0 and i < cols - 1:
				x += rng.randf_range(-0.06, 0.06)
			var out := 0.04 + rng.randf_range(0.0, 0.06)
			out += (1.0 - t) * (0.14 if shore else 0.04)   # 아래쪽이 조금 넓음 (바닷가 턱은 비탈)
			if is_ledge:
				out += 0.035   # 턱: 바로 아래 줄보다 앞으로 나옴
			var side := absf(u - 0.5) * 2.0
			out *= 1.0 - side * side * 0.55   # 양 끝은 뒤로 물러나서 옆 조각과 자연스럽게 겹침
			if j == ys.size() - 1:
				out = 0.02   # 맨 윗줄은 외곽선(풀밭 가장자리)에 딱 붙음
			elif j == ys.size() - 2:
				out = minf(out, 0.07)
			row.append(Vector3(x, ys[j], -minf(out, FRONT_OUT)))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # 면마다 따로 빛을 받음 → 각진 로우폴리 바위
	for j in range(ys.size() - 1):
		for i in range(cols - 1):
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j + 1][i]
			# 대각선 방향을 섞어서 삼각형 무늬가 반복되지 않게
			if rng.randf() < 0.5:
				_tri(st, a, d, c)
				_tri(st, a, c, b)
			else:
				_tri(st, a, d, b)
				_tri(st, b, d, c)
	# 양 옆과 윗면 뒤쪽을 막음 (비스듬히 보면 속이 비어 보이지 않게)
	for j in range(ys.size() - 1):
		var l0: Vector3 = grid[j][0]
		var l1: Vector3 = grid[j + 1][0]
		_quad(st, Vector3(l0.x, l0.y, BACK_IN), l0, l1, Vector3(l1.x, l1.y, BACK_IN))
		var r0: Vector3 = grid[j][cols - 1]
		var r1: Vector3 = grid[j + 1][cols - 1]
		_quad(st, r0, Vector3(r0.x, r0.y, BACK_IN), Vector3(r1.x, r1.y, BACK_IN), r1)
	for i in range(cols - 1):
		var p0: Vector3 = grid[ys.size() - 1][i]
		var p1: Vector3 = grid[ys.size() - 1][i + 1]
		_quad(st, p0, p1, Vector3(p1.x, p1.y, BACK_IN), Vector3(p0.x, p0.y, BACK_IN))
	st.generate_normals()
	return st.commit()


## 앞에서 봤을 때 시계 방향 = 앞면 (Godot 기본)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, d, c)
	_tri(st, a, c, b)
