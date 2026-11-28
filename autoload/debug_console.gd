extends CanvasLayer
## 개발용 디버그 콘솔. ` (백틱) 또는 F1 로 연다. help 로 명령 목록.

var panel: PanelContainer
var log_label: RichTextLabel
var input: LineEdit
var history: Array[String] = []
var hist_i := 0

const HELP := [
	["help", "명령 목록"],
	["level <n>", "레벨 설정"],
	["exp <n>", "경험치 지급"],
	["give <아이템id> [개수]", "아이템 지급 (무기·방어구·소모품·재료)"],
	["giveall weapons|armor", "무기 54종 또는 방어구 전부 지급 (인벤토리 칸까지)"],
	["book <old|trainee|master|meridian|chrono> <무기군|chrono> [개수]", "스킬서 지급"],
	["learn <스킬id|all|무기군> [레벨]", "스킬 배우기"],
	["equip <무기id>", "무기 바로 장착"],
	["god", "무적 켜기/끄기"],
	["hitbox", "히트박스 표시 켜기/끄기"],
	["spawn <dummy|test_brute> [레벨] [normal|elite|midboss|boss] [수]", "몬스터 소환"],
	["killall", "몬스터 모두 처치"],
	["heal", "HP·기력·물약 가득"],
	["stamina <n>", "기력 설정"],
	["chrono <n>", "크로노포스 설정 (코어 레벨로 환산)"],
	["region <n>", "현재 지역 요구 크로노포스 설정"],
	["mastery <무기군> <레벨>", "무기 숙련도 설정"],
	["points <n>", "스탯 포인트 지급"],
	["look <머리 0-5> <망토 0-5>", "머리색·망토색"],
	["list <weapons|skills|armor|items|monsters>", "id 목록"],
	["clear", "콘솔 비우기"],
]

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.visible = false
	panel.anchor_right = 1.0
	panel.offset_bottom = 170
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.08, 0.92)
	sb.border_color = Color(0.75, 0.95, 1.0, 0.6)
	sb.border_width_bottom = 1
	sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.add_theme_font_override("normal_font", load("res://assets/fonts/Galmuri9.ttf"))
	log_label.add_theme_font_size_override("normal_font_size", 10)
	v.add_child(log_label)
	input = LineEdit.new()
	input.placeholder_text = "명령 입력 (help)"
	input.add_theme_font_size_override("font_size", 12)
	input.text_submitted.connect(_on_submit)
	v.add_child(input)
	out("[color=#9fe0ff]디버그 콘솔[/color] — help 로 명령 목록. ` 또는 F1 로 닫기")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_F1:
			toggle()
			get_viewport().set_input_as_handled()
		elif panel.visible and event.physical_keycode == KEY_UP and history.size() > 0:
			hist_i = maxi(0, hist_i - 1); input.text = history[hist_i]; input.caret_column = input.text.length()
			get_viewport().set_input_as_handled()
		elif panel.visible and event.physical_keycode == KEY_DOWN and history.size() > 0:
			hist_i = mini(history.size() - 1, hist_i + 1); input.text = history[hist_i]; input.caret_column = input.text.length()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	panel.visible = not panel.visible
	InputManager.blocked = panel.visible
	if panel.visible:
		input.grab_focus()
		InputManager.clear_buffer()
	else:
		input.release_focus()

func out(s: String) -> void:
	log_label.append_text(s + "\n")

func _on_submit(text: String) -> void:
	input.clear()
	text = text.strip_edges()
	if text == "": return
	history.append(text); hist_i = history.size()
	out("> " + text)
	var r := run(text)
	if r != "": out(r)

## 명령 실행 (테스트에서도 쓴다). 결과 문자열 반환.
func run(text: String) -> String:
	var a := text.split(" ", false)
	var cmd := a[0].to_lower()
	var pd: PlayerData = Game.data
	var pl: Player = Game.player
	match cmd:
		"help":
			var s := ""
			for h in HELP: s += "[color=#ffd98a]%s[/color]  %s\n" % h
			return s
		"clear":
			log_label.clear(); return ""
		"level":
			if a.size() < 2: return "사용법: level <n>"
			var n := clampi(int(a[1]), 1, int(Data.bal("exp.max_level")))
			var gained := (n - pd.level) * int(Data.bal("stats.points_per_level"))
			pd.level = n; pd.exp = 0
			pd.stat_points = maxi(0, pd.stat_points + gained)
			pd.changed.emit("exp"); pd.changed.emit("stats")
			if pl: pl.max_hp = pd.max_hp(); pl.hp = pl.max_hp
			return "레벨 %d" % n
		"exp":
			pd.gain_exp(float(a[1]) if a.size() > 1 else 100.0); return "경험치 지급"
		"give":
			if a.size() < 2: return "사용법: give <id> [개수]"
			var id := a[1]
			var n := int(a[2]) if a.size() > 2 else 1
			if Data.weapons.has(id) or Data.armor.has(id):
				for i in n: pd.add_item(Items.make(id))
				return "%s ×%d" % [Data.item_def(id).name, n]
			if Data.consumables.has(id) or Data.materials.has(id):
				pd.add_stack(id, n); return "%s ×%d" % [Data.item_def(id).name, n]
			return "없는 아이템: " + id
		"giveall":
			var kind := a[1] if a.size() > 1 else "weapons"
			var src: Array = Data.weapons.keys() if kind == "weapons" else Data.armor.keys()
			var c := 0
			for id in src:
				if pd.inv_equip.find(null) < 0: break
				pd.add_item(Items.make(id), false); c += 1
			return "%d개 지급" % c
		"book":
			if a.size() < 3: return "사용법: book <tier> <무기군|chrono> [개수]"
			pd.add_book(a[1], a[2], int(a[3]) if a.size() > 3 else 1); return "스킬서 지급"
		"learn":
			if a.size() < 2: return "사용법: learn <스킬id|all|무기군> [레벨]"
			var lv := int(a[2]) if a.size() > 2 else 1
			var ids := []
			if a[1] == "all": ids = Data.skills.keys()
			elif a[1] in Data.CLASSES or a[1] == "chrono": ids = Data.skills_of(a[1]).map(func(s): return s.id)
			elif Data.skills.has(a[1]): ids = [a[1]]
			else: return "없는 스킬: " + a[1]
			for id in ids:
				while pd.skill_level(id) < lv: pd.learn_skill(id)
			return "%d개 스킬 Lv%d" % [ids.size(), lv]
		"equip":
			if a.size() < 2 or not Data.weapons.has(a[1]): return "사용법: equip <무기id>"
			var it := Items.make_weapon(a[1])
			pd.equipment.weapon = it
			pd.changed.emit("equipment"); pd.changed.emit("stats")
			return "장착: " + Data.weapons[a[1]].name
		"god":
			Game.god_mode = not Game.god_mode; return "무적 " + ("켜짐" if Game.god_mode else "꺼짐")
		"hitbox":
			var on = not Settings.get_value("debug", "hitboxes", false)
			Settings.set_value("debug", "hitboxes", on); return "히트박스 표시 " + ("켜짐" if on else "꺼짐")
		"spawn":
			if a.size() < 2 or not Data.monsters.has(a[1]): return "사용법: spawn <%s> [레벨] [등급] [수]" % "|".join(Data.monsters.keys())
			if Game.world == null or pl == null: return "월드 없음"
			var lv := int(a[2]) if a.size() > 2 else -1
			var rank := a[3] if a.size() > 3 else ""
			var n := int(a[4]) if a.size() > 4 else 1
			for i in n:
				var e: Enemy = Game.world.spawn_enemy(a[1], pl.global_position + pl.facing * 48 + Vector2(randf_range(-20, 20), randf_range(-20, 20)), lv, rank)
				e.respawn = false
			return "소환 %s ×%d" % [a[1], n]
		"killall":
			var c := 0
			for e in Game.enemies():
				if not e.dead and not e.def.get("infinite", false):
					var h := HitInfo.new(); h.team = "player"; h.base_attack = e.max_hp * 10; h.ignore_defense = true; h.no_crit = true
					e.take_hit(h); c += 1
			return "%d마리 처치" % c
		"heal":
			if pl: pl.hp = pl.max_hp
			pd.stamina = pd.stamina_max(); pd.potion_charges = pd.potion_max
			return "회복"
		"stamina":
			pd.stamina = clampf(float(a[1]) if a.size() > 1 else 100.0, 0, pd.stamina_max()); return "기력 %d" % pd.stamina
		"chrono":
			var v := int(a[1]) if a.size() > 1 else 0
			for i in 6: pd.cores[i] = null
			var left := v / int(Data.bal("chronoforce.core_per_level"))
			var i := 0
			while left > 0 and i < 6:
				var l := mini(left, int(Data.bal("chronoforce.core_max_level")))
				pd.cores[i] = {"region": i + 1, "level": l}
				left -= l; i += 1
			pd.changed.emit("stats"); pd.changed.emit("equipment")
			return "크로노포스 %d (결정 무늬 %d단계)" % [pd.chronoforce(), pd.crystal_stage()]
		"region":
			pd.region_requirement = int(a[1]) if a.size() > 1 else 0
			pd.changed.emit("stats")
			return "지역 요구 크로노포스 %d" % pd.region_requirement
		"mastery":
			if a.size() < 3 or not a[1] in Data.CLASSES: return "사용법: mastery <무기군> <레벨>"
			pd.mastery[a[1]].level = clampi(int(a[2]), 1, 10); pd.changed.emit("stats")
			return "%s 숙련도 Lv%d" % [Data.class_name_ko(a[1]), pd.mastery[a[1]].level]
		"points":
			pd.stat_points += int(a[1]) if a.size() > 1 else 10; pd.changed.emit("stats"); return "스탯 포인트 %d" % pd.stat_points
		"look":
			pd.appearance.hair = int(a[1]) if a.size() > 1 else 0
			pd.appearance.cape = int(a[2]) if a.size() > 2 else 0
			pd.changed.emit("equipment"); return "외형 변경"
		"list":
			var what := a[1] if a.size() > 1 else "weapons"
			var keys: Array = {"weapons": Data.weapons.keys(), "skills": Data.skills.keys(), "armor": Data.armor.keys(),
				"items": Data.consumables.keys() + Data.materials.keys(), "monsters": Data.monsters.keys()}.get(what, [])
			return ", ".join(keys)
	return "알 수 없는 명령: %s (help)" % cmd
