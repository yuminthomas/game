class_name SlotBox
extends Control
## 아이콘 칸 하나 (인벤토리, 장비, 스킬, 퀵슬롯, 키보드 키). 드래그·드롭·클릭·툴팁을 콜백으로 연결한다.

var icon: Texture2D
var border := UITheme.GOLD_DIM
var count_text := ""
var key_text := ""
var corner_text := ""
var dim := false
var silhouette := false
var cooldown := 0.0          # 0~1 남은 비율
var is_new := false
var locked := false
var highlight := false
var empty_hint := ""
var payload = null           # 드래그 시 넘길 데이터 (null 이면 드래그 불가)
var accept: Callable         # func(data) -> bool
var on_drop: Callable        # func(data)
var on_click: Callable       # func(button_index, double_click)
var tooltip_fn: Callable     # func() -> Array (줄 목록)
var ui: UIRoot

func _init(sz := Vector2(20, 20)) -> void:
	custom_minimum_size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	mouse_entered.connect(_hover_in)
	mouse_exited.connect(func(): if ui: ui.hide_tooltip())

func _hover_in() -> void:
	if is_new:
		is_new = false
		if payload is Dictionary and payload.get("item") is Dictionary: payload.item.new = false
		queue_redraw()
	if ui and tooltip_fn.is_valid():
		var lines: Array = tooltip_fn.call()
		if not lines.is_empty(): ui.show_tooltip(lines)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and on_click.is_valid():
		on_click.call(event.button_index, event.double_click)
		accept_event()

func _get_drag_data(_pos: Vector2):
	if payload == null: return null
	var prev := TextureRect.new()
	prev.texture = icon
	prev.modulate.a = 0.8
	prev.position = -size / 2
	var holder := Control.new()
	holder.add_child(prev)
	set_drag_preview(holder)
	if ui: ui.hide_tooltip()
	return payload

func _can_drop_data(_pos: Vector2, data) -> bool:
	return accept.is_valid() and accept.call(data)

func _drop_data(_pos: Vector2, data) -> void:
	if on_drop.is_valid(): on_drop.call(data)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.03, 0.04, 0.08, 0.85))
	if icon:
		var isz := icon.get_size()
		var p := ((size - isz) / 2).floor()
		var col := Color.WHITE
		if silhouette: col = Color(0.12, 0.12, 0.16)
		elif dim: col = Color(0.45, 0.45, 0.5)
		draw_texture(icon, p, col)
	elif empty_hint != "":
		draw_string(UITheme.font_small, Vector2(2, size.y / 2 + 4), empty_hint, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 9, Color(1, 1, 1, 0.25))
	if cooldown > 0.0:
		draw_rect(Rect2(0, 0, size.x, size.y * cooldown), Color(0, 0, 0, 0.6))
	draw_rect(r, UITheme.CRYSTAL if highlight else border, false, 1)
	UITheme.fonts()
	if count_text != "":
		var w := UITheme.font_small.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string_outline(UITheme.font_small, Vector2(size.x - w - 1, size.y - 2), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color.BLACK)
		draw_string(UITheme.font_small, Vector2(size.x - w - 1, size.y - 2), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
	if key_text != "":
		draw_string_outline(UITheme.font_small, Vector2(1, 8), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color.BLACK)
		draw_string(UITheme.font_small, Vector2(1, 8), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.GOLD.lightened(0.4))
	if corner_text != "":
		draw_string_outline(UITheme.font_small, Vector2(1, size.y - 2), corner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 2, Color.BLACK)
		draw_string(UITheme.font_small, Vector2(1, size.y - 2), corner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.CRYSTAL)
	if is_new: draw_rect(Rect2(size.x - 4, 1, 3, 3), Color(1, 0.85, 0.2))
	if locked:
		draw_rect(Rect2(1, 1, 5, 4), Color(0.9, 0.8, 0.4)); draw_rect(Rect2(2, -1, 3, 2), Color(0.9, 0.8, 0.4), false, 1)
