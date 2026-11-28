class_name PauseMenu
extends Control
## 일시정지 메뉴 (Esc): 계속 / 설정 / 키 설정 / 처음부터. 싱글에서는 게임이 멈춘다.

var ui: UIRoot
var main_box: VBoxContainer
var settings_box: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(220, 70)
	panel.custom_minimum_size = Vector2(200, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var title := UITheme.label("일시정지", 14, UITheme.GOLD.lightened(0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 3)
	v.add_child(main_box)
	main_box.add_child(UITheme.button("계속", close, 12))
	main_box.add_child(UITheme.button("설정", func(): main_box.visible = false; settings_box.visible = true, 12))
	main_box.add_child(UITheme.button("키 설정", func(): close(); ui.window("keyconfig").open_window(), 12))
	main_box.add_child(UITheme.button("처음부터 (타이틀 화면은 이후 단계)", _restart, 11))
	settings_box = VBoxContainer.new()
	settings_box.visible = false
	settings_box.add_theme_constant_override("separation", 3)
	v.add_child(settings_box)
	_slider("화면 흔들림", "gameplay", "shake", 0.0, 2.0, 0.1)
	_slider("HUD 크기", "gameplay", "hud_scale", 0.8, 1.2, 0.05)
	_slider("선입력 허용 시간(초)", "control", "input_buffer", 0.0, 0.3, 0.01)
	_slider("파티클 양", "graphics", "particles", 0.3, 1.0, 0.1, 1.0)
	_check("데미지 숫자 표시", "gameplay", "damage_numbers")
	_check("조준 보정", "gameplay", "aim_assist")
	_check("HUD 자동 흐려짐 (탐험 중)", "gameplay", "hud_fade")
	_check("히트박스 표시 (디버그)", "debug", "hitboxes")
	settings_box.add_child(UITheme.button("뒤로", func(): settings_box.visible = false; main_box.visible = true, 11))

func _slider(label: String, sec: String, key: String, lo: float, hi: float, step: float, default = null) -> void:
	var row := HBoxContainer.new()
	var l := UITheme.label(label, 10)
	l.custom_minimum_size.x = 100
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = step
	s.custom_minimum_size = Vector2(70, 12)
	s.focus_mode = Control.FOCUS_NONE
	s.value = float(Settings.get_value(sec, key, default))
	var val := UITheme.label("%.2f" % s.value, 10, UITheme.CRYSTAL)
	s.value_changed.connect(func(v): Settings.set_value(sec, key, v); val.text = "%.2f" % v)
	row.add_child(s)
	row.add_child(val)
	settings_box.add_child(row)

func _check(label: String, sec: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Settings.get_value(sec, key))
	c.toggled.connect(func(on): Settings.set_value(sec, key, on))
	settings_box.add_child(c)

func open() -> void:
	visible = true
	move_to_front()
	main_box.visible = true; settings_box.visible = false
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

func _restart() -> void:
	get_tree().paused = false
	Game.new_game()
	Clock.reset()
	get_tree().reload_current_scene()
