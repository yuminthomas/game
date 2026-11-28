class_name SkillsWindow
extends GameWindow
## 스킬창 (K): 무기군 탭 6개 + 크로노 탭. 배운 스킬은 밝게, 안 배운 스킬은 실루엣(등급만).
## 아이콘을 끌어서 HUD 퀵슬롯이나 키 설정창 키보드에 놓는다.

var tabs: TabBar
var list: VBoxContainer
var tab_classes := Data.CLASSES + ["chrono"]
var tab := 0

func _init() -> void:
	super._init("skills", "스킬", Vector2(180, 24))

func _ready() -> void:
	super._ready()
	tabs = TabBar.new()
	tabs.focus_mode = Control.FOCUS_NONE
	for c in tab_classes: tabs.add_tab(Data.class_name_ko(c))
	tabs.tab_changed.connect(func(i): tab = i; refresh())
	body.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(270, 230)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	body.add_child(UITheme.label("아이콘을 끌어 퀵슬롯·키보드에 놓기", 9, UITheme.TEXT_DIM))
	Game.data.changed.connect(func(w): if visible and w in ["skills", "equipment"]: refresh())

func open_window() -> void:
	tab = tab_classes.find(Game.data.weapon_class())
	if tabs: tabs.current_tab = tab
	super.open_window()

static func skill_tooltip(id: String) -> Array:
	var s: Dictionary = Data.skills[id]
	var lv := Game.data.skill_level(id)
	var tier: Dictionary = Data.skill_tiers[s.tier]
	var lines := [[s.name + ("  Lv%d" % lv if lv > 0 else ""), Color(tier.color)]]
	lines.append(["%s · %s · 기력 %d · 쿨 %ds" % [Data.class_name_ko(s.cls), tier.name, s.stamina, s.cooldown], UITheme.TEXT_DIM])
	if s.mult_text != "—": lines.append(["배율 %s (Lv1)" % s.mult_text, Color.WHITE])
	lines.append([s.desc, UITheme.TEXT])
	if s.cls == "chrono": lines.append(["요구 레벨 %d" % s.get("req_level", 1), UITheme.TEXT_DIM])
	var mx := int(Data.bal("skills.max_level"))
	if lv > 0 and lv < mx:
		var nxt := "다음 Lv%d: 피해 +%d%%" % [lv + 1, int(Data.bal("skills.damage_per_level") * 100 * lv)]
		if lv + 1 == 3: nxt += ", 쿨타임 -15%"
		if lv + 1 == mx and s.lv5_desc != "": nxt += ", 강화: " + s.lv5_desc
		lines.append([nxt, UITheme.GREEN])
	elif lv == 0 and s.lv5_desc != "":
		lines.append(["Lv5 강화: " + s.lv5_desc, UITheme.TEXT_DIM])
	elif lv >= mx and s.lv5_desc != "":
		lines.append(["강화됨: " + s.lv5_desc, Color(1, 0.8, 0.4)])
	return lines

func refresh() -> void:
	if list == null: return
	for c in list.get_children(): c.queue_free()
	var cls: String = tab_classes[tab]
	var pd := Game.data
	var arr := Data.skills_of(cls)
	var order := ["old", "trainee", "master", "meridian", "chrono"]
	arr.sort_custom(func(a, b): return order.find(a.tier) < order.find(b.tier) if a.tier != b.tier else int(a.get("req_level", 0)) < int(b.get("req_level", 0)))
	for s in arr:
		var lv := pd.skill_level(s.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := SlotBox.new(Vector2(20, 20))
		b.ui = ui
		b.icon = SpriteFactory.skill_icon(s.id)
		b.silhouette = lv <= 0
		b.border = Color(Data.skill_tiers[s.tier].color).darkened(0.3)
		b.payload = {"type": "skill", "id": s.id} if lv > 0 else null
		var sid: String = s.id
		b.tooltip_fn = func(): return SkillsWindow.skill_tooltip(sid)
		row.add_child(b)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var tier: Dictionary = Data.skill_tiers[s.tier]
		if lv > 0:
			col.add_child(UITheme.label("%s  Lv%d" % [s.name, lv], 11, Color.WHITE))
			var sub := UITheme.label("%s · 기력 %d · 쿨 %ds · %s" % [tier.name, s.stamina, s.cooldown, s.desc], 9, UITheme.TEXT_DIM)
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub.custom_minimum_size.x = 230
			col.add_child(sub)
		else:
			col.add_child(UITheme.label("??? ", 11, UITheme.TEXT_DIM))
			col.add_child(UITheme.label("%s 등급 · 스킬서로 배울 수 있음" % tier.name, 9, Color(tier.color).darkened(0.2)))
		row.add_child(col)
		list.add_child(row)
