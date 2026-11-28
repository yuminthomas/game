class_name InventoryWindow
extends GameWindow
## 인벤토리 (I): 장비 / 소모 / 재료 / 스킬서 탭, 정렬, 잠금, 새 아이템 표시, 비교 툴팁 (GDD 9-6).
## 우클릭·더블클릭 = 장착 / 사용 / 읽기. 장비창으로 끌어다 놓아도 장착된다.

var tabs: TabBar
var grid: GridContainer
var sand_label: Label
var lock_mode := false
var lock_btn: Button
var tab := 0

func _init() -> void:
	super._init("inventory", "인벤토리", Vector2(400, 30))

func _ready() -> void:
	super._ready()
	tabs = TabBar.new()
	for t in ["장비", "소모", "재료", "스킬서"]: tabs.add_tab(t)
	tabs.tab_changed.connect(func(i): tab = i; refresh())
	tabs.focus_mode = Control.FOCUS_NONE
	body.add_child(tabs)
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	body.add_child(grid)
	var row := HBoxContainer.new()
	body.add_child(row)
	row.add_child(UITheme.button("등급순", func(): Game.data.sort_equip("grade"), 10))
	row.add_child(UITheme.button("레벨순", func(): Game.data.sort_equip("level"), 10))
	row.add_child(UITheme.button("종류순", func(): Game.data.sort_equip("kind"), 10))
	lock_btn = UITheme.button("잠금", func(): lock_mode = not lock_mode; _lock_label(), 10)
	row.add_child(lock_btn)
	sand_label = UITheme.label("", 10, Color(0.95, 0.88, 0.6))
	body.add_child(sand_label)
	var hint := UITheme.label("우클릭: 장착·사용·읽기  /  끌어서 장비창에 놓기", 9, UITheme.TEXT_DIM)
	body.add_child(hint)
	Game.data.changed.connect(func(w): if visible and w in ["inventory", "equipment", "skills"]: refresh())

func _lock_label() -> void:
	lock_btn.text = "잠금 중…" if lock_mode else "잠금"
	lock_btn.add_theme_color_override("font_color", UITheme.CRYSTAL if lock_mode else UITheme.TEXT)

func refresh() -> void:
	if grid == null: return
	for c in grid.get_children(): c.queue_free()
	var pd := Game.data
	sand_label.text = "시간의 모래  %d" % pd.inv_material.get("time_sand", 0)
	match tab:
		0:
			for i in pd.inv_equip.size(): grid.add_child(_equip_slot(i))
		1:
			_stack_slots(pd.inv_consume, "consume")
		2:
			var mats := pd.inv_material.duplicate()
			mats.erase("time_sand")
			_stack_slots(mats, "material")
		3:
			for key in pd.inv_books:
				var b := _make_slot()
				b.icon = SpriteFactory.book_icon(key)
				b.count_text = str(pd.inv_books[key])
				var k: String = key
				b.tooltip_fn = func():
					var need := pd.book_tier_level(k)
					return [[PlayerData.book_name(k), Color(0.95, 0.85, 0.5)], ["읽을 수 있는 레벨 %d" % need, UITheme.TEXT if pd.level >= need else UITheme.RED],
						["읽으면 스킬 3개 중 하나를 고릅니다", UITheme.TEXT_DIM], ["우클릭: 읽기", UITheme.TEXT_DIM]]
				b.on_click = func(btn, dbl): if btn == MOUSE_BUTTON_RIGHT or dbl: ui.read_skillbook(k)
				grid.add_child(b)
			_fill_empty(16)

func _make_slot() -> SlotBox:
	var b := SlotBox.new(Vector2(20, 20))
	b.ui = ui
	return b

func _fill_empty(n: int) -> void:
	while grid.get_child_count() < n: grid.add_child(_make_slot())

func _equip_slot(i: int) -> SlotBox:
	var pd := Game.data
	var b := _make_slot()
	var it = pd.inv_equip[i]
	b.accept = func(d): return d is Dictionary and (d.get("type") == "item" or d.get("type") == "equip")
	b.on_drop = func(d): _drop_on(i, d)
	if it == null: return b
	b.icon = SpriteFactory.item_icon(it.id)
	b.border = Data.grade_color(it.grade).darkened(0.2)
	b.is_new = it.get("new", false)
	b.locked = it.get("locked", false)
	b.dim = pd.level < int(it.level)
	b.payload = {"type": "item", "from": "inv", "index": i, "item": it}
	b.tooltip_fn = func():
		var slot := pd.equip_slot_for(it)
		var cur = pd.equipment.get(slot)
		var lines := Items.tooltip_lines(it, cur if cur != null else {}, pd)
		lines.append(["우클릭: 장착%s" % ("  ·  잠금 모드: 클릭" if lock_mode else ""), UITheme.TEXT_DIM])
		return lines
	b.on_click = func(btn, dbl):
		if lock_mode and btn == MOUSE_BUTTON_LEFT:
			it.locked = not it.get("locked", false); refresh(); return
		if btn == MOUSE_BUTTON_RIGHT or dbl: _equip(i)
	return b

func _equip(i: int, target := "") -> void:
	var it = Game.data.inv_equip[i]
	if it != null and it.slot == "weapon" and Game.in_combat():
		ui.show_notice("전투 중에는 무기를 바꿀 수 없습니다", UITheme.RED); return
	var err := Game.data.equip_from_inventory(i, target)
	if err != "": ui.show_notice(err, UITheme.RED)
	ui.hide_tooltip()

func _drop_on(i: int, d: Dictionary) -> void:
	var pd := Game.data
	if d.type == "item" and d.from == "inv":
		var a = pd.inv_equip[d.index]
		pd.inv_equip[d.index] = pd.inv_equip[i]
		pd.inv_equip[i] = a
		pd.changed.emit("inventory")
	elif d.type == "equip":
		if pd.inv_equip[i] != null: return
		var err := pd.unequip(d.slot)
		if err != "": ui.show_notice(err, UITheme.RED)

func _stack_slots(dict: Dictionary, kind: String) -> void:
	for id in dict:
		if dict[id] <= 0: continue
		var b := _make_slot()
		b.icon = SpriteFactory.item_icon(id)
		b.count_text = str(dict[id])
		var key: String = id
		var def := Data.item_def(key)
		b.tooltip_fn = func():
			var lines := [[def.get("name", key), Color(0.95, 0.92, 0.8)]]
			if def.has("desc"): lines.append([def.desc, UITheme.TEXT_DIM])
			if kind == "consume": lines.append(["우클릭: 사용", UITheme.TEXT_DIM])
			return lines
		if kind == "consume":
			b.on_click = func(btn, dbl): if btn == MOUSE_BUTTON_RIGHT or dbl: Game.player.use_consumable(key)
		grid.add_child(b)
	_fill_empty(16)
