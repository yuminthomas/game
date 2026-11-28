class_name HUD
extends Control
## 플레이 화면 HUD (GDD 12-2). 막대와 글자는 _draw 로 그리고, 퀵슬롯만 드롭을 받는 SlotBox 로 만든다.

const SLOTS := ["slot_skill_1", "slot_skill_2", "slot_skill_3", "slot_skill_4", "slot_chrono_1", "slot_chrono_2"]

var ui: UIRoot
var slot_boxes := {}
var potion_box: SlotBox
var bottom: Control
var logs: Array = []          # [text, color, t]
var big_minimap := false
var minimap_tex: ImageTexture
var visited := {}
var zone_title_t := 4.0
var levelup_t := 0.0
var fade := 1.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom = Control.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var x := 0.0
	for s in SLOTS:
		var b := SlotBox.new(Vector2(20, 20))
		b.ui = ui
		b.position = Vector2(x, 0)
		var slot: String = s
		b.accept = func(d): return d is Dictionary and d.get("type") == "skill" and _slot_kind_ok(slot, d.id)
		b.on_drop = func(d): Game.data.set_slot_skill(slot, d.id)
		b.tooltip_fn = func(): return _skill_tip(Game.data.slot_skill(slot))
		b.on_click = func(btn, _dbl): if btn == MOUSE_BUTTON_RIGHT: Game.data.set_slot_skill(slot, "")
		bottom.add_child(b)
		slot_boxes[s] = b
		x += 22 if s != "slot_skill_4" else 28
	potion_box = SlotBox.new(Vector2(20, 20))
	potion_box.ui = ui
	potion_box.icon = SpriteFactory.item_icon("potion")
	potion_box.position = Vector2(x + 6, 0)
	potion_box.tooltip_fn = func(): return [["회복 물약", Color(1, 0.6, 0.6)], ["최대 HP %d%% 회복 · %d/%d회" % [int(Data.bal("potion.heal_pct") * 100), Game.data.potion_charges, Game.data.potion_max], UITheme.TEXT_DIM]]
	bottom.add_child(potion_box)
	bottom.size = Vector2(x + 30, 20)
	Game.data.leveled_up.connect(func(_lv): levelup_t = 2.0)
	_apply_scale()
	Settings.changed.connect(func(_s, _k): _apply_scale())

func _apply_scale() -> void:
	var sc := float(Settings.get_value("gameplay", "hud_scale", 1.0))
	bottom.scale = Vector2(sc, sc)
	bottom.position = Vector2(320 - bottom.size.x * sc / 2, 360 - 30 * sc).round()

func _slot_kind_ok(slot: String, skill_id: String) -> bool:
	var s: Dictionary = Data.skills.get(skill_id, {})
	if s.is_empty() or Game.data.skill_level(skill_id) <= 0: return false
	if slot.begins_with("slot_chrono"): return s.cls == "chrono"
	return s.cls == Game.data.weapon_class()

func _skill_tip(id: String) -> Array:
	if id == "": return [["빈 슬롯", UITheme.TEXT_DIM], ["스킬창(K)에서 스킬을 끌어다 놓으세요", UITheme.TEXT_DIM]]
	return SkillsWindow.skill_tooltip(id)

func toggle_minimap() -> void:
	big_minimap = not big_minimap

func log_item(text: String, color: Color) -> void:
	logs.push_front([text, color, 3.0])
	if logs.size() > 6: logs.pop_back()

func _process(delta: float) -> void:
	var pl: Player = Game.player
	if pl == null: return
	for l in logs: l[2] -= delta
	logs = logs.filter(func(l): return l[2] > 0)
	zone_title_t = maxf(0, zone_title_t - delta)
	levelup_t = maxf(0, levelup_t - delta)
	# 자동 흐려짐 (탐험 중)
	var want := 1.0
	if Settings.get_value("gameplay", "hud_fade", false) and not pl.is_in_combat(): want = 0.35
	fade = move_toward(fade, want, delta * 2)
	modulate.a = fade
	# 퀵슬롯
	var pd := Game.data
	for s in SLOTS:
		var b: SlotBox = slot_boxes[s]
		var id := pd.slot_skill(s)
		b.icon = SpriteFactory.skill_icon(id) if id != "" else null
		b.key_text = InputManager.key_label(InputManager.key_for(s))
		b.empty_hint = "" if id != "" else "+"
		b.payload = {"type": "skill", "id": id} if id != "" else null
		if id != "":
			var cd: float = pl.cooldowns.get(id, 0.0)
			var tot: float = pl.cooldown_total.get(id, 1.0)
			b.cooldown = clampf(cd / maxf(tot, 0.01), 0, 1) if int(pl.skill_charges.get(id, 0)) <= 0 else 0.0
			b.dim = pd.stamina < float(Data.skills[id].stamina)
			b.count_text = str(pd.skill_level(id))
		else:
			b.cooldown = 0; b.dim = false; b.count_text = ""
		b.queue_redraw()
	potion_box.key_text = InputManager.key_label(InputManager.key_for("item_potion"))
	potion_box.count_text = str(pd.potion_charges)
	potion_box.dim = pd.potion_charges <= 0
	potion_box.queue_redraw()
	# 방문 기록 (미니맵 안개)
	visited[Vector2i(pl.global_position / 64.0)] = true
	queue_redraw()

func _draw() -> void:
	var pl: Player = Game.player
	if pl == null: return
	var pd := Game.data
	UITheme.fonts()
	var f := UITheme.font
	var fs := UITheme.font_small
	var sc := float(Settings.get_value("gameplay", "hud_scale", 1.0))
	draw_set_transform(Vector2(4, 4), 0, Vector2(sc, sc))
	# --- 좌상단: 레벨, HP, 기력, 상태이상
	_text(f, Vector2(0, 10), "Lv %d" % pd.level, 12, UITheme.GOLD.lightened(0.35))
	var bx := 42.0
	_bar(Rect2(bx, 1, 120, 8), pl.hp / maxf(1, pl.max_hp), Color(0.85, 0.2, 0.25), Color(0.25, 0.05, 0.08))
	_text(fs, Vector2(bx + 3, 8), "%d / %d" % [pl.hp, pl.max_hp], 9, Color.WHITE)
	_bar(Rect2(bx, 11, 120, 5), pd.stamina / pd.stamina_max(), UITheme.CRYSTAL, Color(0.08, 0.15, 0.2))
	_text(fs, Vector2(bx + 124, 17), "%d" % pd.stamina, 9, UITheme.CRYSTAL)
	var buff_shield := pl.buff_data("mana_shield")
	if not buff_shield.is_empty() and buff_shield.left_amount > 0:
		_bar(Rect2(bx, -1, 120 * clampf(buff_shield.left_amount / pl.max_hp, 0, 1), 2), 1, Color(0.6, 0.8, 1), Color(0, 0, 0, 0))
	var ix := 0.0
	for s in pl.statuses.icons():
		var c := Color(Data.statuses[s.id].color)
		draw_rect(Rect2(bx + ix, 19, 10, 10), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx + ix + 1, 20, 8, 8), c * Color(1, 1, 1, 0.8))
		_text(fs, Vector2(bx + ix + 2, 27), Data.statuses[s.id].name.left(1), 9, Color.BLACK)
		ix += 12
	for b in pl.buffs:
		draw_rect(Rect2(bx + ix, 19, 10, 10), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bx + ix + 1, 20, 8, 8), Color(1, 0.85, 0.4, 0.8))
		ix += 12
	# --- 우상단: 미니맵, 구역 이름, 시간, 크로노포스
	draw_set_transform(Vector2(640 - 4, 4), 0, Vector2(sc, sc))
	var mm := Vector2(150, 100) if big_minimap else Vector2(96, 64)
	var mr := Rect2(Vector2(-mm.x, 0), mm)
	draw_rect(mr, Color(0.03, 0.04, 0.08, 0.75))
	_draw_minimap(mr)
	draw_rect(mr, UITheme.GOLD_DIM, false, 1)
	var zn: String = Game.world.zone_name if Game.world else ""
	_text_right(fs, Vector2(0, mm.y + 10), "☀ " + zn, 9, UITheme.TEXT)
	var cf := pd.chronoforce()
	var req := pd.region_requirement
	var cm := pd.chrono_mults()
	var ok := req <= 0 or cf >= req
	_text_right(fs, Vector2(0, mm.y + 21), "크로노포스 %d / %d%s" % [cf, req, "" if ok else "  피해 ×%.1f" % cm[0]], 9, UITheme.CRYSTAL if ok else UITheme.RED)
	# --- 상단 중앙: 보스·중간보스 HP
	draw_set_transform(Vector2.ZERO)
	var boss := _boss_target(pl)
	if boss:
		var w := 240.0
		var x := 320 - w / 2
		_text(f, Vector2(x, 14), boss.display_name(), 12, Color(1, 0.85, 0.7))
		_bar(Rect2(x, 18, w, 6), boss.hp / boss.max_hp, Color(0.8, 0.2, 0.2), Color(0.15, 0.03, 0.05))
		if boss.groggy_max > 0:
			_bar(Rect2(x, 25, w, 2), boss.groggy_value / boss.groggy_max if not boss.statuses.has("groggy") else 1.0, Color(1, 0.85, 0.2), Color(0.1, 0.1, 0.05))
	# --- 하단: 대시 충전, 경험치
	var bpos := bottom.position + Vector2(bottom.size.x * sc + 4, 4)
	var mx := pl.max_dash_charges()
	for i in int(mx):
		var fill := clampf(pl.dash_charges - i, 0, 1)
		draw_rect(Rect2(bpos + Vector2(i * 7, 0), Vector2(5, 12)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bpos + Vector2(i * 7, 12 - 12 * fill), Vector2(5, 12 * fill)), UITheme.CRYSTAL if fill >= 1 else UITheme.CRYSTAL.darkened(0.5))
	var need := PlayerData.exp_to_next(pd.level)
	var ratio := pd.exp / maxf(1, need)
	draw_rect(Rect2(0, 357, 640, 3), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(0, 357, 640 * ratio, 3), Color(0.95, 0.8, 0.35))
	_text(fs, Vector2(4, 354), "EXP %.1f%%" % (ratio * 100), 9, Color(0.95, 0.85, 0.5))
	# --- 우측 중단: 획득 로그
	var ly := 150.0
	for l in logs:
		var col: Color = l[1]; col.a = clampf(l[2], 0, 1)
		var tw := fs.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		_text(fs, Vector2(636 - tw, ly), l[0], 9, col)
		ly += 11
	# --- 화면 중앙: 구역 이름, 레벨업
	if zone_title_t > 0:
		var a := clampf(minf(zone_title_t, 4.0 - zone_title_t) * 1.5, 0, 1)
		_center_text(f, 120, zn, 16, Color(1, 0.95, 0.85, a))
	if levelup_t > 0:
		_center_text(f, 100, "LEVEL UP  Lv %d" % pd.level, 16, Color(1, 0.9, 0.4, clampf(levelup_t, 0, 1)))
		if pd.stat_points > 0: _center_text(fs, 114, "스탯 포인트 %d (T)" % pd.stat_points, 10, Color(1, 0.95, 0.7, clampf(levelup_t, 0, 1)))

func _boss_target(pl: Player) -> Enemy:
	for e in Game.enemies():
		if not e.dead and e.is_boss() and e.global_position.distance_to(pl.global_position) < 260: return e
	return null

func _draw_minimap(r: Rect2) -> void:
	var w: TestZone = Game.world
	if w == null: return
	var sx := r.size.x / (w.W * w.T)
	var sy := r.size.y / (w.H * w.T)
	for cell in visited:
		var rr := Rect2(r.position + Vector2(cell.x * 64 * sx, cell.y * 64 * sy), Vector2(64 * sx + 1, 64 * sy + 1)).intersection(r)
		draw_rect(rr, Color(0.25, 0.4, 0.25, 0.7))
	for c in w.solid:
		var cell := Vector2i(c.x * w.T / 64, c.y * w.T / 64)
		if visited.has(cell):
			draw_rect(Rect2(r.position + Vector2(c.x * w.T * sx, c.y * w.T * sy), Vector2(maxf(1, w.T * sx), maxf(1, w.T * sy))), Color(0.1, 0.2, 0.1, 0.9))
	for e in Game.enemies():
		if not e.dead and visited.has(Vector2i(e.global_position / 64.0)):
			draw_rect(Rect2(r.position + e.global_position * Vector2(sx, sy) - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.4, 0.4) if not e.def.get("infinite", false) else Color(0.9, 0.8, 0.5))
	var pp: Vector2 = r.position + Game.player.global_position * Vector2(sx, sy)
	draw_rect(Rect2(pp - Vector2(1.5, 1.5), Vector2(3, 3)), UITheme.CRYSTAL)

func _bar(r: Rect2, ratio: float, fill: Color, bg: Color) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.7))
	draw_rect(r, bg)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0, 1), r.size.y)), fill)

func _text(font: Font, p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _text_right(font: Font, p: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(font, p - Vector2(w, 0), s, size, col)

func _center_text(font: Font, y: float, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(font, Vector2(320 - w / 2, y), s, size, col)
