// 절벽 바위 셰이더 (임시 바위 조각과 사용자 .glb 조각 모두에 씀)
// - 면마다 각지게 빛을 받음 (모델의 매끈한 법선 대신 삼각형 면 방향을 직접 계산)
// - 옆면: 가로 지층 줄무늬 (높이 + 약간의 노이즈) → 켜켜이 깎인 바위 느낌
// - 위를 보는 면: 이끼(풀색)가 덮임 → 바위턱 위에 풀이 자란 느낌
// - 물에 가까운 아래쪽: 젖은 듯 어둡게
// 조각마다 다른 색 변화는 instance uniform "tint" 로 줌 (cliff_mesh.gd 에서 설정)
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 rock_light : source_color = vec3(0.68, 0.69, 0.65);
uniform vec3 rock_dark : source_color = vec3(0.47, 0.49, 0.47);
uniform vec3 moss : source_color = vec3(0.40, 0.51, 0.35);
uniform vec3 wet : source_color = vec3(0.33, 0.37, 0.37);
uniform float band_height = 0.28;
uniform float wet_height = 0.45;
instance uniform vec3 tint = vec3(1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// 면 방향 (카메라 쪽을 보게)
	vec3 n = normalize(cross(dFdx(wpos), dFdy(wpos)));
	vec3 to_cam = CAMERA_POSITION_WORLD - wpos;
	if (dot(n, to_cam) < 0.0) {
		n = -n;
	}
	// 지층 줄: 높이를 줄 높이로 나눈 값의 소수 부분. 노이즈로 줄이 살짝 기울고 끊김
	float warp = vnoise(wpos.xz * 1.3) * 0.7 + vnoise(wpos.xz * 4.1) * 0.25;
	float b = wpos.y / band_height + warp;
	float layer = floor(b);
	float f = fract(b);
	float layer_shade = hash12(vec2(layer, 7.0)) * 0.35;          // 줄마다 밝기가 조금 다름
	float groove = smoothstep(0.0, 0.12, f) * (1.0 - smoothstep(0.88, 1.0, f));  // 줄 사이 틈은 어둡게
	float speck = vnoise(wpos.xz * 9.0 + wpos.y * 5.0) * 0.12;
	vec3 col = mix(rock_dark, rock_light, clamp(0.35 + layer_shade + groove * 0.35 + speck, 0.0, 1.0));
	// 물가는 젖은 색
	col = mix(wet, col, smoothstep(0.0, wet_height, wpos.y));
	// 위를 보는 면은 이끼
	float up = smoothstep(0.6, 0.88, n.y);
	col = mix(col, moss * (0.9 + speck), up * 0.9);
	ALBEDO = col * tint;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
