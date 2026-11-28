class_name KeyConfigWindow
extends GameWindow
## 키 설정창 (O, GDD 12-4): 키보드 그림 + 아래 배정 가능 목록. 아이콘을 끌어 키에 놓으면 배정,
## 다른 기능이 있는 키에 놓으면 서로 교체, 키의 아이콘을 키보드 밖으로 끌어내면 해제.
## 기본값 복원 / 취소 / 저장. 필수 키(이동, 공격, 대시, Esc)는 비울 수 없다.

const ROWS := [
	[[KEY_ESCAPE, 1.0], [KEY_QUOTELEFT, 1.0], [KEY_1, 1.0], [KEY_2, 1.0], [KEY_3, 1.0], [KEY_4, 1.0], [KEY_5, 1.0], [KEY_6, 1.0], [KEY_7, 1.0], [KEY_8, 1.0], [KEY_9, 1.0], [KEY_0, 1.0], [KEY_MINUS, 1.0], [KEY_EQUAL, 1.0]],
	[[KEY_TAB, 1.5], [KEY_Q, 1.0], [KEY_W, 1.0], [KEY_E, 1.0], [KEY_R, 1.0], [KEY_T, 1.0], [KEY_Y, 1.0], [KEY_U, 1.0], [KEY_I, 1.0], [KEY_O, 1.0], [KEY_P, 1.0], [KEY_BRACKETLEFT, 1.0], [KEY_BRACKETRIGHT, 1.0]],
	[[-1, 1.8], [KEY_A, 1.0], [KEY_S, 1.0], [KEY_D, 1.0], [KEY_F, 1.0], [KEY_G, 1.0], [KEY_H, 1.0], [KEY_J, 1.0], [KEY_K, 1.0], [KEY_L, 1.0], [KEY_SEMICOLON, 1.0], [KEY_APOSTROPHE, 1.0], [KEY_ENTER, 1.4]],
	[[KEY_SHIFT, 2.3], [KEY_Z, 1.0], [KEY_X, 1.0], [KEY_C, 1.0], [KEY_V, 1.0], [KEY_B, 1.0], [KEY_N, 1.0], [KEY_M, 1.0], [KEY_COMMA, 1.0], [KEY_PERIOD, 1.0], [KEY_SLASH, 1.0], [-1, 0.4], [KEY_UP, 1.0]],
	[[KEY_CTRL, 1.5], [KEY_ALT, 1.5], [KEY_SPACE, 6.0], [-1, 2.9], [KEY_LEFT, 1.0], [KEY_DOWN, 1.0], [KEY_RIGHT, 1.0]],
]
const U := 20.0

const ACTION_NAMES := {"attack": "기본 공격", "dash": "대시", "parry": "패링", "interact": "상호작용",
	"slot_skill_1": "스킬 1", "slot_skill_2": "스킬 2", "slot_skill_3": "스킬 3", "slot_skill_4": "스킬 4", "slot_chrono_1": "크로노 1", "slot_chrono_2": "크로노 2",
	"item_potion": "회복 물약", "item_herb": "약초 다발", "item_candy": "기력 사탕",
	"win_inventory": "인벤토리", "win_equipment": "장비", "win_stats": "스탯", "win_skills": "스킬", "win_keyconfig": "키 설정",
	"win_worldmap": "월드맵", "win_codex": "도감", "minimap": "미니맵 크기", "menu": "메뉴"}

var edit := {}
var edit_wasd := false
var pending_slots := {}
var keyboard: Control
var key_boxes := {}
var palette: VBoxContainer
var wasd_box: CheckBox

func _init() -> void:
	super._init("keyconfig", "키 설정", Vector2(140, 40))

func _ready() -> void:
	super._ready()
	keyboard = Control.new()
	keyboard.custom_minimum_size = Vector2(14.5 * U, 5 * U)
	body.add_child(keyboard)
	var y := 0.0
	for row in ROWS:
		var x := 0.0
		for k in row:
			if k[0] != -1:
				var b := SlotBox.new(Vector2(k[1] * U - 2, U - 2))
				b.ui = ui
				b.position = Vector2(x, y)
				var kc: int = k[0]
				b.accept = func(d): return _accepts(kc, d)
				b.on_drop = func(d): _drop(kc, d)
				b.tooltip_fn = func(): return _key_tip(kc)
				b.on_click = func(btn, _dbl): if btn == MOUSE_BUTTON_RIGHT: _unbind(kc)
				keyboard.add_child(b)
				key_boxes[kc] = b
			x += k[1] * U
		y += U
	var opts := HBoxContainer.new()
	body.add_child(opts)
	wasd_box = CheckBox.new()
	wasd_box.text = "WASD 로 이동"
	wasd_box.focus_mode = Control.FOCUS_NONE
	wasd_box.toggled.connect(func(on): edit_wasd = on; if on: _strip_wasd(); _redraw_keys())
	opts.add_child(wasd_box)
	opts.add_child(UITheme.label("  우클릭/밖으로 끌기: 해제", 9, UITheme.TEXT_DIM))
	palette = VBoxContainer.new()
	palette.add_theme_constant_override("separation", 2)
	body.add_child(palette)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(btns)
	btns.add_child(UITheme.button("기본값 복원", func(): edit = InputManager.DEFAULT_KEYS.duplicate(); if edit_wasd: _strip_wasd(); pending_slots.clear(); _redraw_keys(), 10))
	btns.add_child(UITheme.button("취소", func(): _load(); close_window(), 10))
	btns.add_child(UITheme.button("저장", _save, 10))
	Game.data.changed.connect(func(w): if visible and w in ["skills", "equipment"]: _build_palette())

func open_window() -> void:
	_load()
	super.open_window()

func _load() -> void:
	edit = InputManager.keymap.duplicate()
	edit_wasd = InputManager.wasd
	pending_slots.clear()
	if wasd_box: wasd_box.set_pressed_no_signal(edit_wasd)
	_build_palette()
	_redraw_keys()

func _strip_wasd() -> void:
	for k in InputManager.WASD: edit.erase(k)

func _move_keys() -> Dictionary:
	var d := InputManager.ARROWS.duplicate()
	if edit_wasd: d.merge(InputManager.WASD)
	return d

func _save() -> void:
	var miss := InputManager.commit(edit, edit_wasd)
	if not miss.is_empty():
		ui.show_notice("비울 수 없는 키: " + ", ".join(miss.map(func(a): return ACTION_NAMES.get(a, a))), UITheme.RED)
		return
	for slot in pending_slots: Game.data.set_slot_skill(slot, pending_slots[slot])
	pending_slots.clear()
	ui.show_notice("키 설정을 저장했습니다", UITheme.CRYSTAL)
	close_window()

func _slot_skill(slot: String) -> String:
	return pending_slots.get(slot, Game.data.slot_skill(slot))

func _icon_for(action: String) -> Texture2D:
	if action.begins_with("slot_"):
		var sid := _slot_skill(action)
		return SpriteFactory.skill_icon(sid) if sid != "" else SpriteFactory.action_icon("menu")
	return SpriteFactory.action_icon(action)

func _redraw_keys() -> void:
	var mk := _move_keys()
	for kc in key_boxes:
		var b: SlotBox = key_boxes[kc]
		b.key_text = InputManager.key_label(kc)
		var a = edit.get(kc)
		if mk.has(kc):
			b.icon = null; b.corner_text = "이동"; b.payload = null; b.dim = true
		elif a != null:
			b.icon = _icon_for(a); b.corner_text = ""; b.dim = false
			b.payload = {"type": "key", "keycode": kc}
		else:
			b.icon = null; b.corner_text = ""; b.payload = null; b.dim = false
		b.highlight = a in InputManager.REQUIRED
		b.queue_redraw()

func _key_tip(kc: int) -> Array:
	if _move_keys().has(kc): return [["%s : 이동 (고정)" % InputManager.key_label(kc), UITheme.TEXT_DIM]]
	var a = edit.get(kc)
	if a == null: return [["%s : (비어 있음)" % InputManager.key_label(kc), UITheme.TEXT_DIM]]
	var lines := [["%s : %s" % [InputManager.key_label(kc), ACTION_NAMES.get(a, a)], UITheme.GOLD.lightened(0.3)]]
	if a.begins_with("slot_"):
		var sid := _slot_skill(a)
		lines.append([Data.skills[sid].name if sid != "" else "(빈 슬롯)", UITheme.CRYSTAL])
	if a in InputManager.REQUIRED: lines.append(["필수 키 (비울 수 없음)", UITheme.RED])
	return lines

func _accepts(kc: int, d) -> bool:
	if _move_keys().has(kc) or not d is Dictionary: return false
	return d.get("type") in ["action", "key", "skill"]

func _drop(kc: int, d: Dictionary) -> void:
	match d.type:
		"action":
			InputManager.assign(edit, kc, d.action)
		"key":
			var a = edit.get(d.keycode)
			if a != null: InputManager.assign(edit, kc, a)
		"skill":
			_drop_skill(kc, d.id)
	_redraw_keys()

## 스킬을 키에 놓기: 그 키가 맞는 종류의 슬롯이면 슬롯 내용을 바꾸고, 아니면 빈 슬롯을 골라 키에 배정
func _drop_skill(kc: int, sid: String) -> void:
	var s: Dictionary = Data.skills[sid]
	var chrono: bool = s.cls == "chrono"
	if not chrono and s.cls != Game.data.weapon_class():
		ui.show_notice("현재 무기군의 스킬만 배치할 수 있습니다", UITheme.RED); return
	var prefix := "slot_chrono_" if chrono else "slot_skill_"
	var count := 2 if chrono else 4
	var cur = edit.get(kc)
	var slot := ""
	if cur != null and str(cur).begins_with(prefix): slot = cur
	else:
		for i in range(1, count + 1):
			if _slot_skill(prefix + str(i)) == sid: slot = prefix + str(i)
		if slot == "":
			for i in range(1, count + 1):
				if _slot_skill(prefix + str(i)) == "": slot = prefix + str(i); break
		if slot == "": slot = prefix + str(count)
		InputManager.assign(edit, kc, slot)
	for k in pending_slots.keys():
		if pending_slots[k] == sid: pending_slots[k] = ""
	for i in range(1, count + 1):
		if Game.data.slot_skill(prefix + str(i)) == sid and not pending_slots.has(prefix + str(i)): pending_slots[prefix + str(i)] = ""
	pending_slots[slot] = sid

func _unbind(kc: int) -> void:
	edit.erase(kc)
	_redraw_keys()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and visible:
		var d = get_viewport().gui_get_drag_data()
		if d is Dictionary and d.get("type") == "key" and not get_viewport().gui_is_drag_successful():
			_unbind(d.keycode)

func _build_palette() -> void:
	if palette == null: return
	for c in palette.get_children(): c.queue_free()
	var groups := [["기본 행동", InputManager.BINDABLE.basic], ["스킬 슬롯", InputManager.BINDABLE.skill], ["소모품", InputManager.BINDABLE.item], ["창 열기", InputManager.BINDABLE.window]]
	for g in groups:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var l := UITheme.label(g[0], 9, UITheme.TEXT_DIM); l.custom_minimum_size.x = 44
		row.add_child(l)
		for a in g[1]:
			row.add_child(_palette_box({"type": "action", "action": a}, _icon_for(a), ACTION_NAMES.get(a, a)))
		palette.add_child(row)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 2)
	var sl := UITheme.label("배운 스킬", 9, UITheme.TEXT_DIM); sl.custom_minimum_size.x = 44
	srow.add_child(sl)
	for s in Data.skills_of(Game.data.weapon_class()) + Data.skills_of("chrono"):
		if Game.data.skill_level(s.id) > 0:
			srow.add_child(_palette_box({"type": "skill", "id": s.id}, SpriteFactory.skill_icon(s.id), s.name))
	palette.add_child(srow)

func _palette_box(payload: Dictionary, icon: Texture2D, name: String) -> SlotBox:
	var b := SlotBox.new(Vector2(18, 18))
	b.ui = ui
	b.icon = icon
	b.payload = payload
	b.tooltip_fn = func():
		var lines := [[name, UITheme.TEXT]]
		if payload.type == "skill": lines = SkillsWindow.skill_tooltip(payload.id)
		lines.append(["키보드로 끌어다 놓기", UITheme.TEXT_DIM])
		return lines
	b.accept = func(d): return d is Dictionary and d.get("type") == "key"
	b.on_drop = func(d): _unbind(d.keycode)
	return b
