extends RefCounted
## 적 웨이브 구성표 만들기
##
## 결과 형식: waves[웨이브][배] = ["raider", "raider_archer", ...] (배 한 척에 탄 적 목록)
## 난이도(difficulty)가 오를수록 웨이브 수, 배 수, 배 크기, 강한 적 비율이 늘어납니다.

const BOAT_SEATS := 6


static func build(difficulty: int, rng: RandomNumberGenerator, is_final: bool = false) -> Array:
	var waves: Array = []
	var wave_count: int = 2 + difficulty / 2 + (1 if is_final else 0)
	for w in range(wave_count):
		var boats: Array = []
		var boat_count: int = clampi(1 + (w + difficulty) / 3, 1, 4)
		if is_final and w == wave_count - 1:
			boat_count = 4
		for _b in range(boat_count):
			boats.append(_fill_boat(difficulty, w, rng, is_final))
		waves.append(boats)
	return waves


static func _fill_boat(difficulty: int, wave: int, rng: RandomNumberGenerator, is_final: bool) -> Array:
	var seats: int = clampi(3 + difficulty / 2 + wave / 2, 3, BOAT_SEATS)
	if is_final:
		seats = BOAT_SEATS
	var crew: Array = []
	# 거한: 난이도 2부터, 자리를 2칸 차지
	var brute_chance: float = clamp(0.12 * float(difficulty - 1), 0.0, 0.6)
	if difficulty >= 2 and rng.randf() < brute_chance:
		crew.append("brute")
		seats -= 2
	var archer_chance: float = 0.0 if difficulty < 1 else clamp(0.12 + 0.04 * float(difficulty), 0.0, 0.4)
	for _i in range(seats):
		crew.append("raider_archer" if rng.randf() < archer_chance else "raider")
	return crew


## 적 능력치 배율 (난이도가 오를수록 조금씩 강해짐)
static func enemy_hp_mult(difficulty: int) -> float:
	return 1.0 + 0.08 * float(difficulty)


static func enemy_dmg_mult(difficulty: int) -> float:
	return 1.0 + 0.05 * float(difficulty)
