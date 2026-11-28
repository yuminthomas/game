class_name SkillbookPicker
extends Control
## 스킬서 선택 화면 (GDD 8-1, 12-3): 화면 중앙에 카드 3장이 뒤집히며 등장. 고르지 않은 카드는 사라진다.

var ui: UIRoot
var cards: Array = []
var offers: Array = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(list: Array) -> void:
	offers = list
	for c in cards: c.queue_free()
	cards.clear()
	visible = true
	move_to_front()
	get_tree().paused = true
	var n := offers.size()
	var w := 120.0
	var gap := 12.0
	var x0 := 320 - (n * w + (n - 1) * gap) / 2
	for i in n:
		var card := _card(offers[i], i)
		card.position = Vector2(x0 + i * (w + gap), 90)
		card.size = Vector2(w, 170)
		card.pivot_offset = Vector2(w / 2, 85)
		card.scale = Vector2(0, 1)
		add_child(card)
		cards.append(card)
		var tw := card.create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(card, "scale", Vector2(1, 1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _card(o: Dictionary, i: int) -> PanelContainer:
	var s: Dictionary = Data.skills[o.id]
	var tier: Dictionary = Data.skill_tiers[s.tier]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.07, 0.08, 0.16, 0.97), Color(tier.color), 2, 6))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var top := UITheme.label("%d" % (i + 1), 10, UITheme.TEXT_DIM)
	v.add_child(top)
	var icon := TextureRect.new()
	icon.texture = SpriteFactory.skill_icon(o.id)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(icon)
	var name := UITheme.label(s.name, 12, Color.WHITE)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var t := UITheme.label("%s · %s" % [Data.class_name_ko(s.cls), tier.name], 9, Color(tier.color))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var badge := UITheme.label("신규" if o.from == 0 else "Lv%d → Lv%d" % [o.from, o.to], 11, UITheme.GREEN if o.from == 0 else UITheme.CRYSTAL)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(badge)
	var d := UITheme.label(s.desc, 9, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 106
	v.add_child(d)
	var info := UITheme.label("기력 %d · 쿨 %ds" % [s.stamina, s.cooldown], 9, UITheme.TEXT_DIM)
	v.add_child(info)
	p.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: choose(i))
	p.mouse_entered.connect(func(): p.modulate = Color(1.15, 1.15, 1.15))
	p.mouse_exited.connect(func(): p.modulate = Color.WHITE)
	return p

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed: return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_3 and k - KEY_1 < offers.size():
		choose(k - KEY_1)
		get_viewport().set_input_as_handled()

func choose(i: int) -> void:
	if not visible: return
	var o: Dictionary = offers[i]
	var lv := Game.data.learn_skill(o.id)
	ui.show_notice("%s %s" % [Data.skills[o.id].name, "습득!" if lv == 1 else "Lv%d" % lv], UITheme.CRYSTAL)
	for j in cards.size():
		var c: Control = cards[j]
		var tw := c.create_tween()
		if j == i:
			tw.tween_property(c, "scale", Vector2(1.1, 1.1), 0.12)
			tw.tween_property(c, "modulate:a", 0.0, 0.25)
		else:
			tw.tween_property(c, "modulate:a", 0.0, 0.18)
	offers = []
	await get_tree().create_timer(0.4, true, false, true).timeout
	visible = false
	get_tree().paused = false
