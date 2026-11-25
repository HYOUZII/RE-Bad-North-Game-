extends Node
## 모델 불러오기 담당 (자동 로드 이름: Assets)
##
## 사용법: var node := Assets.get_model("house")
## - res://assets/models/house.glb 가 있으면 그 모델을 씁니다.
## - 없으면 아래 PLACEHOLDERS 표에 적힌 임시 도형을 만들어 줍니다.
## 그래서 나중에 .glb 파일을 폴더에 넣기만 하면 코드 수정 없이 그래픽이 바뀝니다.

const MODEL_DIR := "res://assets/models/"

## 임시 도형 정의. shape: "box" | "capsule" | "cylinder" | "cone"
## size: 가로(x) / 높이(y) / 세로(z), 단위는 미터(타일 1칸 = 1m)
const PLACEHOLDERS := {
	"house":    {"shape": "box",      "size": Vector3(0.55, 0.45, 0.55), "color": Color(0.90, 0.62, 0.40)},
	"infantry": {"shape": "capsule",  "size": Vector3(0.18, 0.45, 0.18), "color": Color(0.30, 0.50, 0.85)},
	"archer":   {"shape": "capsule",  "size": Vector3(0.16, 0.42, 0.16), "color": Color(0.35, 0.75, 0.45)},
	"pikeman":  {"shape": "capsule",  "size": Vector3(0.18, 0.48, 0.18), "color": Color(0.85, 0.80, 0.35)},
	"raider":   {"shape": "capsule",  "size": Vector3(0.20, 0.45, 0.20), "color": Color(0.80, 0.25, 0.25)},
	"boat":     {"shape": "box",      "size": Vector3(0.70, 0.25, 1.60), "color": Color(0.45, 0.30, 0.20)},
	"tree":     {"shape": "cone",     "size": Vector3(0.35, 0.70, 0.35), "color": Color(0.25, 0.50, 0.30)},
}

var _material_cache: Dictionary = {}


func has_custom_model(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + id + ".glb")


## 모델 하나를 새로 만들어 돌려줍니다. 원점(0,0,0)은 모델의 바닥 중앙입니다.
func get_model(id: String) -> Node3D:
	var path := MODEL_DIR + id + ".glb"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			return scene.instantiate() as Node3D
		push_warning("모델을 불러오지 못했습니다: " + path)
	return _make_placeholder(id)


## 색만 지정한 단순 재질. 같은 색은 재사용해서 메모리를 아낍니다.
func get_color_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		_material_cache[key] = mat
	return _material_cache[key]


func _make_placeholder(id: String) -> Node3D:
	var spec: Dictionary = PLACEHOLDERS.get(id, {"shape": "box", "size": Vector3(0.3, 0.3, 0.3), "color": Color.MAGENTA})
	var size: Vector3 = spec["size"]
	var mesh: Mesh
	match spec["shape"]:
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = size.x
			m.height = size.y
			mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = size.x
			m.bottom_radius = size.x
			m.height = size.y
			mesh = m
		"cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = size.x
			m.height = size.y
			mesh = m
		_:
			var m := BoxMesh.new()
			m.size = size
			mesh = m
	var root := Node3D.new()
	root.name = id.capitalize()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = get_color_material(spec["color"])
	mi.position.y = size.y * 0.5  # 바닥이 원점에 오도록 올림
	root.add_child(mi)
	return root
