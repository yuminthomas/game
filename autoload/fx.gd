extends Node
## 타격감 연출 창구: 히트스톱, 화면 흔들림, 데미지 숫자, 파티클, 궤적, 디버그 히트박스. GDD 5-6.
## 실제 그리기는 월드에 붙은 FxLayer 가 한다.

var layer: FxLayer
var shake_strength := 0.0

func _physics_process(delta: float) -> void:
	shake_strength = move_toward(shake_strength, 0.0, float(Data.bal("shake.decay", 12.0)) * delta)

func hitstop(kind: String) -> void:
	Clock.hitstop(int(Data.bal("hitstop_frames." + kind, 3)))

func shake(kind_or_amount) -> void:
	var a: float = float(kind_or_amount) if (kind_or_amount is float or kind_or_amount is int) else float(Data.bal("shake." + str(kind_or_amount), 2.0))
	a *= float(Settings.get_value("gameplay", "shake", 1.0))
	shake_strength = maxf(shake_strength, a)

func number(pos: Vector2, value: float, kind := "normal") -> void:
	if layer == null: return
	if kind != "taken" and not Settings.get_value("gameplay", "damage_numbers", true): return
	layer.add_number(pos, str(int(round(value))), kind)

func text(pos: Vector2, s: String, color := Color.WHITE) -> void:
	if layer: layer.add_text(pos, s, color)

func burst(pos: Vector2, color: Color, count := 8, speed := 60.0, life := 0.4, size := 1.0) -> void:
	if layer: layer.add_burst(pos, color, count, speed, life, size)

func sparks(pos: Vector2, dir: Vector2, color := Color(1, 0.9, 0.5)) -> void:
	if layer: layer.add_sparks(pos, dir, color)

func swoosh(center: Vector2, radius: float, from_angle: float, to_angle: float, color: Color, width := 3.0, life := 0.16) -> void:
	if layer: layer.add_arc(center, radius, from_angle, to_angle, color, width, life)

func ring(center: Vector2, radius: float, color: Color, life := 0.3, width := 2.0) -> void:
	if layer: layer.add_ring(center, radius, color, life, width)

func line(a: Vector2, b: Vector2, color: Color, width := 3.0, life := 0.2) -> void:
	if layer: layer.add_line(a, b, color, width, life)

func glow(pos: Vector2, radius: float, color: Color, life := 0.2) -> void:
	if layer: layer.add_glow(pos, radius, color, life)

## 디버그 히트박스 표시 (Settings debug/hitboxes)
func debug_shape(shape: Dictionary, color: Color) -> void:
	if layer and Settings.get_value("debug", "hitboxes", false): layer.add_debug(shape, color)
