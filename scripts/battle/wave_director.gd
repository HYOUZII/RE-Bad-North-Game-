extends RefCounted
## 적 웨이브 구성표 만들기
##
## 결과 형식: waves[웨이브][배] = ["raider", "raider_archer", ...] (배 한 척에 탄 적 목록)
## 난이도(difficulty)가 오를수록 웨이브 수, 배 수, 배 크기, 강한 적 비율이 늘어납니다.

const BOAT_SEATS := 6


static func build(difficulty: int, rng: RandomNumberGenerator, is_final: bool = false) -> Array:
	var waves: Array = []
	var wave_count: int = 2 + (difficulty + 1) / 3
	for w in range(wave_count):
		var boats: Array = []
		var boat_count: int = clampi(1 + (w + difficulty) / 4, 1, 5)
		if is_final and w == wave_count - 1:
			boat_count = 4  # 마지막 섬의 마지막 웨이브는 배 4척 총공격
		for _b in range(boat_count):
			boats.append(_fill_boat(difficulty, w, rng, is_final))
		waves.append(boats)
	return waves


static func _fill_boat(difficulty: int, wave: int, rng: RandomNumberGenerator, is_final: bool) -> Array:
	var seats: int = clampi(3 + difficulty / 2 + wave / 2, 3, BOAT_SEATS)
	var crew: Array = []
	# 거한: 난이도 2부터, 자리를 2칸 차지
	var brute_chance: float = clamp(0.12 * float(difficulty - 1), 0.0, 0.6)
	if difficulty >= 2 and rng.randf() < brute_chance:
		crew.append("brute")
		seats -= 2
	var archer_chance: float = 0.0 if difficulty < 1 else clamp(0.12 + 0.04 * float(difficulty), 0.0, 0.4)
	# 방패 약탈자: 난이도 2부터. 한 배에 몰아서 태워 상성 판단을 요구함
	var shield_boat: bool = difficulty >= 2 and rng.randf() < clamp(0.1 * float(difficulty), 0.0, 0.45)
	for _i in range(seats):
		if shield_boat and rng.randf() < 0.7:
			crew.append("shield_raider")
		else:
			crew.append("raider_archer" if rng.randf() < archer_chance else "raider")
	return crew


## 적 능력치 배율 (난이도가 오를수록 조금씩 강해짐)
static func enemy_hp_mult(difficulty: int) -> float:
	return 1.15 + 0.14 * float(difficulty)


static func enemy_dmg_mult(difficulty: int) -> float:
	return 1.1 + 0.09 * float(difficulty)
