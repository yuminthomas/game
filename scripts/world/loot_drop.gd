class_name LootDrop
extends Node2D
## 바닥에 떨어진 아이템 (GDD 9-7). 장비는 Space 로 줍고, 재료·모래는 가까이 가면 끌려온다.
## 등급색으로 빛나고 희귀 이상은 빛기둥이 솟는다.

var item := {}          # 장비 인스턴스
var stack_id := ""      # 재료/소모품
var count := 1
var book_key := ""
var t := 0.0
var attract := false

static func spawn_item(pos: Vector2, it: Dictionary) -> LootDrop:
	var d := LootDrop.new(); d.item = it
	d._place(pos); return d

static func spawn_stack(pos: Vector2, id: String, n: int) -> LootDrop:
	var d := LootDrop.new(); d.stack_id = id; d.count = n
	d._place(pos); return d

static func spawn_book(pos: Vector2, key: String) -> LootDrop:
	var d := LootDrop.new(); d.book_key = key
	d._place(pos); return d

func _place(pos: Vector2) -> void:
	global_position = pos + Vector2(randf_range(-10, 10), randf_range(-8, 8))
	add_to_group("loot")
	Game.world.entities.add_child(self)
	if not item.is_empty():
		var g: String = Data.grades[item.grade].drop_fx
		if g in ["pillar_sound", "pillar_screen"]: Fx.shake(2.0 if g == "pillar_sound" else 4.0)
		if g == "pillar_screen": Fx.glow(global_position, 120, Data.grade_color(item.grade), 0.6)

## 테스트 몬스터 드롭 (GDD 9-7 기본 드롭률. 실제 드롭표는 3단계에서 몬스터별로)
static func roll_drops(e: Node) -> void:
	var pos: Vector2 = e.global_position
	if e.def.get("infinite", false): return
	spawn_stack(pos, "time_sand", randi_range(2, 6) * maxi(1, e.level))
	var elite: bool = e.rank != "normal"
	if randf() < (0.4 if elite else 0.04):
		var pool := Data.weapons.values().filter(func(w): return w.grade in ["common", "rare"] and int(w.level) <= 10)
		if not pool.is_empty(): spawn_item(pos, Items.make_weapon(pool[randi() % pool.size()].id))
	if randf() < (0.15 if elite else 0.008):
		spawn_book(pos, "old:" + Data.CLASSES[randi() % 6])
	if randf() < 0.6:
		spawn_stack(pos, ["slime_goo", "wolf_hide", "firefly_dust", "moss_chunk"][randi() % 4], 1)

func needs_interact() -> bool:
	return not item.is_empty() or book_key != ""

func pickup(p: Node) -> void:
	var pd: PlayerData = Game.data
	if not item.is_empty():
		if not pd.add_item(item): return
	elif book_key != "":
		pd.add_book(book_key.split(":")[0], book_key.split(":")[1])
	else:
		pd.add_stack(stack_id, count)
	Fx.burst(global_position, _color(), 8, 40, 0.4)
	queue_free()

func _color() -> Color:
	if not item.is_empty(): return Data.grade_color(item.grade)
	if book_key != "": return Color(0.95, 0.85, 0.5)
	return Color(0.95, 0.9, 0.7)

func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta, true)
	t += dt
	var pl: Node2D = Game.player
	if pl and not needs_interact():
		var d := global_position.distance_to(pl.global_position)
		if d < 40: attract = true
		if attract:
			global_position = global_position.move_toward(pl.global_position, (120 + t * 60) * dt)
			if d < 6: pickup(pl)
	queue_redraw()

func _draw() -> void:
	var c := _color()
	var bob := sin(t * 4.0) * 1.5
	if not item.is_empty():
		var fx: String = Data.grades[item.grade].drop_fx
		if fx.begins_with("pillar"):
			var h := 70.0
			for i in 6:
				var a := 0.18 * (1.0 - i / 6.0)
				draw_rect(Rect2(-3 + i * 0.5, -h, 6 - i, h), Color(c.r, c.g, c.b, a))
		draw_circle(Vector2(0, -2), 9, Color(c.r, c.g, c.b, 0.18 + 0.08 * sin(t * 5)))
		var tex := SpriteFactory.item_icon(item.id)
		draw_texture(tex, Vector2(-8, -14 + bob))
	elif book_key != "":
		draw_circle(Vector2(0, -2), 7, Color(c.r, c.g, c.b, 0.2))
		draw_texture(SpriteFactory.book_icon(book_key), Vector2(-8, -14 + bob))
	else:
		draw_circle(Vector2(0, -3 + bob), 2.5, c)
		draw_circle(Vector2(0, -3 + bob), 1.2, Color.WHITE)
	if needs_interact() and Game.player and Game.player.global_position.distance_to(global_position) < 22:
		draw_string(load("res://assets/fonts/Galmuri9.ttf"), Vector2(-14, -22), "[%s]" % InputManager.key_label(InputManager.key_for("interact")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.9))
