class_name GameWindow
extends PanelContainer
## 드래그로 옮길 수 있고 위치를 기억하는 창 (메이플식, GDD 12-1). 열고 닫을 때 페이드 + 살짝 커짐.

var window_id := ""
var title_label: Label
var body: VBoxContainer
var _dragging := false
var _drag_off := Vector2.ZERO
var default_pos := Vector2(40, 40)
var ui: UIRoot

func _init(id: String, title: String, pos := Vector2(40, 40)) -> void:
	window_id = id
	default_pos = pos
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	add_child(v)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(bar)
	title_label = UITheme.label(title, 12, UITheme.GOLD.lightened(0.3))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(title_label)
	var close := UITheme.button("×", close_window, 11)
	close.custom_minimum_size = Vector2(14, 14)
	bar.add_child(close)
	var sep := ColorRect.new()
	sep.color = UITheme.GOLD_DIM
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	v.add_child(body)
	visible = false

func _ready() -> void:
	position = Settings.window_pos(window_id, default_pos)
	_clamp()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			move_to_front()
			if event.position.y < 18:
				_dragging = true
				_drag_off = event.position
				accept_event()
		elif _dragging:
			_dragging = false
			Settings.set_window_pos(window_id, position)
	elif event is InputEventMouseMotion and _dragging:
		position = (get_global_mouse_position() - _drag_off).round()
		_clamp()
		accept_event()

func _clamp() -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(640, 360)
	position.x = clampf(position.x, 0, maxf(0, vp.x - size.x))
	position.y = clampf(position.y, 0, maxf(0, vp.y - 20))

func toggle() -> void:
	if visible: close_window()
	else: open_window()

func open_window() -> void:
	if visible: return
	visible = true
	move_to_front()
	refresh()
	pivot_offset = size / 2
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.12)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)
	_clamp.call_deferred()

func close_window() -> void:
	if not visible: return
	if ui: ui.hide_tooltip()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.08)
	tw.tween_callback(func(): visible = false)

func refresh() -> void:
	pass
