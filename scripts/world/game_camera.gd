class_name GameCamera
extends Camera2D
## 부드러운 추적, 구역 경계에서 멈춤, 화면 흔들림 (GDD 12-8).

var target: Node2D
var limit_rect := Rect2()

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	limit_left = int(limit_rect.position.x); limit_top = int(limit_rect.position.y)
	limit_right = int(limit_rect.end.x); limit_bottom = int(limit_rect.end.y)
	if target: global_position = target.global_position
	reset_smoothing()

func _process(_delta: float) -> void:
	if target and is_instance_valid(target):
		global_position = target.global_position + Vector2(0, -8)
	var s := Fx.shake_strength
	offset = Vector2(randf_range(-s, s), randf_range(-s, s)).round() if s > 0.2 else Vector2.ZERO
