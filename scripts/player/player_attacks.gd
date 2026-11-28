class_name PlayerAttacks
extends RefCounted
## 무기 6군의 기본 콤보·방향 파생기·차지·대시 공격 (GDD 5-3, 7-3).
## 공격 한 번은 '설명(desc)' 사전으로 만들어지고 update_attack 이 프레임마다 판정을 낸다.

var p: Player
var combo := 0
var last_end := -99.0
var desc := {}
var t := 0.0
var hit_done := false
var hit_targets: Array = []
var press_time := -99.0
var charge_t := 0.0
var charge_full := false
var _spawned := false
var _swoosh_done := false

func _init(player: Player) -> void:
	p = player

func cls() -> String:
	return p.data.weapon_class()

func cd() -> Dictionary:
	return p.data.class_data()

func tile() -> float:
	return float(Data.bal("tile", 16))

func unique() -> Dictionary:
	return p.data.weapon_unique()

func ut() -> String:
	return unique().get("type", "")

func superarmor_now() -> bool:
	return bool(cd().traits.get("swing_superarmor", false)) and p.state == Player.S.ATTACK

func swing_time() -> float:
	# hit_time 은 무기군 기본 속도 기준. 민첩·장비 공격속도 보너스만큼 짧아진다.
	return float(cd().hit_time) / maxf(0.1, p.data.attack_speed() / float(cd().speed))

# ---------- 시작 ----------
func start_combo() -> void:
	press_time = Clock.game_time
	var mults: Array = cd().combo
	if Clock.game_time - last_end > float(Data.bal("control.combo_reset")) or combo >= mults.size():
		combo = 0
	_aim()
	var d := _basic_desc(combo)
	# 방향 파생기: 콤보 중 앞/뒤 입력
	if combo > 0 and p.move_input != Vector2.ZERO:
		var dot := p.move_input.dot(p.aim_dir)
		var th := float(Data.bal("control.derivative_dot"))
		if dot >= th and not cls() in ["bow", "staff"]:
			d.lunge = 1.5 * tile(); d.swing = "thrust"; d.derive = "forward"
			if d.shape == "arc": d.angle = 60
		elif dot <= -th:
			d.lunge = -1.0 * tile(); d.derive = "back"
	combo += 1
	_start(d)

func start_dash_attack() -> void:
	press_time = Clock.game_time
	combo = 0
	_aim()
	var da: Dictionary = cd().dash_attack
	var d := {}
	match da.type:
		"dash_slash", "dash_thrust":
			var dist := float(da.distance) * tile()
			dist *= 1.0 + float(cd().traits.get("dash_attack_distance", 0.0))
			if ut() == "dash_attack_boost": dist *= 1.0 + float(unique().params.distance)
			d = {"kind": "dash", "mult": float(da.mult), "dur": 0.32, "active": [0.1, 0.75], "shape": "path", "radius": 14.0,
				"lunge": dist, "swing": "thrust" if da.type == "dash_thrust" else "slash_a", "anim": "dash"}
			if da.type == "dash_thrust": d.star_beam = true
		_:
			d = _shot_desc(float(da.mult), "dash")
	_start(d)
	if ut() == "dash_attack_boost": p.move_boost_left = float(unique().params.duration) + 0.32

func backstep_shot() -> void:
	_aim()
	var d := _shot_desc(1.0, "basic")
	d.lunge = -2.0 * tile(); d.dur = 0.3; d.active = [0.55, 0.7]
	_start(d)
	p.invuln_time = maxf(p.invuln_time, 0.1)

func _aim() -> void:
	var dir := p.move_input if p.move_input != Vector2.ZERO else p.facing
	p.aim_dir = dir.normalized()
	if Settings.get_value("gameplay", "aim_assist", true):
		var rng := maxf(float(Data.bal("control.aim_assist_range")), float(cd().range) * tile() + 16)
		var tgt := Combat.aim_target(p.global_position, p.aim_dir, float(Data.bal("control.aim_assist_angle")), rng)
		if tgt: p.aim_dir = (tgt.global_position - p.global_position).normalized()
	p.facing = Player._snap8(p.aim_dir)

func _range_px() -> float:
	var r = float(cd().range) * tile() * (1.0 + p.data.gear_mods().get("range_pct", 0.0))
	if ut() == "long_reach" and cls() == "spear": r *= float(unique().params.range)
	return r

func _basic_desc(i: int) -> Dictionary:
	var mults: Array = cd().combo
	var last := i == mults.size() - 1 and mults.size() >= 3
	var kind := "finisher" if last else "basic"
	var mult := float(mults[mini(i, mults.size() - 1)])
	var st := swing_time() * (1.25 if last else 1.0)
	var act: Array = cd().active
	match cls():
		"bow", "staff":
			var d := _shot_desc(mult, kind)
			d.dur = st
			return d
		"spear":
			return {"kind": kind, "mult": mult, "dur": st, "active": act, "shape": "line", "range": _range_px(), "width": float(cd().width) * tile(),
				"pierce": last and bool(cd().traits.get("last_hit_pierce", false)) or ut() == "extra_pierce", "extra_pierce": int(unique().params.get("count", 0)) if ut() == "extra_pierce" else 0,
				"lunge": 3.0, "swing": "thrust", "anim": "attack", "star_beam": true}
	var swing := "slash_a" if i % 2 == 0 else "slash_b"
	if last: swing = "smash" if cls() == "greatsword" else "slash_wide"
	return {"kind": kind, "mult": mult, "dur": st, "active": act, "shape": "arc", "range": _range_px() + 6.0, "angle": float(cd().arc) + (20.0 if last else 0.0),
		"lunge": 4.0 if cls() != "greatsword" else 2.0, "swing": swing, "anim": "attack", "finisher": last}

func _shot_desc(mult: float, kind: String) -> Dictionary:
	var c := cd()
	if cls() == "bow":
		return {"kind": kind, "mult": mult, "dur": swing_time(), "active": [0.4, 0.5], "shape": "proj", "swing": "shoot", "anim": "attack",
			"proj": {"speed": float(c.projectile_speed), "dist": float(c.range) * tile(), "visual": "arrow", "color": Color(0.95, 0.92, 0.8), "count": 1, "spread": 0.0, "tag": "bow_shot",
				"bounce": int(unique().params.count) if ut() == "arrow_bounce" else 0}}
	var count := 1
	var spread := 0.0
	if ut() == "triple_bolt":
		count = int(unique().params.count); spread = float(unique().params.spread)
	return {"kind": kind, "mult": mult, "dur": swing_time(), "active": [0.4, 0.5], "shape": "proj", "swing": "cast", "anim": "attack",
		"proj": {"speed": float(c.projectile_speed), "dist": float(c.range) * tile(), "visual": "bolt", "color": Color(0.6, 0.85, 1.0), "count": count, "spread": spread,
			"explode": float(c.explode_radius) * tile(), "tag": "staff_bolt"}}

func _start(d: Dictionary) -> void:
	desc = d
	t = 0.0
	hit_done = false
	hit_targets.clear()
	_spawned = false
	_swoosh_done = false
	p.set_state(Player.S.ATTACK)
	p.begin_action(d.kind)
	p.look.play(d.get("anim", "attack"), 4.0 / maxf(0.1, d.dur) / 10.0, false)
	if bool(cd().traits.get("swing_superarmor", false)) and d.kind != "dash": p.superarmor += 1; d["_sa"] = true
	p.velocity = Vector2.ZERO

func end_attack() -> void:
	if desc.get("_sa", false):
		p.superarmor = maxi(0, p.superarmor - 1); desc["_sa"] = false
	p.look.weapon_angle_override = null
	p.look.weapon_extend = 0.0
	last_end = Clock.game_time

# ---------- 진행 ----------
func update_attack(dt: float) -> void:
	t += dt
	var dur: float = desc.dur
	var f := t / dur
	var a0: float = desc.active[0]
	var a1: float = desc.active[1]
	# 몸 이동 (돌진·물러나기)
	var lunge: float = desc.get("lunge", 0.0)
	if lunge != 0.0 and f <= a1:
		var span := a1
		p.velocity = p.aim_dir * (lunge / (dur * span))
	elif cls() == "bow" and desc.kind in ["basic"] and p.move_input != Vector2.ZERO:
		var slow = float(cd().traits.get("move_while_attacking", 0.7)) + p.data.gear_mods().get("move_attack", 0.0)
		p.velocity = p.move_input * p.current_move_speed() * slow
	else:
		p.velocity = p.velocity.move_toward(Vector2.ZERO, 1200 * dt)
	_animate_weapon(f)
	# 판정
	if f >= a0 and f <= a1 + 0.0001:
		_do_hits()
		if not hit_done:
			hit_done = true
			_on_active_start()
	elif f > a1 and not hit_done:
		hit_done = true; _do_hits(); _on_active_start()
	# 콤보 잇기
	if f >= a1 and InputManager.buffered("attack") and not desc.kind in ["charge", "dash"]:
		var mults: Array = cd().combo
		if combo < mults.size() or mults.size() == 1:
			InputManager.consume("attack")
			if mults.size() == 1: combo = 0
			start_combo()
			return
	if f >= 1.0:
		# 길게 누르고 있으면 차지로
		if InputManager.held("attack") and desc.kind in ["basic", "finisher"] and Clock.game_time - press_time >= 0.18:
			_start_charge(); return
		if desc.get("finisher", false) or combo >= (cd().combo as Array).size(): combo = 0 if (cd().combo as Array).size() > 1 else combo
		p.set_state(Player.S.IDLE)

func _on_active_start() -> void:
	if desc.shape == "proj" and not _spawned:
		_spawned = true
		_spawn_projectiles()
	if desc.get("finisher", false):
		match ut():
			"finisher_echo":
				var d := desc.duplicate(true)
				var pos := p.global_position
				var dir := p.aim_dir
				p.get_tree().create_timer(float(unique().params.delay), false).timeout.connect(func(): _echo_hit(d, pos, dir, float(unique().params.mult)))
			"finisher_rocks":
				for i in int(unique().params.count):
					var off := Vector2.from_angle(TAU * i / 3.0 + randf()) * 28
					SkillExecutor.delayed_blast(p, p.global_position + off, 14, float(unique().params.mult), 0.3 + i * 0.1, Color(0.65, 0.6, 0.5))
	if desc.get("star_beam", false) and ut() == "kill_star_beam" and p.stars >= int(unique().params.stars):
		p.stars = 0
		var a := p.global_position + Vector2(0, -6)
		var b := a + p.aim_dir * 10 * tile()
		Fx.line(a, b, Color(1, 0.95, 0.6), 8, 0.35)
		p.begin_action("proc")
		for tg in Combat.targets_in(Combat.line(a, b, 20), p.team):
			p.deal(tg, p.make_hit(float(unique().params.mult), "proc"))

func _echo_hit(d: Dictionary, pos: Vector2, dir: Vector2, mult: float) -> void:
	var s := _shape_for(d, pos, dir)
	Fx.swoosh(pos + Vector2(0, -6), d.get("range", 20), dir.angle() - 1.2, dir.angle() + 1.2, Color(1, 0.85, 0.4, 0.6), 3, 0.2)
	p.begin_action("proc")
	for tg in Combat.targets_in(s, p.team):
		p.deal(tg, p.make_hit(float(d.mult) * mult, "proc"))

func _shape_for(d: Dictionary, pos: Vector2, dir: Vector2) -> Dictionary:
	var c := pos + Vector2(0, -6)
	match d.shape:
		"arc": return Combat.arc(c, d.range, dir.angle(), d.angle)
		"line": return Combat.line(c, c + dir * float(d.range), float(d.width))
		"circle": return Combat.circle(c + dir * float(d.get("offset", 0.0)), float(d.radius))
		"path": return Combat.circle(c, float(d.radius))
	return Combat.circle(c, 1)

func _do_hits() -> void:
	if desc.shape == "proj": return
	var s := _shape_for(desc, p.global_position, p.aim_dir)
	Fx.debug_shape(s, Color(1, 0.3, 0.3))
	if not _swoosh_done:
		_swoosh_done = true
		_swing_fx()
	var found := Combat.targets_in(s, p.team).filter(func(x): return not x in hit_targets)
	if desc.shape == "line" and not desc.get("pierce", false):
		if not hit_targets.is_empty(): return
		found.sort_custom(func(a, b): return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
		found = found.slice(0, 1 + int(desc.get("extra_pierce", 0)))
	for tg in found:
		hit_targets.append(tg)
		var h := p.make_hit(float(desc.mult), desc.kind)
		h.dir = (tg.global_position - p.global_position).normalized()
		if ut() == "long_reach" and desc.shape == "line":
			var k := clampf(tg.global_position.distance_to(p.global_position) / float(desc.range), 0, 1)
			h.bonus += k * float(unique().params.max_bonus)
		_charge_extras(tg, h)
		p.deal(tg, h)

func _swing_fx() -> void:
	var col := Color(1, 1, 1).lerp(Data.grade_color(p.data.weapon().get("grade", "common")), 0.55)
	if ut() == "just_dodge_next_attack": col = Color(1, 0.6, 0.25)
	var c := p.global_position + Vector2(0, -6)
	var ang := p.aim_dir.angle()
	match desc.shape:
		"arc":
			var half := deg_to_rad(float(desc.angle)) * 0.5
			var a0 := ang - half if desc.swing != "slash_b" else ang + half
			var a1 := ang + half if desc.swing != "slash_b" else ang - half
			Fx.swoosh(c, float(desc.range) - 3, minf(a0, a1), maxf(a0, a1), col, 4 if desc.get("finisher", false) else 3, 0.18)
		"line":
			Fx.line(c, c + p.aim_dir * float(desc.range), col, 3, 0.12)
		"circle":
			Fx.ring(c + p.aim_dir * float(desc.get("offset", 0.0)), float(desc.radius), col, 0.35, 3)
			Fx.burst(c + p.aim_dir * float(desc.get("offset", 0.0)), Color(0.75, 0.7, 0.6), 14, 80, 0.4)
		"path":
			Fx.line(c, c + p.aim_dir * float(desc.lunge), col, 3, 0.18)

func _animate_weapon(f: float) -> void:
	var ang := p.aim_dir.angle()
	var k := clampf(f / maxf(0.01, desc.active[1]), 0, 1)
	match desc.get("swing", "slash_a"):
		"slash_a", "slash_wide": p.look.weapon_angle_override = ang - 1.4 + k * 2.8; p.look.weapon_extend = 0
		"slash_b": p.look.weapon_angle_override = ang + 1.4 - k * 2.8
		"smash": p.look.weapon_angle_override = ang - 2.2 + k * 2.2
		"thrust": p.look.weapon_angle_override = ang; p.look.weapon_extend = sin(k * PI) * 6.0
		"shoot", "cast": p.look.weapon_angle_override = ang

func _spawn_projectiles() -> void:
	var pr: Dictionary = desc.proj
	var n := int(pr.count)
	for i in n:
		var off := 0.0 if n == 1 else lerp(-float(pr.spread), float(pr.spread), i / float(n - 1))
		var dir := p.aim_dir.rotated(deg_to_rad(off))
		var kind: String = desc.kind
		var mult: float = desc.mult
		var tag: String = pr.get("tag", "")
		var maker := func():
			var h := p.make_hit(mult, kind)
			if tag != "": h.tags[tag] = true
			return h
		var opts := {"team": "player", "visual": pr.visual, "color": pr.color, "radius": 3.0,
			"pierce": int(pr.get("pierce", 0)), "explode": float(pr.get("explode", 0.0)), "bounce": int(pr.get("bounce", 0))}
		var on_hit := Callable()
		if pr.has("on_hit"): on_hit = pr.on_hit
		opts.on_hit = on_hit
		var proj := Projectile.spawn(Game.world.entities, p.global_position + Vector2(0, -8) + dir * 6, dir, float(pr.speed), float(pr.dist), maker, opts)
		if p.frozen_left > 0 and cls() == "bow":
			proj.frozen = true
			proj.travelled = 0
			proj.velocity = dir * float(pr.speed)
			var fm := p.frozen_mult
			proj.hit_maker = func():
				var h := p.make_hit(fm, "skill"); h.tags[tag] = true; return h
			p.frozen_arrows.append(proj)
			proj.global_position += dir * 10
	if cls() == "bow": Fx.burst(p.global_position + Vector2(0, -8) + p.aim_dir * 8, Color(0.95, 0.9, 0.7), 3, 30, 0.2)

# ---------- 차지 ----------
func _start_charge() -> void:
	p.set_state(Player.S.CHARGE)
	charge_t = Clock.game_time - press_time
	charge_full = false
	p.look.play("charge", 0.8)

func end_charge() -> void:
	p.look.weapon_angle_override = null

func update_charge(dt: float) -> void:
	charge_t += dt
	var need := float(Data.bal("control.charge_time"))
	var mv := p.move_input * p.current_move_speed() * 0.35
	p.velocity = p.velocity.move_toward(mv, 900 * dt)
	if p.move_input != Vector2.ZERO:
		p.facing = Player._snap8(p.move_input); p.aim_dir = p.facing
	p.look.weapon_angle_override = p.aim_dir.angle() + PI * 0.75
	var glow_col := Color(0.75, 0.95, 1.0) if ut() != "charge_guard" else Color(1, 0.6, 0.2)
	if randf() < 0.4: Fx.burst(p.global_position + Vector2(0, -10), glow_col, 1, 25, 0.3)
	if not charge_full and charge_t >= need:
		charge_full = true
		Fx.ring(p.global_position + Vector2(0, -8), 18, glow_col, 0.3, 2)
		Fx.glow(p.global_position + Vector2(0, -8), 12, glow_col, 0.2)
	if not InputManager.held("attack"):
		if charge_full: _release_charge()
		else: p.set_state(Player.S.IDLE)

func _release_charge() -> void:
	_aim()
	var ch: Dictionary = cd().charge
	var d := {}
	match ch.type:
		"dash_slash":
			d = {"kind": "charge", "mult": float(ch.mult), "dur": 0.42, "active": [0.15, 0.7], "shape": "path", "radius": 16.0, "lunge": float(ch.distance) * tile(), "swing": "slash_wide", "anim": "dash"}
		"shockwave":
			var r := float(ch.radius) * tile()
			if ut() == "charge_shockwave_radius": r *= 1.0 + float(unique().params.bonus)
			d = {"kind": "charge", "mult": float(ch.mult), "dur": 0.55, "active": [0.45, 0.6], "shape": "circle", "radius": r, "offset": 12.0, "swing": "smash", "anim": "attack", "time_stop": ut() == "charge_time_stop"}
		"leap_throw":
			d = {"kind": "charge", "mult": float(ch.mult), "dur": 0.4, "active": [0.55, 0.65], "shape": "proj", "lunge": -float(ch.back) * tile(), "swing": "shoot", "anim": "dash",
				"proj": {"speed": float(ch.speed), "dist": float(ch.range) * tile(), "visual": "dagger", "color": Color.WHITE, "count": 1, "spread": 0.0}}
		"long_thrust":
			var r := float(ch.range) * tile()
			if ut() == "long_reach": r *= float(unique().params.range)
			d = {"kind": "charge", "mult": float(ch.mult), "dur": 0.45, "active": [0.4, 0.6], "shape": "line", "range": r, "width": 14.0, "pierce": true, "lunge": 8.0, "swing": "thrust", "anim": "attack", "star_beam": true}
		"pierce_shot":
			d = _shot_desc(float(ch.mult), "charge")
			d.proj.speed = float(ch.speed); d.proj.pierce = 99; d.proj.visual = "arrow"; d.proj.color = Color(0.8, 0.95, 1.0)
			if ut() == "charge_frost_burst":
				var u := unique()
				d.proj.on_hit = func(tg, r, _pr): if r.get("result", "") == "hit": SkillExecutor.burst(p, tg.global_position, float(u.params.radius), float(u.params.mult), Color(0.75, 0.9, 1.0), [{"status": "slow", "duration": 2.5}])
			if ut() == "charge_arrow_rain":
				d["arrow_rain"] = true
		"aoe_blast":
			if ut() == "charge_sun":
				d = _shot_desc(float(unique().params.mult), "charge")
				d.proj.visual = "sun"; d.proj.color = Color(1, 0.7, 0.25); d.proj.explode = 1.6 * tile(); d.proj.speed = 200.0; d.proj.count = 1
				d.proj.on_hit = func(tg, r, _pr): if r.get("result", "") == "hit": tg.statuses.add("burn", 3.0, p.attack_power())
			else:
				d = {"kind": "charge", "mult": float(ch.mult), "dur": 0.5, "active": [0.45, 0.55], "shape": "circle", "radius": float(ch.radius) * tile(), "offset": float(ch.distance) * tile(), "swing": "cast", "anim": "attack"}
				var tgt := Combat.aim_target(p.global_position, p.aim_dir, 30, float(ch.distance) * tile() + 24)
				if tgt: d.offset = clampf(tgt.global_position.distance_to(p.global_position), 8, float(ch.distance) * tile() + 24)
	if ut() == "charge_guard": d["sun_eater"] = true
	_start(d)
	if d.get("arrow_rain", false):
		var tgt := Combat.aim_target(p.global_position, p.aim_dir, 30, 9 * tile())
		var pos: Vector2 = tgt.global_position if tgt else p.global_position + p.aim_dir * 5 * tile()
		var u := unique()
		SkillExecutor.rain(p, pos, 22, int(u.params.count), float(u.params.mult), 0.6, 0.35)
	Fx.hitstop("normal")

func _charge_extras(tg: Node, h: HitInfo) -> void:
	if desc.kind != "charge": return
	if desc.get("sun_eater", false): h.bonus += float(unique().params.bonus)
	if desc.get("time_stop", false):
		var u := unique()
		tg.statuses.add("time_stop", float(u.params.duration), 0.0, {"boss_slow": float(u.params.boss_slow)})
