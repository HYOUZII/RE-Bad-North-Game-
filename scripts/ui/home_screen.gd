extends Control
## 본 섬(내가 다스리는 섬) 정비 화면
##
## 전투와 전투 사이에 돌아오는 곳입니다. 여기서 지휘관(분대)을 관리합니다.
##   - 지휘관 카드: 상태(병사 수, 체력, 공격력, 이동속도, 전적), 기술, 장비, 출전 여부
##   - 레벨업 / 민병 승급 / 기술 배우기 / 장비 달기
##   - 상점(장비 사기), 새 지휘관 고용
## "출항" 버튼을 누르면 원정 지도로 가서 지켜 줄 이웃 섬을 고릅니다.

signal sail_requested

const UnitDefs := preload("res://scripts/battle/unit_defs.gd")
const Catalog := preload("res://scripts/core/catalog.gd")

const CARD_WIDTH := 540.0

const CLASS_DESC := {
	"militia": "민병: 아직 병종이 없는 분대. 골드로 보병·궁수·창병으로 승급할 수 있습니다.",
	"infantry": "보병: 방패로 화살을 막고, 적의 길을 막는 데 좋습니다.",
	"archer": "궁수: 멀리서 화살을 쏩니다. 배에 탄 적도 맞힐 수 있지만 근접전에 약합니다.",
	"pikeman": "창병: 넉백이 강해 적을 바다로 밀어냅니다. 방패병과 거한에 강하고 화살에 약합니다.",
}

var _grid: GridContainer
var _shop_box: VBoxContainer
var _gold_label: Label
var _info_label: Label
var _sail_btn: Button


func _ready() -> void:
	# 부모가 Control이 아니어서 화면 크기를 직접 맞춤
	get_viewport().size_changed.connect(_fit_to_screen)
	_fit_to_screen()
	# 못 누르는(회색) 버튼 글씨도 읽히게
	theme = Theme.new()
	theme.set_color("font_disabled_color", "Button", Color(0.72, 0.72, 0.72))
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.22, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	# 위쪽 띠: 제목, 골드, 출항 버튼
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	outer.add_child(top)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_box)
	title_box.add_child(_label("본 섬 - 정비", 30))
	_info_label = _label("", 16)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_info_label)
	_gold_label = _label("", 26)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	top.add_child(_gold_label)
	_sail_btn = Button.new()
	_sail_btn.custom_minimum_size = Vector2(240, 60)
	_sail_btn.add_theme_font_size_override("font_size", 22)
	_sail_btn.pressed.connect(func(): sail_requested.emit())
	top.add_child(_sail_btn)
	outer.add_child(HSeparator.new())

	# 가운데: 지휘관 카드(여러 줄) + 상점, 화면보다 길면 스크롤
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	body.add_child(_label("지휘관 (출전 체크: 최대 %d명)" % Game.MAX_DEPLOY, 20))
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	body.add_child(_grid)
	body.add_child(HSeparator.new())
	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 8)
	body.add_child(_shop_box)

	Game.changed.connect(_refresh)
	_refresh()


func _fit_to_screen() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	if _grid != null:
		_grid.columns = max(1, int((size.x - 40.0) / (CARD_WIDTH + 12.0)))


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _refresh() -> void:
	if not is_inside_tree():
		return
	_fit_to_screen()
	var deployed := Game.deployed_commanders().size()
	_gold_label.text = "골드 %d" % Game.gold
	_info_label.text = "당신이 다스리는 섬입니다. 이웃 섬들이 침략자로부터 지켜 달라고 도움을 청합니다.\n지켜 준 섬은 남은 집마다 골드로 보답합니다. 지켜 낸 이웃 섬 %d개, 출전 %d/%d명" % [Game.islands_cleared, deployed, Game.MAX_DEPLOY]
	_sail_btn.text = "출항 → 원정 지도"
	_sail_btn.disabled = deployed == 0
	for c in _grid.get_children():
		c.queue_free()
	for c in Game.roster:
		_grid.add_child(_commander_card(c))
	_build_shop()


func _build_shop() -> void:
	for c in _shop_box.get_children():
		c.queue_free()
	_shop_box.add_child(_label("상점 (이웃 섬을 지킬 때마다 물건이 바뀜)", 20))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	_shop_box.add_child(row)
	for item in Game.shop:
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 0)
		b.text = "%s (%dG)\n%s" % [Catalog.item_name(item), Catalog.ITEM_COST, Catalog.item_desc(item)]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Game.can_buy_item(item)
		b.pressed.connect(func(): Game.buy_item(item))
		row.add_child(b)
	var r := Button.new()
	r.custom_minimum_size = Vector2(360, 0)
	r.text = "지휘관 고용 (%dG)\n민병 분대 하나가 합류 (최대 %d명)" % [Catalog.RECRUIT_COST, Game.MAX_ROSTER]
	r.alignment = HORIZONTAL_ALIGNMENT_LEFT
	r.disabled = not Game.can_recruit()
	r.pressed.connect(func(): Game.recruit())
	row.add_child(r)
	var names: PackedStringArray = []
	for it in Game.inventory:
		names.append(Catalog.item_name(it))
	var inv := "창고: " + (", ".join(names) + "  (지휘관 카드에서 달기)" if not names.is_empty() else "비어 있음")
	_shop_box.add_child(_label(inv, 16))


func _commander_card(c: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var cls := str(c["cls"])
	var cid := int(c["id"])

	var top := HBoxContainer.new()
	vb.add_child(top)
	var dep := CheckBox.new()
	dep.text = "출전"
	dep.button_pressed = Game.is_deployed(cid)
	dep.focus_mode = Control.FOCUS_NONE
	dep.toggled.connect(func(_on): Game.toggle_deploy(cid))
	top.add_child(dep)
	top.add_child(_label("%s  -  %s  Lv%d%s" % [str(c["name"]), UnitDefs.display_name(cls), int(c["level"]),
		"" if int(c["level"]) < Game.MAX_LEVEL else " (최고)"], 20))

	var desc := _label(str(CLASS_DESC.get(cls, "")), 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(desc)

	# 상태
	vb.add_child(_label("병사 %d명   체력 x%.2f   공격 x%.2f   이동 x%.2f" % [
		Game.soldiers_for(c), Game.hp_mult(c), Game.dmg_mult(c), Game.speed_mult(c)], 16))
	vb.add_child(_label("전적: 출전 %d회, 지켜 낸 섬 %d개" % [int(c.get("battles", 0)), int(c.get("saved", 0))], 14))

	# 기술
	if bool(c.get("skill", false)):
		var sk := _label("기술 [F] %s: %s" % [Catalog.skill_name(cls), str(Catalog.SKILLS[cls]["desc"])], 14)
		sk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sk.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		vb.add_child(sk)
	elif Catalog.SKILLS.has(cls):
		vb.add_child(_label("기술: 없음", 14))
	# 장비
	var item := str(c.get("item", ""))
	if item != "":
		var it := _label("장비 %s%s: %s" % ["[G] " if Catalog.item_active(item) else "", Catalog.item_name(item), Catalog.item_desc(item)], 14)
		it.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		it.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		vb.add_child(it)
	else:
		vb.add_child(_label("장비: 없음 (한 명에 하나, 한 번 달면 못 뗌)", 14))

	# 할 수 있는 일 버튼
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	vb.add_child(row)
	if cls == "militia":
		for k in UnitDefs.PLAYER_CLASSES:
			var b := Button.new()
			b.text = "%s 승급 (%dG)" % [UnitDefs.display_name(k), Game.PROMOTE_COST]
			b.tooltip_text = str(CLASS_DESC.get(k, ""))
			b.disabled = not Game.can_promote(c)
			b.pressed.connect(func(): Game.promote(cid, k))
			row.add_child(b)
	elif int(c["level"]) < Game.MAX_LEVEL:
		var b := Button.new()
		b.text = "레벨업 (%dG): 병사 +1, 능력치 상승" % Game.level_cost(c)
		b.disabled = not Game.can_level_up(c)
		b.pressed.connect(func(): Game.level_up(cid))
		row.add_child(b)
	if Catalog.SKILLS.has(cls) and not bool(c.get("skill", false)):
		var sk2: Dictionary = Catalog.SKILLS[cls]
		var b2 := Button.new()
		b2.text = "기술 '%s' 배우기 (%dG)" % [sk2["name"], Catalog.SKILL_COST]
		b2.tooltip_text = str(sk2["desc"])
		b2.disabled = not Game.can_buy_skill(c)
		b2.pressed.connect(func(): Game.buy_skill(cid))
		row.add_child(b2)
	if item == "":
		var seen := {}
		for inv_item in Game.inventory:
			if seen.has(inv_item):
				continue
			seen[inv_item] = true
			var b3 := Button.new()
			b3.text = "%s 달기" % Catalog.item_name(inv_item)
			b3.tooltip_text = Catalog.item_desc(inv_item) + " (한 번 달면 뗄 수 없음)"
			b3.pressed.connect(func(): Game.equip(cid, inv_item))
			row.add_child(b3)
	return panel
