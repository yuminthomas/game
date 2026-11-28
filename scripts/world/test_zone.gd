class_name TestZone
extends Node2D
## 1단계 테스트 구역: 자연물로 막힌 풀밭, 돌바닥 수련장, 허수아비 2개, 공격해 오는 테스트 몬스터.

const W := 60
const H := 40
const T := 16

var entities: Node2D
var camera: GameCamera
var player: Player
var zone_name := "수련의 풀밭 (테스트 구역)"
var solid := {}     # Vector2i -> true

func _ready() -> void:
	Game.world = self
	var ground := ZoneGround.new()
	ground.zone = self
	add_child(ground)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	var fx := FxLayer.new()
	add_child(fx)
	_build_borders()
	_spawn_player()
	_spawn_enemies()
	camera = GameCamera.new()
	camera.target = player
	camera.limit_rect = Rect2(0, 0, W * T, H * T)
	add_child(camera)
	camera.make_current()
	Game.world_ready.emit()

func _build_borders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# 가장자리 나무 띠 (두께가 들쭉날쭉한 자연스러운 경계)
	for x in W:
		for y in H:
			var edge := mini(mini(x, W - 1 - x), mini(y, H - 1 - y))
			var thick := 2 + int(1.5 + 1.5 * sin(x * 0.45) * cos(y * 0.37))
			if edge < thick: solid[Vector2i(x, y)] = true
	# 안쪽 장애물: 나무 무리와 바위
	for c in [Vector2i(40, 8), Vector2i(41, 8), Vector2i(40, 9), Vector2i(12, 30), Vector2i(13, 30), Vector2i(48, 28), Vector2i(49, 29), Vector2i(30, 33)]:
		solid[c] = true
	var rocks := [Vector2i(34, 14), Vector2i(35, 14), Vector2i(44, 20), Vector2i(26, 26), Vector2i(52, 12)]
	for c in rocks: solid[c] = true
	# 충돌체
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	add_child(body)
	for c in solid:
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new(); r.size = Vector2(T, T)
		cs.shape = r
		cs.position = Vector2(c.x * T + T / 2.0, c.y * T + T / 2.0)
		body.add_child(cs)
	# 그림: 바깥에서 보이는 나무만 스프라이트로 (y 정렬)
	for c in solid:
		var is_rock: bool = c in rocks
		var neighbor_open := false
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(0, 2)]:
			if not solid.has(c + o) and (c + o).x >= 0 and (c + o).y >= 0 and (c + o).x < W and (c + o).y < H: neighbor_open = true
		if not neighbor_open and (c.x + c.y) % 2 == 1: continue
		var s := Sprite2D.new()
		s.texture = SpriteFactory.tile_texture("rock" if is_rock else "tree")
		s.centered = false
		s.offset = Vector2(-8, -16) if is_rock else Vector2(-16, -38)
		s.position = Vector2(c.x * T + 8, c.y * T + 15)
		entities.add_child(s)

func _spawn_player() -> void:
	player = Player.new()
	player.global_position = Vector2(14 * T, 18 * T)
	entities.add_child(player)
	player.spawn_point = player.global_position

func _spawn_enemies() -> void:
	spawn_enemy("dummy", Vector2(20 * T, 14 * T), 1)
	spawn_enemy("dummy", Vector2(24 * T, 14 * T), 10)
	spawn_enemy("test_brute", Vector2(38 * T, 20 * T), 1)
	spawn_enemy("test_brute", Vector2(44 * T, 25 * T), 1)

func spawn_enemy(kind: String, pos: Vector2, lv := -1, rank := "") -> Enemy:
	var e := Enemy.create(kind, lv, rank)
	e.global_position = pos
	entities.add_child(e)
	e.spawn_pos = pos
	return e

func is_solid(cell: Vector2i) -> bool:
	return solid.has(cell)

func is_stone(cell: Vector2i) -> bool:
	return cell.x >= 16 and cell.x <= 28 and cell.y >= 10 and cell.y <= 20
