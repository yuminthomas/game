class_name FxLayer
extends Node2D
## 월드 위에 그려지는 가벼운 연출 묶음 (파티클, 궤적, 링, 숫자). 노드를 만들지 않고 배열로 관리해 가볍다.

const MAX_PARTICLES := 600
var particles: Array = []   # [pos, vel, life, max_life, color, size]
var arcs: Array = []
var rings: Array = []
var lines: Array = []
var glows: Array = []
var numbers: Array = []
var debug: Array = []
var font: Font
var font_small: Font

func _ready() -> void:
	z_index = 50
	font = load("res://assets/fonts/Galmuri11.ttf")
	font_small = load("res://assets/fonts/Galmuri9.ttf")
	Fx.layer = self

func _exit_tree() -> void:
	if Fx.layer == self: Fx.layer = null

func add_number(pos: Vector2, s: String, kind: String) -> void:
	var col := Color.WHITE
	var size := 11
	match kind:
		"crit": col = Color(1, 0.86, 0.2); size = 16
		"taken": col = Color(1, 0.3, 0.3)
		"heal": col = Color(0.4, 1, 0.5)
		"dot": col = Color(0.85, 0.75, 1.0); size = 10
		"block": col = Color(0.6, 0.8, 1.0)
	numbers.append({"pos": pos + Vector2(randf_range(-4, 4), -10), "s": s, "col": col, "size": size, "life": 0.75, "max": 0.75, "vy": -40.0})

func add_text(pos: Vector2, s: String, col: Color) -> void:
	numbers.append({"pos": pos + Vector2(0, -14), "s": s, "col": col, "size": 11, "life": 0.9, "max": 0.9, "vy": -22.0})

func add_burst(pos: Vector2, col: Color, count: int, speed: float, life: float, size: float) -> void:
	var q: float = float(Settings.get_value("graphics", "particles", 1.0))
	count = int(ceil(count * q))
	for i in count:
		if particles.size() >= MAX_PARTICLES: particles.pop_front()
		var a := randf() * TAU
		var v := Vector2.from_angle(a) * speed * randf_range(0.3, 1.0)
		var l := life * randf_range(0.6, 1.0)
		particles.append([pos, v, l, l, col, size])

func add_sparks(pos: Vector2, dir: Vector2, col: Color) -> void:
	for i in 7:
		if particles.size() >= MAX_PARTICLES: particles.pop_front()
		var a := dir.angle() + randf_range(-0.9, 0.9)
		var v := Vector2.from_angle(a) * randf_range(60, 160)
		particles.append([pos, v, 0.22, 0.22, col, 1.0])

func add_arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float, life: float) -> void:
	arcs.append({"c": c, "r": r, "a0": a0, "a1": a1, "col": col, "w": w, "life": life, "max": life})

func add_ring(c: Vector2, r: float, col: Color, life: float, w: float) -> void:
	rings.append({"c": c, "r": r, "col": col, "life": life, "max": life, "w": w})

func add_line(a: Vector2, b: Vector2, col: Color, w: float, life: float) -> void:
	lines.append({"a": a, "b": b, "col": col, "w": w, "life": life, "max": life})

func add_glow(p: Vector2, r: float, col: Color, life: float) -> void:
	glows.append({"p": p, "r": r, "col": col, "life": life, "max": life})

func add_debug(shape: Dictionary, col: Color) -> void:
	debug.append({"shape": shape, "col": col, "life": 0.1})

func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta, true)
	if dt <= 0.0:
		queue_redraw(); return
	for p in particles:
		p[0] += p[1] * dt
		p[1] *= 0.92
		p[2] -= dt
	particles = particles.filter(func(p): return p[2] > 0)
	for arr in [arcs, rings, lines, glows, numbers, debug]:
		for e in arr: e.life -= dt
	for n in numbers:
		n.pos.y += n.vy * dt
		n.vy *= 0.9
	arcs = arcs.filter(func(e): return e.life > 0)
	rings = rings.filter(func(e): return e.life > 0)
	lines = lines.filter(func(e): return e.life > 0)
	glows = glows.filter(func(e): return e.life > 0)
	numbers = numbers.filter(func(e): return e.life > 0)
	debug = debug.filter(func(e): return e.life > 0)
	queue_redraw()

func _draw() -> void:
	for g in glows:
		var t: float = g.life / g.max
		var c: Color = g.col; c.a *= t * 0.5
		draw_circle(g.p, g.r, c)
		c.a *= 1.5
		draw_circle(g.p, g.r * 0.5, c)
	for a in arcs:
		var t: float = a.life / a.max
		var c: Color = a.col; c.a *= t
		draw_arc(a.c, a.r, a.a0, a.a1, 12, c, a.w * (0.5 + t * 0.5))
		var c2 := Color(1, 1, 1, c.a * 0.8)
		draw_arc(a.c, a.r, lerp(a.a0, a.a1, 0.5), a.a1, 8, c2, 1.0)
	for r in rings:
		var t: float = 1.0 - r.life / r.max
		var c: Color = r.col; c.a *= 1.0 - t
		draw_arc(r.c, r.r * (0.4 + 0.6 * t), 0, TAU, 32, c, r.w)
	for l in lines:
		var t: float = l.life / l.max
		var c: Color = l.col; c.a *= t
		draw_line(l.a, l.b, c, l.w * t + 1)
		draw_line(l.a, l.b, Color(1, 1, 1, c.a), maxf(1.0, l.w * 0.3 * t))
	for p in particles:
		var c: Color = p[4]; c.a *= clampf(p[2] / p[3] * 1.5, 0, 1)
		var s: float = p[5]
		draw_rect(Rect2(p[0].round(), Vector2(s, s)), c)
	for d in debug:
		_draw_shape(d.shape, d.col)
	for n in numbers:
		var t: float = n.life / n.max
		var c: Color = n.col; c.a = clampf(t * 2.0, 0, 1)
		var f := font if n.size >= 11 else font_small
		var w := f.get_string_size(n.s, HORIZONTAL_ALIGNMENT_LEFT, -1, n.size).x
		var p: Vector2 = (n.pos - Vector2(w / 2, 0)).round()
		draw_string_outline(f, p, n.s, HORIZONTAL_ALIGNMENT_LEFT, -1, n.size, 3, Color(0, 0, 0, c.a))
		draw_string(f, p, n.s, HORIZONTAL_ALIGNMENT_LEFT, -1, n.size, c)

func _draw_shape(s: Dictionary, col: Color) -> void:
	var fill := col; fill.a = 0.25
	match s.type:
		"circle":
			draw_circle(s.c, s.r, fill)
			draw_arc(s.c, s.r, 0, TAU, 24, col, 1)
		"arc":
			var pts := PackedVector2Array([s.c])
			for i in 13: pts.append(s.c + Vector2.from_angle(s.dir - s.half + s.half * 2 * i / 12.0) * s.r)
			draw_colored_polygon(pts, fill)
			pts.append(s.c); draw_polyline(pts, col, 1)
		"line":
			var d: Vector2 = (s.b - s.a).normalized().orthogonal() * s.w * 0.5
			var pts := PackedVector2Array([s.a + d, s.b + d, s.b - d, s.a - d])
			draw_colored_polygon(pts, fill)
			pts.append(s.a + d); draw_polyline(pts, col, 1)
