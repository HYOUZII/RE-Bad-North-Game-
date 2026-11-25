extends Node
## 플레이 테스트 에이전트 (개발용): 실제 입력 이벤트(마우스·키)를 넣어 사람처럼 플레이하고 스크린샷을 남깁니다.
## 실행: godot --path . --rendering-driver opengl3 res://tests/playtest_agent.tscn -- --out=/home/user/shots_play

var out_dir := "/home/user/shots_play"
var main: Node
var shot_i := 0
var battle = null
var boat_land_violations := 0
var boat_checks := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(4242)
	if "--mode=skills" in OS.get_cmdline_user_args():
		_skill_lab.call_deferred()
		return
	_run.call_deferred()


func _run() -> void:
	main = load("res://scripts/main.gd").new()
	add_child(main)
	await _frames(10)
	_save("title")
	print("viewport size: ", get_viewport().get_visible_rect().size)
	var b := _find_button(main, "새 원정 시작")
	print("title button: ", b != null)
	await _click_control(b)
	await _frames(10)
	_save("map_start")
	_dump_buttons("map_start")
	# 처음엔 골드 0 → 테스트를 위해 골드 지급 (치트)
	Game.gold = 80
	Game.changed.emit()
	await _frames(5)
	_save("map_gold80")
	# 기술 배우기: 각 지휘관 카드의 '기술' 버튼 클릭
	for _k in range(3):
		var sb := _find_button_prefix(main, "기술 '")
		if sb == null:
			break
		print("click skill btn: ", sb.text, " disabled=", sb.disabled)
		await _click_control(sb)
		await _frames(5)
	_save("map_after_skills")
	# 상점 아이템 사기
	for item in Game.shop.duplicate():
		pass
	var bought := 0
	for _k in range(2):
		var shop_btn := _find_button_prefix(main, "", "G): 전투마다")
		if shop_btn == null:
			break
		print("click shop: ", shop_btn.text, " disabled=", shop_btn.disabled, " rect=", shop_btn.get_global_rect())
		await _click_control(shop_btn)
		await _frames(5)
	print("inventory after buy: ", Game.inventory, " gold=", Game.gold)
	_save("map_after_shop")
	# 장비 달기
	for _k in range(2):
		var eb := _find_button_suffix(main, " 달기")
		if eb == null:
			break
		print("click equip: ", eb.text, " rect=", eb.get_global_rect())
		await _click_control(eb)
		await _frames(5)
	print("roster: ", Game.roster)
	_save("map_after_equip")
	# 출전 토글 (끄고 다시 켜기)
	var cbs := _find_all(main, func(n): return n is CheckBox)
	print("deploy checkboxes: ", cbs.size(), " deployed=", Game.deploy_ids)
	if cbs.size() > 0:
		await _click_control(cbs[0])
		await _frames(3)
		print("after toggle off: ", Game.deploy_ids)
		_save("map_deploy_off")
		cbs = _find_all(main, func(n): return n is CheckBox)
		await _click_control(cbs[0])
		await _frames(3)
		print("after toggle on: ", Game.deploy_ids)
	# 공격 섬 선택
	var reach := Game.reachable_nodes()
	print("reachable: ", reach)
	var nodes_btns := _find_all(main, func(n): return n is Button and not n.disabled and "위험" in n.text)
	print("enabled node buttons: ", nodes_btns.size())
	_save("map_before_battle")
	await _click_control(nodes_btns[0])
	await _frames(10)
	battle = _find_all(main, func(n): return n.get_script() == load("res://scripts/battle/battle.gd"))[0] if not _find_all(main, func(n): return n.get_script() == load("res://scripts/battle/battle.gd")).is_empty() else null
	print("battle: ", battle)
	if battle == null:
		get_tree().quit()
		return
	await _battle_play()
	get_tree().quit()


# ================================================================ 전투

func _battle_play() -> void:
	var bt = battle
	_save("b_start")
	print("squads: ", bt.squads.map(func(s): return [s.index, s.type_id(), s.anchor_cell, s.has_skill(), s.commander.get("item")]))
	print("houses: ", bt.houses.map(func(h): return h.cell))
	print("tile count ", bt.island.tiles.size(), " stairs ", bt.island.stairs.keys())
	# 0) 다른 분대 옆 칸 클릭 시험
	var adj_ok := 0
	var adj_steal := 0
	var adj_other := 0
	var other = bt.squads[1]
	for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1)]:
		var c: Vector2i = other.anchor_cell + d
		if bt.order_path(bt.squads[0], c).is_empty():
			continue
		await _key(KEY_ESCAPE)
		await _key(KEY_1)
		await _frames(1)
		var sp = _screen_of(bt.cell_center(c))
		var picked_sq = bt._pick_squad(sp)
		await _click(sp)
		await _frames(1)
		if bt.squads[0].anchor_cell == c:
			adj_ok += 1
		elif bt.selected == other:
			adj_steal += 1
			if adj_steal == 1:
				_save("b_adjacent_steal")
		else:
			adj_other += 1
			print("  adj click ", c, " -> anchor ", bt.squads[0].anchor_cell, " pick_cell=", bt._pick_cell(sp), " sel=", bt.selected.index if bt.selected else -1)
		print("  adj click cell ", c, " pick_squad=", picked_sq.index if picked_sq else -1, " px dist to cell center from other centroid=", sp.distance_to(_screen_of(other.centroid() + Vector3(0,0.25,0))))
	print("ADJACENT TEST: ordered=", adj_ok, " selection stolen by neighbour squad=", adj_steal, " other=", adj_other)
	await _key(KEY_ESCAPE)
	# 0b) 선택 중 다른 분대 숫자 라벨 클릭 → 선택 전환
	await _key(KEY_1)
	await _frames(1)
	await _click(_screen_of(bt.squads[1].centroid() + Vector3(0, 1.15, 0)))
	await _frames(2)
	print("LABEL SWITCH: selected=", bt.selected.index if bt.selected else -1, " (expect 1)")
	_save("b_label_switch")
	# 0c) 적 없을 때 일제 사격 F → 거부, 쿨다운 유지
	var arch = bt.squads.filter(func(q): return q.type_id() == "archer")[0]
	await _key(KEY_ESCAPE)
	await _key(KEY_1 + arch.index)
	await _frames(2)
	_save("b_volley_btn_noenemy")
	await _key(KEY_F)
	await _frames(3)
	print("VOLLEY NO ENEMY: skill_cd=", arch.skill_cd, " projectiles=", bt.projectiles.size(), " btn='", bt._skill_btn.text, "' disabled=", bt._skill_btn.disabled)
	_save("b_volley_refused")
	# 0d) 장비 G (적 없음/병사 가득) → 거부 + 안내
	for q in bt.squads:
		if str(q.commander.get("item", "")) != "":
			await _key(KEY_ESCAPE)
			await _key(KEY_1 + q.index)
			await _frames(2)
			await _key(KEY_G)
			await _frames(3)
			print("ITEM NO-USE: squad ", q.index, " item ", q.commander["item"], " used=", q.item_used, " btn='", bt._item_btn.text, "' disabled=", bt._item_btn.disabled)
			_save("b_item_refused_%d" % q.index)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	# 1) 분대 1 숫자 라벨 클릭
	await _click(_screen_of(bt.squads[0].centroid() + Vector3(0, 0.25, 0)))
	await _frames(3)
	print("selected after click: ", bt.selected.index if bt.selected else null)
	_save("b_sel1")
	# 2) 바위 칸 hover → 빨간 마커, 클릭 → 거부되어야
	var rock = null
	for c in bt.island.blocked.keys():
		rock = c
		break
	if rock != null:
		var rp = _screen_of(bt.cell_center(rock) + Vector3(0, 0.1, 0))
		await _move(rp)
		await _frames(3)
		print("hover rock ", rock, " picked=", bt._hover_cell, " bad_visible=", bt._hover_bad.visible)
		_save("b_hover_rock")
		var before = bt.squads[0].anchor_cell
		await _click(rp)
		await _frames(3)
		print("after click rock: anchor ", bt.squads[0].anchor_cell, " (before ", before, ") still selected=", bt.selected != null)
	# 3) 다른 높이 칸(계단 필요)으로 이동
	var s0 = bt.squads[0]
	var h0: int = bt.height_steps(s0.anchor_cell)
	var target = null
	var best_len := 0
	for c in bt.island.tiles.keys():
		if bt.height_steps(c) != h0 and bt.island.is_walkable(c):
			var p: Array = bt.order_path(s0, c)
			if p.size() > best_len and p.size() < 12:
				best_len = p.size()
				target = c
	if target != null:
		var tp = _screen_of(bt.cell_center(target))
		print("stairs target ", target, " h=", bt.height_steps(target), " pick=", bt._pick_cell(tp))
		await _move(tp)
		await _frames(3)
		_save("b_preview_stairs")
		await _click(tp)
		await _frames(3)
		print("ordered: anchor ", s0.anchor_cell, " marching=", s0.marching, " path=", s0.path_cells)
		_save("b_march")
	# 4) 절벽(높이 다른 이웃, 계단 없음) 칸 위로 hover - 다른 분대 선택 후 occupied 칸
	await _key(KEY_2)
	await _frames(2)
	var occ_cell = bt.squads[2].anchor_cell
	var op = _screen_of(bt.cell_center(occ_cell) + Vector3(0.35, 0, 0.35))
	await _move(op)
	await _frames(3)
	print("hover occupied ", occ_cell, " picked ", bt._hover_cell, " bad=", bt._hover_bad.visible, " ok=", bt._hover_marker.visible)
	_save("b_hover_occupied")
	await _click(op)
	await _frames(3)
	print("click on occupied-ish: selected=", bt.selected.index if bt.selected else null)
	await _key(KEY_ESCAPE)
	# 5) 경로 이동 감시 - 행군 중 유닛이 절벽을 넘는지
	var t_end: float = bt.elapsed + 6.0
	var cliff_cross := 0
	var last_cells := {}
	while bt.elapsed < t_end:
		for u in s0.units:
			var c = bt.world_to_cell(u.position)
			if last_cells.has(u) and last_cells[u] != c and u.knock_vel.length() < 0.1:
				if not bt.nav.can_step(last_cells[u], c) and bt.nav.tiles.has(c):
					cliff_cross += 1
					print("CLIFF CROSS? ", last_cells[u], " -> ", c)
			last_cells[u] = c
		await get_tree().process_frame
	print("s0 after march: anchor ", s0.anchor_cell, " centroid cell ", bt.world_to_cell(s0.centroid()), " marching ", s0.marching, " cliff_cross=", cliff_cross)
	_save("b_arrived")
	# 6) 웨이브: 배 접근 감시
	Engine.time_scale = 1.0
	var t_shot := 0.0
	var skills_done := {}
	var item_done := false
	var start_wall := Time.get_ticks_msec()
	while not bt.finished and skills_done.keys().filter(func(k): return k is int).size() < 3 and bt.elapsed < 45.0 and Time.get_ticks_msec() - start_wall < 120000:
		_check_boats()
		if bt.elapsed > t_shot:
			t_shot = bt.elapsed + 4.0
			_save("b_t%03d" % int(bt.elapsed))
			print("t=%.1f wave=%d enemies=%d boats=%d houses=%d" % [bt.elapsed, bt.wave_index, bt.enemy_count(), bt.boats.size(), bt.intact_house_count()])
		# 적이 상륙하면 각 분대 기술 시험
		var landed: Array = bt.units.filter(func(u): return u.team == 1 and u.state == u.State.ACTIVE)
		if landed.size() > 0:
			landed = landed.filter(func(u): return is_instance_valid(u))
			for s in bt.squads:
				landed = landed.filter(func(u): return is_instance_valid(u) and u.state == u.State.ACTIVE)
				if landed.is_empty():
					break
				if skills_done.has(s.index) or s.is_wiped() or not s.has_skill():
					continue
				var ready := false
				for e in landed:
					for u in s.units:
						var d: float = bt._flat_dist(u.position, e.position)
						if s.type_id() == "archer":
							if d <= bt.effective_range(u, e) and d > 1.0:
								ready = true
						elif d < 1.0:
							ready = true
				if ready and not s.marching:
					skills_done[s.index] = true
					await _test_skill(s)
					continue
				if not s.marching and bt.elapsed > float(skills_done.get("sent_t%d" % s.index, -1.0)):
					skills_done["sent_t%d" % s.index] = bt.elapsed + 6.0
					var tgt = landed[0]
					var ec = bt.world_to_cell(tgt.position)
					var goal = null
					var dirs := [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1)]
					if s.type_id() == "archer":
						dirs = [Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2),Vector2i(2,2),Vector2i(-2,-2)]
					dirs.sort_custom(func(x, y): return Vector2(ec + x).length() < Vector2(ec + y).length())
					for d in dirs:
						if not bt.order_path(s, ec + d).is_empty():
							goal = ec + d
							break
					if goal != null and goal != s.anchor_cell:
						await _select_squad(s)
						await _click(_screen_of(bt.cell_center(goal)))
						await _frames(1)
						print("t=%.1f sent squad %d (%s) to %s ok=%s selected_after=%s" % [bt.elapsed, s.index, s.type_id(), goal, s.anchor_cell == goal, bt.selected.index if bt.selected else -1])
						if bt.selected != null:
							_save("b_send_fail_%d" % s.index)
							await _key(KEY_ESCAPE)
			landed = landed.filter(func(u): return is_instance_valid(u))
			if not item_done:
				for s in bt.squads:
					if s.item_ready():
						item_done = true
						await _select_squad(s)
						var before_e: int = bt.enemy_count()
						await _key(KEY_G)
						await _frames(2)
						print("item G squad ", s.index, " item=", s.commander.get("item"), " used=", s.item_used, " enemies ", before_e, "->", bt.enemy_count())
						_save("b_item_g")
						await _key(KEY_ESCAPE)
						break
		await get_tree().process_frame
	print("boat checks ", boat_checks, " land violations ", boat_land_violations)
	# 7) 집 불타게 두기: 모든 분대를 집에서 먼 곳으로
	print("--- abandon houses ---")
	for s in bt.squads:
		if s.is_wiped():
			continue
		var far = null
		var far_d := -1.0
		for c in bt.island.tiles.keys():
			if not bt.order_path(s, c).is_empty():
				var dmin := INF
				for h in bt.houses:
					dmin = min(dmin, Vector2(c - h.cell).length())
				if dmin > far_d:
					far_d = dmin
					far = c
		await _select_squad(s)
		await _click(_screen_of(bt.cell_center(far)))
		await _frames(2)
	Engine.time_scale = 4.0
	start_wall = Time.get_ticks_msec()
	t_shot = 0.0
	while not bt.finished and Time.get_ticks_msec() - start_wall < 150000:
		_check_boats()
		if bt.elapsed > t_shot:
			t_shot = bt.elapsed + 15.0
			_save("c_t%03d" % int(bt.elapsed))
			print("t=%.1f wave=%d/%d enemies=%d houses=%d players=%d" % [bt.elapsed, bt.wave_index, bt.waves.size(), bt.enemy_count(), bt.intact_house_count(), bt.player_count()])
		await get_tree().process_frame
	Engine.time_scale = 1.0
	await _frames(5)
	print("finished=", bt.finished, " result=", bt.result, " houses=", bt.intact_house_count())
	print("boat checks ", boat_checks, " land violations ", boat_land_violations)
	_save("result")
	var cont := _find_button(bt, "계속")
	if cont != null:
		await _click_control(cont)
		await _frames(10)
		_save("after_result")
		_dump_buttons("after_result")


func _test_skill(s) -> void:
	var bt = battle
	await _select_squad(s)
	var enemies_before := []
	for e in bt.units:
		if e.team == 1 and e.state == e.State.ACTIVE:
			enemies_before.append([e, e.position, e.hp])
	var cd_before := []
	for u in s.units:
		cd_before.append(u._ranged_cd)
	var proj_before: int = bt.projectiles.size()
	var hits_before: int = bt.skill_hits
	if s.type_id() == "archer" and not s.marching:
		for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			if not bt.order_path(s, s.anchor_cell + d).is_empty():
				await _click(_screen_of(bt.cell_center(s.anchor_cell + d)))
				await _frames(1)
				break
		await _select_squad(s)
		print("  archer marching before F: ", s.marching)
	_save("b_skill_pre_%s" % s.type_id())
	for rec in enemies_before:
		var md := INF
		var cm := false
		for u in s.units:
			var dd: float = bt._flat_dist(u.position, rec[0].position)
			if dd < md:
				md = dd
				cm = bt.can_melee(u.position, rec[0].position)
		print("  pre-F enemy %s cell %s nearest soldier %.2f can_melee=%s shore_dist?" % [rec[0].type_id, bt.world_to_cell(rec[0].position), md, cm])
	await _key(KEY_F)
	await _frames(1)
	print("SKILL %s squad %d: cd=%.1f buff_t=%.1f marching=%s anchor=%s" % [s.type_id(), s.index, s.skill_cd, s.units[0].buff_t if s.units.size() else -1.0, s.marching, s.anchor_cell])
	await _frames(1)
	if s.type_id() == "archer":
		print("  archer ranged_cd before ", cd_before.slice(0, 3), " projectiles ", proj_before, " -> ", bt.projectiles.size())
	await _frames(12)
	_save("b_skill_%s" % s.type_id())
	# 2초 정도 지켜보며 추락/밀림 기록
	var t_end: float = bt.elapsed + 2.5
	var fell := 0
	var seen_fall := {}
	while bt.elapsed < t_end and not bt.finished:
		for e in bt.units:
			if e.team == 1 and e.state == e.State.FALLING and not seen_fall.has(e):
				seen_fall[e] = true
				fell += 1
		await get_tree().process_frame
	var moved := []
	for rec in enemies_before:
		var e = rec[0]
		if is_instance_valid(e) and e.state != e.State.DEAD:
			moved.append("%.2f" % Vector2(e.position.x - rec[1].x, e.position.z - rec[1].z).length())
		else:
			moved.append("dead")
	print("  after skill: skill_hits +", bt.skill_hits - hits_before, " fell_to_sea=", fell, " enemy displacement=", moved, " projectiles=", bt.projectiles.size())
	_save("b_skill_after_%s" % s.type_id())
	await _key(KEY_ESCAPE)


func _select_squad(s) -> void:
	var bt = battle
	if bt.selected == s:
		return
	await _key(KEY_1 + s.index)
	await _frames(2)


func _check_boats() -> void:
	var bt = battle
	for b in bt.boats:
		if b.phase != b.Phase.SAILING and b.phase != b.Phase.LEAVING:
			continue
		boat_checks += 1
		# 배 몸통(길이 약 1.2, 폭 0.7) 앞·중·뒤 점이 섬 칸 위에 있는가
		var fwd: Vector3 = -b.transform.basis.z
		for k in [-0.5, 0.0, 0.5]:
			var p: Vector3 = b.position + fwd * k
			var c := Vector2i(int(round(p.x)), int(round(p.z)))
			if bt.island.tiles.has(c):
				# 도착 직전(상륙 지점 근처) 은 허용
				if Vector2(b.position.x - b.land_pos.x, b.position.z - b.land_pos.z).length() > 0.9:
					boat_land_violations += 1
					if boat_land_violations < 6:
						print("BOAT OVER LAND at ", p, " cell ", c, " phase ", b.phase, " land_pos ", b.land_pos)
						_save("boat_over_land_%d" % boat_land_violations)


# ================================================================ 입력 도우미

func _screen_of(p: Vector3) -> Vector2:
	return battle.camera_rig.camera.unproject_position(p)


func _move(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	Input.parse_input_event(m)
	await _frames(1)


func _click(pos: Vector2) -> void:
	await _move(pos)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await _frames(1)


func _click_control(c: Control) -> void:
	if c == null:
		print("CLICK NULL CONTROL")
		return
	var vp := get_viewport().get_visible_rect()
	var tries := 0
	while not vp.encloses(c.get_global_rect()) and tries < 30:
		tries += 1
		var r0 := c.get_global_rect()
		var at := Vector2(clampf(r0.get_center().x, 5, vp.size.x - 5), vp.size.y * 0.5)
		for pressed in [true, false]:
			var w := InputEventMouseButton.new()
			w.button_index = MOUSE_BUTTON_WHEEL_DOWN if r0.end.y > vp.size.y else MOUSE_BUTTON_WHEEL_UP
			w.pressed = pressed
			w.position = at
			w.global_position = at
			Input.parse_input_event(w)
		await _frames(2)
	if tries > 0:
		print("  (scrolled ", tries, " wheel steps to reach '", c.get("text"), "')")
	var r := c.get_global_rect()
	await _click(r.position + r.size * 0.5)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(1)


func _find_all(root: Node, pred: Callable) -> Array:
	var out := []
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if pred.call(n):
			out.append(n)
		for ch in n.get_children():
			stack.append(ch)
	return out


func _find_button(root: Node, text: String) -> Button:
	var r := _find_all(root, func(n): return n is Button and n.text == text and n.is_visible_in_tree())
	return r[0] if r.size() else null


func _find_button_prefix(root: Node, prefix: String, contains: String = "") -> Button:
	var r := _find_all(root, func(n): return n is Button and n.is_visible_in_tree() and not n.disabled and n.text.begins_with(prefix) and (contains == "" or contains in n.text))
	return r[0] if r.size() else null


func _find_button_suffix(root: Node, suffix: String) -> Button:
	var r := _find_all(root, func(n): return n is Button and n.is_visible_in_tree() and not n.disabled and n.text.ends_with(suffix))
	return r[0] if r.size() else null


func _dump_buttons(tag: String) -> void:
	for b in _find_all(main, func(n): return n is BaseButton and n.is_visible_in_tree()):
		print("[%s] btn '%s' dis=%s rect=%s" % [tag, b.text.replace("\n", "/"), b.disabled, b.get_global_rect()])


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	shot_i += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%03d_%s.png" % [shot_i, name]))


# ================================================================ 기술 실험실: 해안 적을 상대로 F 키
func _skill_lab() -> void:
	Game.new_run(4242)
	for c in Game.roster:
		c["skill"] = true
	var B = load("res://scripts/battle/battle.gd")
	for cls in ["archer", "infantry", "pikeman"]:
		for trial in range(3):
			var bt = B.new()
			var node: Dictionary = Game.map_nodes[0].duplicate()
			node["seed"] = 100 + trial
			var cmd: Dictionary = Game.roster.filter(func(c): return c["cls"] == cls)[0]
			bt.setup(node, [cmd])
			add_child(bt)
			battle = bt
			bt.wave_timer = 9999.0
			await _frames(3)
			# 해안 칸 + 안쪽 이웃(같은 높이) 찾기
			var s = bt.squads[0]
			var pick = null
			var beaches: Array = bt.island.get_beach_cells()
			beaches.sort_custom(func(a, b): return Vector2(a - s.anchor_cell).length() < Vector2(b - s.anchor_cell).length())
			for beach in beaches:
				for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					var sea: Vector2i = beach - d
					var inland: Vector2i = beach + d
					if not bt.island.tiles.has(sea) and bt.nav.can_step(beach, inland) and not bt.order_path(s, inland).is_empty() and bt.house_at(inland) == null:
						pick = [beach, inland]
						break
				if pick != null:
					break
			await _key(KEY_1)
			await _click(_screen_of(bt.cell_center(pick[1])))
			var t0: float = bt.elapsed
			while s.marching and bt.elapsed - t0 < 20.0:
				await get_tree().process_frame
			# 적 3명을 해안 칸에 내려놓음
			var es := []
			for k in range(3):
				var e = bt.spawn_unit("raider", 1, bt.cell_center(pick[0]) + Vector3(randf_range(-0.2,0.2), 0, randf_range(-0.2,0.2)), 1.0, 1.0)
				es.append(e)
			await _frames(4)
			if bt.selected != s:
				await _key(KEY_1)
			print("  pre: squad anchor ", s.anchor_cell, " marching ", s.marching, " selected ", bt.selected == s, " nearest dist ", es.map(func(e): return snappedf(s.units.map(func(u): return bt._flat_dist(u.position, e.position)).min(), 0.01)))
			_save("lab_%s_%d_pre" % [cls, trial])
			var hits0: int = bt.skill_hits
			if cls == "archer":
				for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					var nc: Vector2i = s.anchor_cell + d
					if nc != pick[0] and not bt.order_path(s, nc).is_empty():
						await _click(_screen_of(bt.cell_center(nc)))
						break
				if bt.selected != s:
					await _key(KEY_1)
				var p0: int = bt.projectiles.size()
				await _key(KEY_F)
				print("LAB archer volley while marching=", s.marching, " projectiles ", p0, " -> ", bt.projectiles.size(), " cd=", s.skill_cd)
				_save("lab_archer_%d_volley" % trial)
				bt.queue_free()
				await _frames(3)
				continue
			await _key(KEY_F)
			var fell := 0
			var seen := {}
			t0 = bt.elapsed
			var shot := false
			while bt.elapsed - t0 < 3.0:
				for e in es:
					if is_instance_valid(e) and e.state == e.State.FALLING and not seen.has(e):
						seen[e] = true
						fell += 1
				if not shot and bt.elapsed - t0 > 0.4:
					shot = true
					_save("lab_%s_%d_post" % [cls, trial])
				await get_tree().process_frame
			var alive := es.filter(func(e): return is_instance_valid(e) and e.state != e.State.DEAD).size()
			print("LAB %s trial %d: beach %s squad at %s -> skill_hits=%d fell_to_sea=%d alive=%d/3" % [cls, trial, pick[0], pick[1], bt.skill_hits - hits0, fell, alive])
			bt.queue_free()
			await _frames(3)
	get_tree().quit()
