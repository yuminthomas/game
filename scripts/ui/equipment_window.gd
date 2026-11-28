class_name EquipmentWindow
extends GameWindow
## 장비창 (E): 실제 외형 미리보기 + 장비 칸 8개 + 크로노 코어 6칸 (GDD 12-3).

const LEFT := ["helmet", "chest", "gloves", "boots"]
const RIGHT := ["weapon", "ring1", "ring2", "necklace"]

var preview_holder: Control
var preview: LayeredCharacter
var slots := {}
var cores: Array = []
var turn := 2

func _init() -> void:
	super._init("equipment", "장비", Vector2(210, 30))

func _ready() -> void:
	super._ready()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var lcol := VBoxContainer.new()
	row.add_child(lcol)
	for s in LEFT: lcol.add_child(_slot(s))
	preview_holder = Control.new()
	preview_holder.custom_minimum_size = Vector2(60, 92)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_holder.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: turn = (turn + 2) % 8; preview.dir8 = turn)
	preview_holder.draw.connect(func(): preview_holder.draw_rect(Rect2(Vector2.ZERO, preview_holder.size), Color(0.03, 0.04, 0.08, 0.6)); preview_holder.draw_rect(Rect2(Vector2.ZERO, preview_holder.size), UITheme.GOLD_DIM, false, 1))
	row.add_child(preview_holder)
	preview = LayeredCharacter.new()
	preview.position = Vector2(30, 84)
	preview.scale = Vector2(2, 2)
	preview_holder.add_child(preview)
	var rcol := VBoxContainer.new()
	row.add_child(rcol)
	for s in RIGHT: rcol.add_child(_slot(s))
	body.add_child(UITheme.label("크로노 코어", 10, UITheme.CRYSTAL))
	var crow := HBoxContainer.new()
	body.add_child(crow)
	for i in 6:
		var b := SlotBox.new(Vector2(20, 20))
		b.ui = ui
		b.border = UITheme.CRYSTAL.darkened(0.5)
		var idx := i
		b.tooltip_fn = func():
			var c = Game.data.cores[idx]
			if c == null: return [["빈 코어 칸", UITheme.TEXT_DIM], ["크로놀리스를 복구하면 그 지역의 크로노 코어를 얻습니다", UITheme.TEXT_DIM]]
			return [["크로노 코어 #%d  Lv%d" % [c.region, c.level], UITheme.CRYSTAL], ["크로노포스 +%d · 주스탯 +%d · 최대 HP +%d%%" % [c.level * 10, c.level * 3, c.level], UITheme.TEXT]]
		crow.add_child(b)
		cores.append(b)
	body.add_child(UITheme.label("우클릭: 해제  ·  미리보기 클릭: 돌려보기", 9, UITheme.TEXT_DIM))
	Game.data.changed.connect(func(w): if visible and w in ["equipment", "stats"]: refresh())

func _slot(s: String) -> SlotBox:
	var b := SlotBox.new(Vector2(22, 22))
	b.ui = ui
	b.empty_hint = Items.slot_name(s).left(2)
	b.accept = func(d): return d is Dictionary and d.get("type") == "item" and _fits(s, d.item)
	b.on_drop = func(d):
		if s == "weapon" and Game.in_combat():
			ui.show_notice("전투 중에는 무기를 바꿀 수 없습니다", UITheme.RED); return
		var err := Game.data.equip_from_inventory(d.index, s)
		if err != "": ui.show_notice(err, UITheme.RED)
	b.on_click = func(btn, _dbl):
		if btn == MOUSE_BUTTON_RIGHT:
			var err := Game.data.unequip(s)
			if err != "": ui.show_notice(err, UITheme.RED)
			ui.hide_tooltip()
	b.tooltip_fn = func():
		var it = Game.data.equipment[s]
		if it == null: return [[Items.slot_name(s) + " (비어 있음)", UITheme.TEXT_DIM]]
		return Items.tooltip_lines(it, {}, Game.data)
	slots[s] = b
	return b

func _fits(s: String, it: Dictionary) -> bool:
	if s.begins_with("ring"): return it.slot == "ring"
	return it.slot == s

func refresh() -> void:
	if preview == null: return
	var pd := Game.data
	for s in slots:
		var b: SlotBox = slots[s]
		var it = pd.equipment[s]
		b.icon = SpriteFactory.item_icon(it.id) if it != null else null
		b.border = Data.grade_color(it.grade).darkened(0.2) if it != null else UITheme.GOLD_DIM
		b.payload = {"type": "equip", "slot": s} if it != null and s != "weapon" else null
		b.queue_redraw()
	for i in 6:
		var c = pd.cores[i]
		cores[i].icon = SpriteFactory.item_icon("chrono_shard") if c != null else null
		cores[i].count_text = str(c.level) if c != null else ""
		cores[i].queue_redraw()
	if Game.player:
		Game.player.refresh_look()
		var src: LayeredCharacter = Game.player.look
		preview.apply_look({"hair": pd.appearance.hair, "cape": pd.appearance.cape, "crystal": pd.crystal_stage(), "weapon_id": pd.weapon().get("id", ""),
			"armor_color": Data.armor[pd.equipment.chest.id].get("look", {}).get("color") if pd.equipment.chest != null else null,
			"cape_style": Data.armor[pd.equipment.chest.id].get("look", {}).get("cape", "default") if pd.equipment.chest != null else "default",
			"helmet_style": Data.armor[pd.equipment.helmet.id].get("look", {}).get("layer", "hood") if pd.equipment.helmet != null else "none",
			"helmet_color": Data.armor[pd.equipment.helmet.id].get("look", {}).get("color", "#a0a0a0") if pd.equipment.helmet != null else "#a0a0a0",
			"gloves_color": Data.armor[pd.equipment.gloves.id].get("look", {}).get("color") if pd.equipment.gloves != null else null,
			"boots_color": Data.armor[pd.equipment.boots.id].get("look", {}).get("color", "#5a4030") if pd.equipment.boots != null else "#5a4030"})
		preview.dir8 = turn
		preview.play("idle", 0.6)
