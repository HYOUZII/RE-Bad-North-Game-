extends RefCounted
## 유닛 능력치 표 (아군 병종 + 적 종류)
##
## 숫자만 바꿔도 밸런스가 바뀝니다. 단위: 거리 m(타일 1칸 = 1m), 시간 초.
## - hp: 체력            - damage: 근접 공격력      - reach: 근접 사거리(몸 표면 기준)
## - cooldown: 근접 공격 간격  - windup: 휘두르기 시작~맞을 때까지 시간(이때 밀려나면 공격 취소)
## - speed: 이동 속도     - knock: 근접 넉백 세기   - mass: 무게(클수록 덜 밀림)
## - radius: 몸 반지름    - ranged_taken: 화살 피해 배율(방패=0.25)
## - range / ranged_damage / ranged_cooldown: 활 사거리, 화살 공격력, 활 공격 간격 (range 0 = 활 없음)
## - aggro: 적이 아군을 발견하고 쫓아가는 거리
## - house_damage: 집 공격력  - large: 큰 몸집 여부   - bonus_vs_large: 큰 적에게 주는 피해 배율

const DEFAULTS := {
	"name": "?",
	"hp": 20.0,
	"damage": 5.0,
	"reach": 0.25,
	"cooldown": 1.0,
	"windup": 0.25,
	"speed": 1.5,
	"knock": 1.0,
	"ranged_knock": 0.4,
	"mass": 1.0,
	"radius": 0.14,
	"ranged_taken": 1.0,
	"range": 0.0,
	"ranged_damage": 0.0,
	"ranged_cooldown": 2.0,
	"aggro": 1.8,
	"house_damage": 5.0,
	"large": false,
	"bonus_vs_large": 1.0,
}

const TYPES := {
	# ---- 아군 병종 ----
	# 보병: 방패로 화살을 막고 버티는 기본 병종. 궁수 상대로 강함.
	"infantry": {"name": "보병", "hp": 30.0, "damage": 7.0, "reach": 0.28, "cooldown": 0.9, "windup": 0.2,
		"speed": 1.6, "knock": 1.2, "mass": 1.3, "ranged_taken": 0.25},
	# 궁수: 멀리서 화살 일제 사격. 배에 탄 적도 맞힘. 높은 곳에서 사거리·피해 증가. 근접은 약함.
	"archer": {"name": "궁수", "hp": 18.0, "damage": 3.0, "reach": 0.22, "cooldown": 1.1, "windup": 0.25,
		"speed": 1.8, "knock": 0.6, "range": 5.5, "ranged_damage": 6.0, "ranged_cooldown": 2.0},
	# 창병: 긴 사거리와 강한 넉백. 거한(큰 적)에게 2배 피해. 화살에 약함.
	"pikeman": {"name": "창병", "hp": 26.0, "damage": 9.0, "reach": 0.6, "cooldown": 1.2, "windup": 0.15,
		"speed": 1.5, "knock": 3.0, "mass": 1.1, "ranged_taken": 1.3, "bonus_vs_large": 2.0},
	# 민병: 아직 병종이 없는 신병. 골드로 승급시킬 수 있음.
	"militia": {"name": "민병", "hp": 18.0, "damage": 5.0, "reach": 0.25, "cooldown": 1.1, "windup": 0.25,
		"speed": 1.6, "knock": 0.9},

	# ---- 적 ----
	"raider": {"name": "약탈자", "hp": 16.0, "damage": 5.0, "reach": 0.25, "cooldown": 1.1, "windup": 0.3,
		"speed": 1.4, "knock": 0.9, "aggro": 1.8, "house_damage": 6.0},
	"raider_archer": {"name": "약탈자 궁수", "hp": 13.0, "damage": 2.0, "reach": 0.22, "cooldown": 1.2,
		"speed": 1.4, "knock": 0.5, "range": 5.0, "ranged_damage": 4.0, "ranged_cooldown": 2.6,
		"aggro": 5.0, "house_damage": 3.0},
	"brute": {"name": "거한", "hp": 80.0, "damage": 13.0, "reach": 0.35, "cooldown": 2.0, "windup": 0.55,
		"speed": 1.0, "knock": 3.6, "mass": 3.0, "radius": 0.28, "aggro": 1.6, "house_damage": 20.0,
		"large": true},
}

## 아군 승급 가능한 병종
const PLAYER_CLASSES := ["infantry", "archer", "pikeman"]


static func get_def(id: String) -> Dictionary:
	var d: Dictionary = DEFAULTS.duplicate()
	d.merge(TYPES.get(id, {}), true)
	d["id"] = id
	return d


static func display_name(id: String) -> String:
	return str(TYPES.get(id, {}).get("name", id))
