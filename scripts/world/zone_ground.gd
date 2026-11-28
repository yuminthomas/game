class_name ZoneGround
extends Node2D
## 바닥 타일 그리기 (한 번 그려서 캐시). 튜토리얼처럼 바닥에 키 아이콘만 그린다 (GDD 10-4: 글 없음).

var zone: TestZone

func _ready() -> void:
	z_index = -20
	InputManager.bindings_changed.connect(queue_redraw)

func _draw() -> void:
	for x in zone.W:
		for y in zone.H:
			var c := Vector2i(x, y)
			var kind := "grass"
			var h := absi(hash(c)) % 13
			if zone.is_stone(c): kind = "stone"
			elif h == 0: kind = "flowers"
			draw_texture(SpriteFactory.tile_texture(kind, h % 4 if kind != "stone" else 0), Vector2(x, y) * zone.T)
	# 바닥의 키 아이콘 (이동·공격·대시·패링)
	var font: Font = load("res://assets/fonts/Galmuri9.ttf")
	var base := Vector2(17, 21) * zone.T
	var keys := [["move", "←↑↓→"], ["attack", InputManager.key_label(InputManager.key_for("attack"))],
		["dash", InputManager.key_label(InputManager.key_for("dash"))], ["parry", InputManager.key_label(InputManager.key_for("parry"))]]
	for i in keys.size():
		var p: Vector2 = base + Vector2(i * 44, 0)
		draw_rect(Rect2(p, Vector2(36, 18)), Color(0.1, 0.1, 0.15, 0.35))
		draw_rect(Rect2(p, Vector2(36, 18)), Color(0.9, 0.85, 0.6, 0.5), false, 1)
		if keys[i][0] != "move":
			draw_texture(SpriteFactory.action_icon(keys[i][0]), p + Vector2(2, 1))
			draw_string(font, p + Vector2(20, 13), keys[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
		else:
			draw_string(font, p + Vector2(3, 13), keys[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
