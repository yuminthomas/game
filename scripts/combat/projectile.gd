class_name Projectile
extends Node2D
## 투사체 (화살, 마력탄, 단검, 적 탄환). 관통·폭발·튕김·정지(멈춘 화살들)를 지원한다.

var team := "player"
var hit_maker: Callable          # func() -> HitInfo  (적중마다 새로 만든다)
var on_hit: Callable             # func(target, result, proj)
var velocity := Vector2.ZERO
var max_dist := 160.0
var travelled := 0.0
var radius := 3.0
var pierce := 0
var explode := 0.0               # 폭발 반경(px). 0이면 단일 대상
var bounce := 0
var visual := "arrow"
var color := Color.WHITE
var frozen := false              # 멈춘 화살들: 공중에 정지
var hit_list: Array = []
var trail: Array = []
var life_extra := 0.0
var guardable := true
var unblockable := false
var is_enemy := false

static func spawn(parent: Node, pos: Vector2, dir: Vector2, speed: float, dist: float, maker: Callable, opts := {}) -> Projectile:
	var p := Projectile.new()
	p.global_position = pos
	p.velocity = dir.normalized() * speed
	p.max_dist = dist
	p.hit_maker = maker
	for k in opts: p.set(k, opts[k])
	parent.add_child(p)
	return p

func _ready() -> void:
	z_index = 20
	is_enemy = team != "player"

func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta, not is_enemy)
	if dt <= 0: return
	if is_enemy and Clock.time_stopped: return
	if frozen:
		queue_redraw(); return
	var step := velocity * dt
	global_position += step
	travelled += step.length()
	trail.push_front(global_position)
	if trail.size() > 5: trail.pop_back()
	_check_hits()
	if travelled >= max_dist:
		if explode > 0: _explode()
		queue_free()
	queue_redraw()

func _check_hits() -> void:
	if is_enemy:
		var p: Node = Game.player
		if p and not p.dead and global_position.distance_to(p.global_position + p.hurt_offset()) <= radius + p.hurt_radius:
			_hit(p)
		return
	for t in Combat.targets_in(Combat.circle(global_position, radius), team):
		if t in hit_list: continue
		if explode > 0:
			_explode(); queue_free(); return
		_hit(t)
		if is_queued_for_deletion(): return

func _hit(t: Node) -> void:
	hit_list.append(t)
	var h: HitInfo = hit_maker.call()
	h.dir = velocity.normalized()
	h.projectile = true
	var r: Dictionary = _deliver(t, h)
	if on_hit.is_valid(): on_hit.call(t, r, self)
	if is_enemy:
		queue_free(); return
	if bounce > 0:
		bounce -= 1
		var nxt := Combat.nearest(global_position, 120, team, hit_list)
		if nxt:
			velocity = (nxt.global_position + nxt.hurt_offset() - global_position).normalized() * velocity.length()
			travelled = 0
			return
	if pierce > 0:
		pierce -= 1
	else:
		queue_free()

func _explode() -> void:
	Fx.ring(global_position, explode, color, 0.3, 2)
	Fx.burst(global_position, color, 10, 70, 0.35)
	Fx.glow(global_position, explode * 0.8, color, 0.2)
	for t in Combat.targets_in(Combat.circle(global_position, explode), team):
		var h: HitInfo = hit_maker.call()
		h.dir = (t.global_position - global_position).normalized()
		h.projectile = true
		var r: Dictionary = _deliver(t, h)
		if on_hit.is_valid(): on_hit.call(t, r, self)
	Fx.debug_shape(Combat.circle(global_position, explode), Color(1, 0.6, 0.2))

func _deliver(t: Node, h: HitInfo) -> Dictionary:
	if team == "player" and Game.player: return Game.player.deal(t, h)
	return t.take_hit(h)

## 멈춘 화살 발사
func release() -> void:
	frozen = false

func _draw() -> void:
	var d := velocity.normalized()
	if d == Vector2.ZERO: d = Vector2.RIGHT
	match visual:
		"arrow", "dagger":
			var c := color if visual == "arrow" else Color("d8dce6")
			draw_line(-d * 7, d * 2, Color("8a5a34") if visual == "arrow" else c, 1.0)
			draw_line(d * 1, d * 4, c, 2.0)
			if frozen: draw_circle(Vector2.ZERO, 3, Color(0.75, 0.95, 1, 0.4))
		"bolt", "frost", "fireball", "sun", "orb":
			var r := radius + (2.0 if visual in ["fireball", "sun"] else 0.0)
			for i in trail.size():
				var tc := color; tc.a = 0.35 * (1.0 - i / 5.0)
				draw_circle(trail[i] - global_position, r * (1.0 - i * 0.15), tc)
			draw_circle(Vector2.ZERO, r, color)
			draw_circle(Vector2.ZERO, r * 0.5, Color(1, 1, 1, 0.9))
		"enemy_bolt":
			draw_circle(Vector2.ZERO, radius + 1, Color(0.3, 0.1, 0.3))
			draw_circle(Vector2.ZERO, radius, color)
		"beam_star":
			draw_line(-d * 14, d * 6, color, 4.0)
			draw_line(-d * 14, d * 6, Color.WHITE, 1.5)
