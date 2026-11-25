extends Node
## 자동 플레이 테스트: 컴퓨터가 지휘하며 원정 전체를 끝까지 진행해 봅니다.
## 실행: godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
## 출력 끝에 "SMOKE_TEST_DONE"이 나오면 성공(오류 없이 끝까지 진행).
## 인자: -- --seed=123 --runs=3

const Battle := preload("res://scripts/battle/battle.gd")
# 아래 스크립트들도 미리 불러서 문법 오류가 있으면 테스트가 실패하게 함
const _Main := preload("res://scripts/main.gd")
const _Campaign := preload("res://scripts/ui/campaign_screen.gd")

var stats := {}


func _ready() -> void:
	var seed_value := 12345
	var runs := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--runs="):
			runs = int(a.substr(7))
	var wins := 0
	var total_islands := 0
	for r in range(runs):
		var won := await _run(seed_value + r)
		if won:
			wins += 1
		total_islands += Game.islands_cleared
	print("SUMMARY runs=%d wins=%d avg_islands=%.2f" % [runs, wins, float(total_islands) / runs])
	for k in stats.keys():
		print("STAT ", k, " = ", stats[k])
	print("SMOKE_TEST_DONE")
	get_tree().quit()


func _count(k: String) -> void:
	stats[k] = int(stats.get(k, 0)) + 1


func _run(seed_value: int) -> bool:
	Game.new_run(seed_value)
	var guard := 0
	while not Game.run_over and guard < 12:
		guard += 1
		var options: Array = Game.reachable_nodes()
		if options.is_empty():
			break
		var nid: int = options[0]
		var b := Battle.new()
		b.auto_play = true
		b.speed = 4.0
		b.setup(Game.map_nodes[nid], Game.deployed_commanders())
		b.skill_used.connect(func(_s, k): _count("skill_" + k))
		b.item_used.connect(func(_s, k): _count("item_" + k))
		b.unit_died.connect(func(u, cause): _count("died_%s_%s" % ["player" if u.team == 0 else "enemy", cause]))
		b.house_burned.connect(func(_h): _count("house_burned"))
		b.unit_fell.connect(func(u): _count("fell_sea_%s" % ("player" if u.team == 0 else "enemy")))
		b.squad_reinforced.connect(func(_s): _count("reinforced"))
		add_child(b)
		var timer := get_tree().create_timer(150.0)
		var on_timeout := func():
			push_error("battle timeout")
			for u in b.units:
				if u.team == 1:
					var c: Vector2i = b.world_to_cell(u.position)
					print("  stuck enemy %s cell=%s walk=%s state=%d target=%s path=%s" % [u.type_id, c, b.island.is_walkable(c), u.state, u._target, u._path])
			b._finish(false)
		timer.timeout.connect(on_timeout)
		var result: Dictionary = await b.battle_ended
		timer.timeout.disconnect(on_timeout)
		stats["skill_hits"] = int(stats.get("skill_hits", 0)) + b.skill_hits
		if not result["won"]:
			_count("lost_by_houses" if b.intact_house_count() == 0 else "lost_by_wipe")
		var node: Dictionary = Game.map_nodes[nid]
		print("seed=%d island=%s diff=%d won=%s houses=%d/%d gold=%d wiped=%s time=%.0fs roster=%s" % [
			seed_value, node["name"], node["difficulty"], result["won"], result["houses_saved"],
			result["houses_total"], result["gold"], str(result["wiped"]), result["time"], str(Game.roster.map(func(c): return "%s%d" % [c["cls"].left(3), c["level"]]))])
		b.queue_free()
		Game.apply_battle_result(nid, result)
		_spend_gold()
	print("RUN seed=%d won=%s islands=%d gold=%d roster=%s" % [seed_value, Game.run_won, Game.islands_cleared, Game.gold, str(Game.roster)])
	return Game.run_won


func _spend_gold() -> void:
	var changed := true
	while changed:
		changed = false
		for c in Game.roster:
			if str(c["cls"]) == "militia" and Game.can_promote(c):
				changed = Game.promote(int(c["id"]), ["infantry", "archer", "pikeman"][randi() % 3]) or changed
		for c in Game.roster:
			if Game.can_buy_skill(c):
				changed = Game.buy_skill(int(c["id"])) or changed
		for it in Game.shop.duplicate():
			if Game.inventory.size() < 1 and Game.can_buy_item(it):
				changed = Game.buy_item(it) or changed
		for c in Game.roster:
			if str(c["item"]) == "" and not Game.inventory.is_empty():
				changed = Game.equip(int(c["id"]), Game.inventory[0]) or changed
		if Game.roster.size() < 4 and Game.can_recruit():
			changed = Game.recruit() or changed
		var cheapest = null
		for c in Game.roster:
			if Game.can_level_up(c) and (cheapest == null or Game.level_cost(c) < Game.level_cost(cheapest)):
				cheapest = c
		if cheapest != null:
			changed = Game.level_up(int(cheapest["id"])) or changed
