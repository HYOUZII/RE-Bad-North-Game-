extends RefCounted
## 골드로 사는 것들의 목록: 병종 기술, 장비(아이템), 비용
##
## 숫자만 바꿔도 밸런스가 바뀝니다.
## - 기술: 지휘관마다 한 번 배우면 전투 중 F 키(또는 화면 아래 버튼)로 씁니다. 다시 쓰려면 기다려야 함(cooldown).
## - 장비: 지휘관 한 명에 하나만 달 수 있고, 한 번 달면 뗄 수 없습니다.
##   active = true 인 장비는 전투마다 한 번 G 키로 씁니다. 나머지는 항상 효과가 있습니다.

const SKILL_COST := 8
const ITEM_COST := 9
const RECRUIT_COST := 7

## buff: 기술을 쓰는 동안 곱해지는 배율
##   speed 이동속도, damage 공격력, knock 넉백, mass 무게(클수록 안 밀림),
##   ranged_taken 받는 화살 피해, range 활 사거리, ranged_cd 활 쏘는 간격
const SKILLS := {
	"infantry": {"name": "방패 돌격", "desc": "4초 동안 빠르게 달리며 적을 크게 밀쳐 내고 화살을 완전히 막음",
		"duration": 4.0, "cooldown": 22.0, "buff": {"speed": 1.8, "knock": 2.2, "ranged_taken": 0.0}},
	"archer": {"name": "일제 사격", "desc": "4초 동안 화살을 4배 빠르게, 30% 더 멀리 쏨",
		"duration": 4.0, "cooldown": 20.0, "buff": {"ranged_cd": 0.25, "range": 1.3}},
	"pikeman": {"name": "창벽", "desc": "5초 동안 공격력·넉백 1.5배, 거의 밀려나지 않음",
		"duration": 5.0, "cooldown": 22.0, "buff": {"damage": 1.5, "knock": 1.6, "mass": 5.0}},
}

const ITEMS := {
	"bomb": {"name": "화약 단지", "desc": "전투마다 1번: 분대 근처 적 무리에 폭발(피해 + 사방으로 날려 버림)", "active": true},
	"horn": {"name": "뿔나팔", "desc": "전투마다 1번: 쓰러진 병사가 그 자리에서 모두 돌아옴", "active": true},
	"armor": {"name": "철갑 조끼", "desc": "항상: 병사 체력 +30%", "active": false},
	"boots": {"name": "가죽 장화", "desc": "항상: 이동 속도 +30%", "active": false},
	"banner": {"name": "지휘 깃발", "desc": "항상: 분대 병사 +2명", "active": false},
}

## 폭탄 수치
const BOMB_DAMAGE := 28.0
const BOMB_RADIUS := 1.4
const BOMB_KNOCK := 4.0
const BOMB_REACH := 4.0   # 분대 중심에서 이 거리 안의 적만 노림


static func skill_name(cls: String) -> String:
	return str(SKILLS.get(cls, {}).get("name", ""))


static func item_name(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", ""))


static func item_desc(id: String) -> String:
	return str(ITEMS.get(id, {}).get("desc", ""))


static func item_active(id: String) -> bool:
	return bool(ITEMS.get(id, {}).get("active", false))
