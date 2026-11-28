class_name StatsWindow
extends GameWindow
## 스탯창 (T): 기본 스탯 4종 + 분배, 초기화, 파생 스탯 전체, 크로노포스, 무기 숙련도 (GDD 6장, 12-3).

const NAMES := {"str": ["힘", "근접 무기 공격력, 그로기 누적 +0.5%/점"], "dex": ["민첩", "치명타 확률 +0.1%/점, 공격속도 +0.1%/점"],
	"int": ["지능", "스킬 피해 +0.3%/점, 기력 획득 +0.2%/점"], "vit": ["체력", "최대 HP +10/점, 방어력 +0.5/점"]}

var points_label: Label
var stat_rows := {}
var derived: GridContainer
var mastery_box: VBoxContainer

func _init() -> void:
	super._init("stats", "스탯", Vector2(20, 30))

func _ready() -> void:
	super._ready()
	points_label = UITheme.label("", 11, UITheme.GOLD.lightened(0.3))
	body.add_child(points_label)
	for s in PlayerData.STATS:
		var row := HBoxContainer.new()
		var n := UITheme.label(NAMES[s][0], 11)
		n.custom_minimum_size.x = 30
		n.tooltip_text = NAMES[s][1]
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(n)
		var v := UITheme.label("", 11, Color.WHITE)
		v.custom_minimum_size.x = 30
		row.add_child(v)
		var st: String = s
		row.add_child(UITheme.button("+1", func(): Game.data.allocate(st, 1), 10))
		row.add_child(UITheme.button("+5", func(): Game.data.allocate(st, mini(5, Game.data.stat_points)), 10))
		var desc := UITheme.label(NAMES[s][1], 9, UITheme.TEXT_DIM)
		row.add_child(desc)
		body.add_child(row)
		stat_rows[s] = v
	body.add_child(UITheme.button("스탯 초기화 (첫 1회 무료, 이후 망각의 모래)", func():
		var err := Game.data.reset_stats(true)
		if err != "": ui.show_notice(err, UITheme.RED), 10))
	body.add_child(UITheme.label("파생 스탯", 10, UITheme.GOLD.lightened(0.3)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	body.add_child(cols)
	derived = GridContainer.new()
	derived.columns = 4
	derived.add_theme_constant_override("h_separation", 4)
	derived.add_theme_constant_override("v_separation", 0)
	cols.add_child(derived)
	mastery_box = VBoxContainer.new()
	mastery_box.add_theme_constant_override("separation", 0)
	cols.add_child(mastery_box)
	Game.data.changed.connect(func(w): if visible and w in ["stats", "equipment", "exp"]: refresh())

func refresh() -> void:
	if derived == null: return
	var pd := Game.data
	points_label.text = "Lv %d   남은 포인트 %d" % [pd.level, pd.stat_points]
	for s in stat_rows:
		var tot := pd.stat_total(s)
		stat_rows[s].text = "%d" % tot if tot == pd.stats[s] else "%d (+%d)" % [pd.stats[s], tot - pd.stats[s]]
	for c in derived.get_children(): c.queue_free()
	for c in mastery_box.get_children(): c.queue_free()
	var cm := pd.chrono_mults()
	var lines := [
		["최대 HP", "%d" % pd.max_hp()],
		["공격력", "%d" % pd.attack_power()],
		["방어력", "%.1f" % pd.defense()],
		["피해 감소", "%.1f%%" % (pd.damage_reduction() * 100)],
		["치명타 확률", "%.1f%%" % (pd.crit_chance() * 100)],
		["치명타 피해", "%d%%" % (pd.crit_damage() * 100)],
		["공격속도", "%.2f" % pd.attack_speed()],
		["이동속도", "%d" % pd.move_speed()],
		["쿨타임 감소", "%d%%" % (pd.cdr() * 100)],
		["기력 최대", "%d" % pd.stamina_max()],
		["기력 획득", "+%d%%" % ((pd.stamina_gain_mult() - 1) * 100)],
		["스킬 피해", "+%.1f%%" % ((pd.skill_damage_mult() - 1) * 100)],
		["그로기 누적", "×%.2f" % pd.groggy_mult()],
		["크로노포스", "%d / 요구 %d" % [pd.chronoforce(), pd.region_requirement]],
		["주는/받는 피해", "×%.2f / ×%.2f" % [cm[0], cm[1]]],
	]
	for l in lines:
		derived.add_child(UITheme.label(l[0], 9, UITheme.TEXT_DIM))
		derived.add_child(UITheme.label(l[1], 9, Color.WHITE))
	mastery_box.add_child(UITheme.label("무기 숙련도", 10, UITheme.GOLD.lightened(0.3)))
	for c in Data.CLASSES:
		var m: Dictionary = pd.mastery[c]
		var row := HBoxContainer.new()
		var cur = c == pd.weapon_class()
		var a := UITheme.label(Data.class_name_ko(c), 9, UITheme.CRYSTAL if cur else UITheme.TEXT_DIM); a.custom_minimum_size.x = 34
		row.add_child(a)
		row.add_child(UITheme.label("Lv%d" % m.level, 9, Color.WHITE))
		var bar := UITheme.bar(Color(0.95, 0.8, 0.35))
		bar.custom_minimum_size = Vector2(40, 5)
		bar.max_value = PlayerData.mastery_to_next(m.level)
		bar.value = m.exp if m.level < 10 else bar.max_value
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var pas: Dictionary = Data.classes[c].get("mastery_passives", {})
		var tip := ""
		for lv in pas:
			var on: bool = m.level >= int(lv)
			tip += "%sLv%s %s%s\n" % ["● " if on else "○ ", lv, pas[lv].desc, " (열림)" if on else ""]
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(4, 4)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.color = UITheme.GREEN if on else Color(0.3, 0.3, 0.35)
			row.add_child(dot)
		row.tooltip_text = tip.strip_edges()
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		mastery_box.add_child(row)
	mastery_box.add_child(UITheme.label("점: Lv5·Lv10 패시브 (마우스를 올리면 설명)", 9, UITheme.TEXT_DIM))
