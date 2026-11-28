class_name Zone
extends Node2D
## 시간 차를 두고 피해를 주는 장판·오라 (화살비, 유성, 블랙홀, 덫, 독 장판, 감속장, 칼날 폭풍 등).

var team := "player"
var radius := 24.0
var duration := 1.0
var delay := 0.0                  # 첫 피해 전 대기 (유성)
var hits := 1                     # 지속 시간 동안 피해 횟수
var hit_maker: Callable           # func(target) -> HitInfo
var on_hit: Callable              # func(target, result)
var on_end: Callable              # func(zone)
var follow: Node2D = null
var pull := 0.0                   # 끌어당기기 세기 (칸/초)
var visual := "circle"
var color := Color(1, 1, 1, 0.5)
var trap := false                 # 밟으면 1회 발동
var apply_status := ""            # 매 틱 상태이상 부여 (감속장)
var status_opts := {}
var status_opts_boss := {}
var light := false
var count := 0                    # 오라 장식 개수 (칼날, 창)

var t := 0.0
var tick_t := 0.0
var done_hits := 0
var _spin := 0.0

func _ready() -> void:
	z_index = -5 if visual in ["circle", "pool", "slow", "trap", "light", "crack"] else 15

func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta, team == "player")
	if dt <= 0: return
	t += dt
	_spin += dt * 6.0
	if follow and is_instance_valid(follow): global_position = follow.global_position
	if t < delay:
		queue_redraw(); return
	if trap:
		var victims := Combat.targets_in(Combat.circle(global_position, radius), team)
		if not victims.is_empty():
			for v in victims: _hit(v)
			Fx.ring(global_position, radius * 1.5, color, 0.3)
			queue_free(); return
	elif hits > 0:
		var interval := (duration / hits) if duration > 0 else 0.0
		tick_t += dt
		while done_hits < hits and tick_t >= interval:
			tick_t -= interval
			done_hits += 1
			for v in Combat.targets_in(Combat.circle(global_position, radius), team): _hit(v)
			Fx.debug_shape(Combat.circle(global_position, radius), Color(1, 0.5, 0.2))
			_tick_fx()
			if interval <= 0.0:
				done_hits = hits
				break
	if apply_status != "":
		for v in Combat.targets_in(Combat.circle(global_position, radius), team):
			var o: Dictionary = status_opts_boss if v.is_boss() and not status_opts_boss.is_empty() else status_opts
			v.statuses.add(apply_status, 0.3, 0.0, o.duplicate())
	if pull > 0:
		for v in Combat.targets_in(Combat.circle(global_position, radius * 1.4), team):
			if v.superarmor <= 0 and not v.is_boss():
				var to: Vector2 = global_position - v.global_position
				if to.length() > 4: v.move_and_collide(to.normalized() * pull * 16.0 * dt)
	if t >= delay + duration and (done_hits >= hits or hits <= 0):
		if on_end.is_valid(): on_end.call(self)
		queue_free()
	queue_redraw()

func _hit(v: Node) -> void:
	if not hit_maker.is_valid(): return
	var h: HitInfo = hit_maker.call(v)
	if h == null: return
	h.dir = (v.global_position - global_position).normalized()
	var r: Dictionary = Game.player.deal(v, h) if team == "player" and Game.player else v.take_hit(h)
	if on_hit.is_valid(): on_hit.call(v, r)

func _tick_fx() -> void:
	match visual:
		"arrows":
			for i in 3: Fx.line(global_position + Vector2(randf_range(-radius, radius), randf_range(-radius, radius) - 30), global_position + Vector2(randf_range(-radius, radius), randf_range(-radius, radius)), Color(0.9, 0.85, 0.7), 1.5, 0.12)
		"meteor", "star":
			Fx.ring(global_position, radius, color, 0.4, 3); Fx.burst(global_position, color, 20, 120, 0.5); Fx.shake(3.0); Fx.glow(global_position, radius, color, 0.3)
		"blades", "spears", "sun":
			Fx.swoosh(global_position + Vector2(0, -6), radius * 0.8, _spin, _spin + 2.0, color, 2, 0.12)
		_:
			Fx.burst(global_position, color, 4, 30, 0.3)

func _draw() -> void:
	var a := clampf(1.0 - (t - delay - duration + 0.3) / 0.3, 0, 1) if t > delay + duration - 0.3 else 1.0
	var c := color; c.a *= a
	match visual:
		"meteor", "star":
			if t < delay:
				var k := t / maxf(delay, 0.01)
				draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(1, 0.3, 0.2, 0.8), 1.5)
				draw_circle(Vector2.ZERO, radius * k, Color(1, 0.3, 0.2, 0.2))
				var fall := Vector2(-30, -120) * (1.0 - k)
				draw_circle(fall, 5 if visual == "meteor" else 3, c)
		"blackhole":
			draw_circle(Vector2.ZERO, radius, Color(0.2, 0.05, 0.3, 0.35 * a))
			draw_circle(Vector2.ZERO, 6, Color(0, 0, 0, a))
			draw_arc(Vector2.ZERO, 8, _spin, _spin + 4, 12, Color(0.7, 0.4, 1, a), 2)
		"blades", "spears":
			for i in count:
				var ang := _spin + TAU * i / maxf(count, 1)
				var p := Vector2.from_angle(ang) * radius * 0.8 + Vector2(0, -6)
				draw_line(p, p + Vector2.from_angle(ang + PI / 2) * 8, Color(0.85, 0.95, 1, 0.8 * a), 2)
		"sun":
			draw_circle(Vector2(0, -20), 7, Color(1, 0.7, 0.2, a)); draw_circle(Vector2(0, -20), 4, Color(1, 1, 0.8, a))
			draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(1, 0.6, 0.2, 0.4 * a), 1)
		"trap":
			draw_arc(Vector2.ZERO, radius, 0, TAU, 16, Color(0.9, 0.8, 0.4, 0.8), 1)
			draw_line(Vector2(-3, -3), Vector2(3, 3), Color(0.9, 0.8, 0.4)); draw_line(Vector2(3, -3), Vector2(-3, 3), Color(0.9, 0.8, 0.4))
		"slow":
			draw_circle(Vector2.ZERO, radius, Color(0.6, 0.85, 1, 0.12 * a))
			draw_arc(Vector2.ZERO, radius, _spin * 0.2, _spin * 0.2 + TAU, 48, Color(0.75, 0.95, 1, 0.5 * a), 1)
		"crack":
			draw_circle(Vector2.ZERO, radius, Color(1, 0.4, 0.1, 0.25 * a))
		_:
			draw_circle(Vector2.ZERO, radius, Color(c.r, c.g, c.b, 0.18 * c.a))
			draw_arc(Vector2.ZERO, radius, 0, TAU, 32, c, 1)
