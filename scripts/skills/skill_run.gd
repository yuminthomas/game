class_name SkillRun
extends RefCounted
## 시전 중인 스킬 하나. behavior.type 마다 start/update 가 있다. 행위자(actor)는 Player 또는 GhostActor(잔상).

var actor                         # Player 또는 GhostActor
var player: Player
var skill: Dictionary
var skill_id := ""
var lv := 1
var p := {}                       # Lv5 가 반영된 동작 수치
var power := 1.0
var slot := ""
var t := 0.0
var done := false
var hit_done := false
var dur := 0.3
var st := {}                      # 동작별 상태
var _sa := false
var _inv := false

func _init(a, s: Dictionary, level: int, pw: float, key_slot := "") -> void:
	actor = a
	player = a if a is Player else a.player
	skill = s
	skill_id = s.id
	lv = level
	power = pw
	slot = key_slot
	p = SkillExecutor.params_for(s, level)

func tile() -> float:
	return float(Data.bal("tile", 16))

func level_mult() -> float:
	return (1.0 + float(Data.bal("skills.damage_per_level")) * (lv - 1)) * player.data.skill_damage_mult() * power

func pos() -> Vector2:
	return actor.global_position

func dir() -> Vector2:
	return actor.aim_dir

func hit(mult: float, extra_effects: Array = []) -> HitInfo:
	var h: HitInfo = actor.make_hit(mult * level_mult(), "skill")
	h.skill_id = skill_id
	h.groggy = float(skill.get("groggy", 3))
	h.hitstop = "normal"
	for e in p.get("effects", []) + extra_effects: h.statuses.append(e.duplicate())
	if p.has("knockback"): h.knockback = float(p.knockback) * 40.0
	return h

func strike_shape(shape: Dictionary, mult: float, once_list = null, extra: Array = []) -> Array:
	Fx.debug_shape(shape, Color(0.4, 0.8, 1))
	var out := []
	for tg in Combat.targets_in(shape, actor.team):
		if once_list != null and tg in once_list: continue
		if once_list != null: once_list.append(tg)
		var h := hit(mult, extra)
		h.dir = (tg.global_position - pos()).normalized()
		if h.dir == Vector2.ZERO: h.dir = dir()
		actor.deal(tg, h)
		out.append(tg)
	hit_done = true
	return out

func set_superarmor(on: bool) -> void:
	if actor is Player and on != _sa:
		_sa = on
		player.superarmor += 1 if on else -1

func set_invuln(seconds: float) -> void:
	if actor is Player: player.invuln_time = maxf(player.invuln_time, seconds)

func pose(anim: String, speed := 1.0) -> void:
	if actor is Player: player.set_pose(anim, speed)

func finish() -> void:
	if done: return
	done = true
	set_superarmor(false)
	if actor is Player:
		player.look.weapon_angle_override = null
		player.look.weapon_extend = 0.0

func interrupt() -> void:
	if actor is Player: player.look.position.y = 0
	finish()

func cancel_ok() -> bool:
	return hit_done or t > dur

func damage_taken_mult() -> float:
	if skill.behavior.type == "charge_slam": return 1.0 - float(p.get("charge_reduction", 0.0))
	return 1.0

## 반격 자세: 자세 중 맞으면 무피해 + 반격
func absorbs_hit(h: HitInfo) -> bool:
	if skill.behavior.type != "counter" or st.get("countered", false) or done: return false
	if h.unblockable or h.kind == "dot": return false
	st.countered = true
	Fx.hitstop("parry")
	Fx.text(pos() + Vector2(0, -34), "반격!", Color(1, 0.95, 0.6))
	var c := pos() + Vector2(0, -6)
	var d := dir()
	if h.attacker and is_instance_valid(h.attacker): d = (h.attacker.global_position - pos()).normalized(); actor.aim_dir = d
	Fx.swoosh(c, float(p.range) * tile(), d.angle() - 1.4, d.angle() + 1.4, Color(1, 0.95, 0.6), 5, 0.25)
	strike_shape(Combat.arc(c, float(p.range) * tile(), d.angle(), float(p.angle)), float(p.mult))
	if p.get("refund", false): player.gain_stamina(float(skill.stamina), false)
	t = dur - 0.2
	return true

func on_kill(_target: Node) -> void:
	if p.get("kill_reset", false):
		player.cooldowns.erase(skill_id)
		Fx.text(pos() + Vector2(0, -36), "쿨타임 초기화", Color(0.8, 1, 0.8))

# =====================================================================
func start() -> void:
	actor.aim_dir = _aimed_dir()
	if actor is Player: player.facing = Player._snap8(actor.aim_dir)
	var fn := "_start_" + str(skill.behavior.type)
	if has_method(fn): call(fn)
	else: finish()

func update(dt: float) -> void:
	if done: return
	t += dt
	var fn := "_update_" + str(skill.behavior.type)
	if has_method(fn): call(fn, dt)
	elif t >= dur: finish()

func _aimed_dir() -> Vector2:
	var d: Vector2 = actor.aim_dir
	if actor is Player and player.move_input != Vector2.ZERO: d = player.move_input
	if Settings.get_value("gameplay", "aim_assist", true):
		var tg := Combat.aim_target(pos(), d, 30, 120)
		if tg: d = (tg.global_position - pos()).normalized()
	return d.normalized()

func _target_point(dist_tiles: float) -> Vector2:
	var tg := Combat.aim_target(pos(), dir(), 35, (dist_tiles + 2) * tile())
	if tg: return tg.global_position
	return pos() + dir() * dist_tiles * tile()

# ---------- strike: 전방 베기·찌르기·내려찍기 ----------
func _start_strike() -> void:
	dur = 0.12 + float(p.get("hits", 1)) * float(p.get("interval", 0.0)) + 0.25
	st = {"next": 0, "count": 0}
	pose("attack", 1.6)

func _update_strike(_dt: float) -> void:
	var hits := int(p.get("hits", 1))
	var interval := float(p.get("interval", 0.0))
	while st.count < hits and t >= 0.12 + st.count * interval:
		st.count += 1
		var c := pos() + Vector2(0, -6)
		var shape := {}
		var r := float(p.get("range", 1.5)) * tile()
		match p.shape:
			"arc": shape = Combat.arc(c, r, dir().angle(), float(p.get("angle", 120)))
			"line": shape = Combat.line(c, c + dir() * r, float(p.get("width", 1.0)) * tile())
			"circle_front": shape = Combat.circle(c + dir() * r * 0.7, float(p.get("radius", 1.4)) * tile())
		_strike_fx(shape)
		var mult := float(p.mult)
		if st.count == hits and p.has("final_beam_mult"):
			var b := c + dir() * 5 * tile()
			Fx.line(c, b, Color(1, 0.95, 0.7), 6, 0.25)
			strike_shape(Combat.line(c, b, 16), float(p.final_beam_mult))
		var victims := strike_shape(shape, mult)
		if p.get("shockwave", false) or p.has("shockwave_extra"):
			var extra := float(p.get("shockwave_extra", 0)) * tile()
			var wc := c + dir() * (r + extra * 0.5)
			Fx.ring(wc, 18 + extra * 0.5, Color(0.9, 0.85, 0.7), 0.3, 2)
			if extra > 0: strike_shape(Combat.line(c, c + dir() * (r + extra), 18), mult * 0.5, victims)
		if p.has("followup_mult") and not victims.is_empty():
			var list := victims.duplicate()
			var m := float(p.followup_mult)
			player.get_tree().create_timer(0.35, false).timeout.connect(func():
				for v in list:
					if is_instance_valid(v) and not v.dead and v.statuses.has("airborne"):
						Fx.swoosh(v.global_position + Vector2(0, -20), 12, -2.5, 0.5, Color(1, 1, 1), 3, 0.15)
						actor.begin_action("skill")
						actor.deal(v, hit(m)))
	if t >= dur: finish()

func _strike_fx(shape: Dictionary) -> void:
	var col := Color(Data.skill_tiers[skill.tier].color).lerp(Color.WHITE, 0.4)
	match shape.type:
		"arc": Fx.swoosh(shape.c, shape.r - 2, shape.dir - shape.half, shape.dir + shape.half, col, 4, 0.2)
		"line": Fx.line(shape.a, shape.b, col, 4, 0.15)
		"circle": Fx.ring(shape.c, shape.r, col, 0.3, 3); Fx.burst(shape.c, Color(0.8, 0.75, 0.6), 12, 80, 0.4)
	if actor is Player:
		player.look.weapon_angle_override = dir().angle() + (1.2 if st.count % 2 == 0 else -1.2)

# ---------- dash_strike: 돌진 베기 ----------
func _start_dash_strike() -> void:
	dur = float(p.duration) + 0.15
	st = {"hit": [], "carried": [], "wall": false}
	if p.get("invuln", false): set_invuln(float(p.duration) + 0.05)
	if p.get("superarmor", false): set_superarmor(true)
	pose("dash", 1.5)

func _update_dash_strike(dt: float) -> void:
	if t <= float(p.duration):
		var speed := float(p.distance) * tile() / float(p.duration)
		var step: Vector2 = dir() * speed * dt
		if actor.move_by(step): st.wall = true
		var c := pos() + Vector2(0, -6)
		var victims := strike_shape(Combat.circle(c, float(p.width) * tile() * 0.6), float(p.mult), st.hit)
		if p.get("carry", false):
			st.carried += victims
			for v in st.carried:
				if is_instance_valid(v) and not v.dead and not v.is_boss(): v.global_position = pos() + dir() * 14
		if randf() < 0.6: Fx.burst(c, Color(0.9, 0.95, 1), 2, 30, 0.25)
		Fx.line(c - dir() * 10, c, Color(1, 1, 1, 0.6), 3, 0.1)
		if st.wall and p.has("wall_mult") and not st.get("wall_done", false):
			st.wall_done = true
			Fx.shake(3.0); Fx.ring(c, 20, Color(1, 0.8, 0.5), 0.3, 3)
			for v in st.carried:
				if is_instance_valid(v) and not v.dead:
					actor.begin_action("skill"); actor.deal(v, hit(float(p.wall_mult)))
	elif not st.get("ended", false):
		st.ended = true
		if p.has("end_mult"):
			var c := pos() + Vector2(0, -6) + dir() * 10
			Fx.ring(c, 22, Color(0.9, 0.85, 0.7), 0.3, 3); Fx.shake(2.5)
			strike_shape(Combat.circle(c, 22), float(p.end_mult))
	if t >= dur: finish()

# ---------- spin: 회전 베기 ----------
func _start_spin() -> void:
	dur = float(p.duration)
	st = {"count": 0}
	if p.get("superarmor", false): set_superarmor(true)
	pose("attack", 2.0)

func _update_spin(dt: float) -> void:
	var mv := float(p.get("move", 0.0))
	if mv > 0:
		var input: Vector2 = player.move_input if actor is Player else Vector2.ZERO
		var speed := float(Data.bal("control.move_speed")) * mv * dt
		if p.get("forced_move", false):
			if input != Vector2.ZERO: actor.aim_dir = input
			actor.move_by(dir() * speed)
		elif input != Vector2.ZERO:
			actor.move_by(input * speed)
	var hits := int(p.hits)
	var r := float(p.radius) * tile()
	var c := pos() + Vector2(0, -6)
	while st.count < hits and t >= dur * st.count / hits:
		st.count += 1
		var a0 := t * 18.0
		Fx.swoosh(c, r - 2, a0, a0 + PI * 1.4, Color(0.9, 0.95, 1), 3, 0.2)
		Fx.ring(c, r, Color(0.9, 0.95, 1, 0.5), 0.2, 1)
		strike_shape(Combat.circle(c, r), float(p.mult))
		if p.get("trail_bleed", false): _bleed_trail()
	if float(p.get("pull", 0.0)) > 0:
		for v in Combat.targets_in(Combat.circle(c, r * 1.6), actor.team):
			if not v.is_boss() and v.superarmor <= 0:
				v.move_and_collide((c - v.global_position).normalized() * float(p.pull) * tile() * dt)
	if actor is Player: player.look.weapon_angle_override = t * 18.0
	if t >= dur: finish()

func _bleed_trail() -> void:
	var z := Zone.new()
	z.team = actor.team; z.radius = 12; z.duration = 1.5; z.hits = 0
	z.visual = "pool"; z.color = Color(0.85, 0.2, 0.2, 0.6); z.apply_status = "bleed"
	z.global_position = pos()
	SkillExecutor.world().add_child(z)

# ---------- counter: 반격 자세 ----------
func _start_counter() -> void:
	dur = float(p.duration) + 0.2
	pose("guard", 1.0)
	Fx.ring(pos() + Vector2(0, -8), 16, Color(1, 0.95, 0.6), 0.6, 1)

func _update_counter(_dt: float) -> void:
	if actor is Player: player.velocity = Vector2.ZERO
	if t >= dur: finish()

# ---------- multi_teleport: 순간이동 연격 ----------
func _start_multi_teleport() -> void:
	dur = int(p.hits) * float(p.interval) + 0.2
	st = {"count": 0, "origin": pos()}
	if p.get("invuln", false): set_invuln(dur)
	var targets := Combat.enemies_of(actor.team).filter(func(e): return e.global_position.distance_to(pos()) <= float(p.radius) * tile())
	if targets.is_empty():
		finish(); return
	st.targets = targets
	pose("attack", 3.0)

func _update_multi_teleport(_dt: float) -> void:
	while st.count < int(p.hits) and t >= st.count * float(p.interval):
		var alive: Array = st.targets.filter(func(e): return is_instance_valid(e) and not e.dead)
		if alive.is_empty(): break
		var tg: Node = alive[st.count % alive.size()]
		st.count += 1
		var from := pos()
		var side := Vector2.from_angle(randf() * TAU) * 14
		actor.global_position = tg.global_position + side
		actor.aim_dir = (tg.global_position - pos()).normalized()
		Fx.line(from + Vector2(0, -8), pos() + Vector2(0, -8), Color(0.85, 0.95, 1, 0.7), 2, 0.12)
		Fx.swoosh(tg.global_position + Vector2(0, -8), 12, randf() * TAU, randf() * TAU + 2.5, Color(1, 1, 1), 3, 0.12)
		actor.begin_action("skill")
		var h := hit(float(p.mult))
		h.dir = actor.aim_dir
		actor.deal(tg, h)
		hit_done = true
	if t >= dur: finish()

# ---------- beam: 직선 광선·균열 ----------
func _start_beam() -> void:
	dur = float(p.get("delay", 0.2)) + 0.3
	st = {"fired": false}
	pose("attack", 1.2)
	var c := pos() + Vector2(0, -6)
	Fx.line(c, c + dir() * float(p.length) * tile(), Color(1, 1, 1, 0.25), 1, float(p.get("delay", 0.2)))

func _update_beam(_dt: float) -> void:
	if not st.fired and t >= float(p.get("delay", 0.2)):
		st.fired = true
		var c := pos() + Vector2(0, -6)
		var b := c + dir() * float(p.length) * tile()
		var w := float(p.width) * tile()
		if p.get("visual", "") == "crack":
			Fx.line(c, b, Color(0.55, 0.4, 0.3), w * 0.6, 0.6); Fx.shake(3.0)
			for i in 8: Fx.burst(c.lerp(b, i / 8.0), Color(0.7, 0.6, 0.5), 3, 60, 0.4)
		else:
			Fx.line(c, b, Color(0.85, 0.97, 1.0), w, 0.35); Fx.shake(2.5)
		var victims := strike_shape(Combat.line(c, b, w), float(p.mult))
		for v in victims:
			for e in p.get("effects", []):
				if e.status == "time_stop": v.statuses.add("time_stop", float(e.duration), 0.0, {"force": true})
		if p.has("burn_zone"):
			for i in 4:
				var z := Zone.new()
				z.team = actor.team; z.radius = w * 0.6; z.duration = float(p.burn_zone); z.hits = 0
				z.visual = "crack"; z.apply_status = "burn"; z.color = Color(1, 0.4, 0.1)
				z.status_opts = {}
				z.global_position = c.lerp(b, (i + 0.5) / 4.0) + Vector2(0, 6)
				SkillExecutor.world().add_child(z)
	if t >= dur: finish()

# ---------- aura: 내 주위 지속 피해 (칼날 폭풍, 용의 비상, 태양 강림) ----------
func _start_aura() -> void:
	dur = 0.3
	pose("interact", 1.2)
	var z := Zone.new()
	z.team = actor.team
	z.radius = float(p.radius) * tile()
	z.duration = float(p.duration)
	z.hits = int(p.hits)
	z.visual = p.get("visual", "blades")
	z.count = int(p.get("count", 6))
	z.color = Color(0.9, 0.95, 1) if z.visual != "sun" else Color(1, 0.6, 0.2)
	if p.get("follow", true): z.follow = actor
	var m := float(p.mult)
	var effects: Array = [{"status": "burn", "duration": 3}] if z.visual == "sun" else []
	z.hit_maker = func(_v):
		actor.begin_action("skill")
		return hit(m, effects)
	if p.has("end_mult"):
		var em := float(p.end_mult)
		z.on_end = func(zz): SkillExecutor.burst(actor, zz.global_position, zz.radius * 1.3, em * level_mult(), Color(0.9, 0.95, 1), [], "skill")
	z.global_position = pos()
	SkillExecutor.world().add_child(z)
	hit_done = true

# ---------- buff ----------
func _start_buff() -> void:
	dur = 0.25
	pose("interact", 1.2)
	hit_done = true
	if not actor is Player: return
	var id := skill_id
	var extra := {}
	if p.has("on_hit_status"):
		id = "poison_coat"; extra = {"poison_mult": float(p.get("poison_mult", 1.0))}
	player.add_buff(id, float(p.duration), p.get("mods", {}), p.get("flags", []), extra)
	Fx.ring(pos() + Vector2(0, -8), 20, Color(1, 0.8, 0.4), 0.5, 2)
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(1, 0.9, 0.6))

# ---------- leap: 도약 내려찍기 ----------
func _start_leap() -> void:
	dur = float(p.duration) + 0.15
	var target := _target_point(float(p.distance))
	if target.distance_to(pos()) > float(p.distance) * tile(): target = pos() + (target - pos()).normalized() * float(p.distance) * tile()
	st = {"from": pos(), "to": target, "landed": false}
	if p.get("invuln", false): set_invuln(float(p.duration))
	pose("dash", 1.0)

func _update_leap(_dt: float) -> void:
	var k := clampf(t / float(p.duration), 0, 1)
	if not st.landed:
		var np: Vector2 = st.from.lerp(st.to, k)
		actor.move_by(np - pos())
		if actor is Player: player.look.position.y = -sin(k * PI) * 22
		if k >= 1.0:
			st.landed = true
			if actor is Player: player.look.position.y = 0
			var r := float(p.radius) * tile() * float(p.get("radius_mult", 1.0))
			Fx.shake(3.0)
			Fx.ring(pos(), r, Color(1, 0.9, 0.7), 0.4, 3)
			Fx.burst(pos(), Color(0.75, 0.7, 0.6), 20, 100, 0.5)
			var victims := strike_shape(Combat.circle(pos(), r), float(p.mult))
			for v in victims:
				for e in p.get("effects", []):
					if e.status == "airborne": v.statuses.add("airborne", float(e.duration))
	if t >= dur: finish()

# ---------- charge_slam: 산을 쪼개는 일격 (키를 누르고 있는 동안 충전) ----------
func _start_charge_slam() -> void:
	dur = float(p.max_charge) + 0.5
	st = {"charge": 0.0, "released": false}
	set_superarmor(true)
	pose("charge", 1.0)

func _update_charge_slam(dt: float) -> void:
	if not st.released:
		st.charge += dt
		if randf() < 0.5: Fx.burst(pos() + Vector2(0, -10), Color(1, 0.8, 0.4), 1, 30, 0.3)
		var holding: bool = slot != "" and InputManager.held(slot)
		if not holding or st.charge >= float(p.max_charge):
			st.released = true
			st.release_t = t
			var k := clampf(st.charge / float(p.max_charge), 0, 1)
			var r: float = lerp(float(p.min_radius), float(p.radius), k) * tile()
			var m: float = lerp(float(p.min_mult), float(p.mult), k)
			var c := pos() + dir() * 14
			Fx.shake(2.0 + 3.0 * k); Fx.ring(c, r, Color(1, 0.85, 0.5), 0.5, 4); Fx.burst(c, Color(0.8, 0.7, 0.6), 30, 140, 0.6)
			Fx.hitstop("finisher")
			strike_shape(Combat.circle(c, r), m)
			pose("attack", 1.5)
	elif t - st.release_t >= 0.35:
		finish()

# ---------- multi_slam: 거인의 춤 ----------
func _start_multi_slam() -> void:
	dur = int(p.hits) * float(p.interval) + 0.2
	st = {"count": 0}
	set_superarmor(true)
	pose("attack", 2.0)

func _update_multi_slam(_dt: float) -> void:
	while st.count < int(p.hits) and t >= (st.count + 0.6) * float(p.interval):
		st.count += 1
		actor.move_by(dir() * float(p.get("step", 0.5)) * tile())
		var r := float(p.radius) * tile()
		if st.count == int(p.hits): r *= float(p.get("last_radius_mult", 1.0))
		var c := pos() + dir() * 12
		Fx.ring(c, r, Color(1, 0.85, 0.6), 0.35, 3); Fx.shake(2.5)
		Fx.burst(c, Color(0.75, 0.7, 0.6), 14, 100, 0.4)
		strike_shape(Combat.circle(c, r), float(p.mult))
		actor.aim_dir = actor.aim_dir.rotated(PI / 2.5)
	if t >= dur: finish()

# ---------- teleport_behind: 그림자 걸음, 암습 ----------
func _start_teleport_behind() -> void:
	dur = 0.3
	var tg := Combat.nearest(pos(), float(p.radius) * tile(), actor.team)
	if tg == null:
		Fx.text(pos() + Vector2(0, -34), "대상 없음", Color(1, 0.7, 0.7))
		finish(); return
	var behind: Vector2 = tg.global_position - tg.facing.normalized() * 14
	Fx.burst(pos() + Vector2(0, -8), Color(0.3, 0.3, 0.45), 10, 40, 0.3)
	actor.global_position = behind
	actor.aim_dir = (tg.global_position - behind).normalized()
	if actor is Player: player.facing = Player._snap8(actor.aim_dir)
	Fx.burst(pos() + Vector2(0, -8), Color(0.3, 0.3, 0.45), 10, 40, 0.3)
	if p.get("next_crit", false) and actor is Player:
		player.next_attack_crit = true
		Fx.text(pos() + Vector2(0, -34), "다음 공격 치명타", Color(1, 0.9, 0.4))
		if randf() < float(p.get("reset_chance", 0.0)):
			player.cooldowns.erase(skill_id)
			Fx.text(pos() + Vector2(0, -44), "쿨타임 초기화", Color(0.8, 1, 0.8))
	if float(p.mult) > 0:
		pose("attack", 2.0)
		var h := hit(float(p.mult))
		h.origin = pos()
		h.dir = actor.aim_dir
		Fx.line(pos() + Vector2(0, -8), tg.global_position + Vector2(0, -8), Color(1, 1, 1), 3, 0.12)
		var r: Dictionary = actor.deal(tg, h)
		if r.get("killed", false): on_kill(tg)
	hit_done = true

# ---------- clones: 그림자 분신 ----------
func _start_clones() -> void:
	dur = 0.3
	hit_done = true
	if not actor is Player: return
	for c in player.clones: if is_instance_valid(c): c.queue_free()
	player.clones.clear()
	for i in int(p.count):
		var g := player.look.make_ghost()
		g.modulate = Color(0.25, 0.25, 0.4, 0.6)
		SkillExecutor.world().add_child(g)
		g.global_position = pos()
		player.clones.append(g)
	player.clone_left = float(p.duration)
	player.add_buff("clones", float(p.duration), {}, [], {"mult": float(p.mult)})
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(0.7, 0.7, 1))

# ---------- projectile: 투척·연사·마법 탄 ----------
func _start_projectile() -> void:
	var n := int(p.count)
	var interval := float(p.get("interval", 0.0))
	dur = 0.15 + n * interval + 0.15
	st = {"fired": 0, "hits": {}}
	pose("attack", 1.5)

func _update_projectile(_dt: float) -> void:
	var n := int(p.count)
	var interval := float(p.get("interval", 0.0))
	while st.fired < n and t >= 0.1 + st.fired * interval:
		var off := 0.0
		if interval <= 0.0 and n > 1: off = lerp(-float(p.spread), float(p.spread), st.fired / float(n - 1))
		elif n > 1: off = randf_range(-float(p.spread), float(p.spread))
		st.fired += 1
		_fire(dir().rotated(deg_to_rad(off)))
		if interval <= 0.0:
			while st.fired < n:
				off = lerp(-float(p.spread), float(p.spread), st.fired / float(n - 1))
				st.fired += 1
				_fire(dir().rotated(deg_to_rad(off)))
	if t >= dur: finish()

func _fire(d: Vector2) -> void:
	var m := float(p.mult)
	var vis: String = p.get("visual", "arrow")
	var col := {"arrow": Color(0.95, 0.92, 0.8), "dagger": Color.WHITE, "fireball": Color(1, 0.5, 0.2), "frost": Color(0.7, 0.9, 1.0)}.get(vis, Color.WHITE)
	var explode := float(p.get("explode", 0.0)) * tile() * float(p.get("explode_mult", 1.0))
	var maker := func():
		actor.begin_action("skill")
		return hit(m)
	var on_hit := func(tg, r, _pr):
		if r.get("result", "") != "hit" or not p.get("freeze_on_3", false): return
		var k: int = st.hits.get(tg, 0) + 1
		st.hits[tg] = k
		if k == 3: tg.statuses.add("freeze", 1.5)
	Projectile.spawn(SkillExecutor.world(), pos() + Vector2(0, -8) + d * 6, d, float(p.speed), float(p.range) * tile(), maker,
		{"team": actor.team, "visual": vis, "color": col, "radius": 3.0 if vis != "fireball" else 4.0, "explode": explode, "on_hit": on_hit})
	hit_done = true

# ---------- throw_recall: 창 투척 (다시 누르면 회수) ----------
func _start_throw_recall() -> void:
	dur = 0.3
	pose("attack", 1.5)
	var m := float(p.mult)
	var spear_hit := func():
		actor.begin_action("skill")
		return hit(m)
	var proj := Projectile.spawn(SkillExecutor.world(), pos() + Vector2(0, -8), dir(), float(p.speed), float(p.range) * tile(), spear_hit,
		{"team": actor.team, "visual": "arrow", "color": Color(0.85, 0.9, 1.0), "radius": 4.0, "pierce": 0})
	# 꽂힌 자리를 기억할 표식
	var marker := Zone.new()
	marker.team = actor.team; marker.radius = 6; marker.duration = float(p.window); marker.hits = 0
	marker.visual = "trap"; marker.color = Color(0.85, 0.9, 1.0)
	marker.global_position = pos() + dir() * float(p.range) * tile()
	SkillExecutor.world().add_child(marker)
	proj.tree_exiting.connect(func(): if is_instance_valid(marker) and is_instance_valid(proj): marker.global_position = proj.global_position)
	hit_done = true
	if not actor is Player: return
	var recall_m := float(p.recall_mult)
	var pull: bool = p.get("pull", false)
	var lm := level_mult()
	player.recast[skill_id] = func():
		if not is_instance_valid(marker): return
		var a := marker.global_position
		var b := player.global_position
		Fx.line(a + Vector2(0, -6), b + Vector2(0, -6), Color(0.85, 0.9, 1.0), 4, 0.25)
		player.begin_action("skill")
		for tg in Combat.targets_in(Combat.line(a, b, 18), player.team):
			var h: HitInfo = player.make_hit(recall_m * lm, "skill")
			h.dir = (b - a).normalized()
			player.deal(tg, h)
			if pull and not tg.is_boss(): tg.global_position = b + (a - b).normalized() * 16
		marker.queue_free()
	player.get_tree().create_timer(float(p.window), false).timeout.connect(func(): player.recast.erase(skill_id))

# ---------- backstep_shot: 뒤로 도약 사격 ----------
func _start_backstep_shot() -> void:
	dur = float(p.duration) + 0.15
	st = {"fired": false}
	set_invuln(float(p.invuln))
	pose("dash", 1.5)

func _update_backstep_shot(dt: float) -> void:
	if t <= float(p.duration):
		actor.move_by(-dir() * float(p.distance) * tile() / float(p.duration) * dt)
	elif not st.fired:
		st.fired = true
		var n := int(p.get("count", 1))
		for i in n:
			var off := 0.0 if n == 1 else lerp(-12.0, 12.0, i / float(n - 1))
			var d := dir().rotated(deg_to_rad(off))
			var m := float(p.mult)
			var maker := func():
				actor.begin_action("skill")
				return hit(m)
			Projectile.spawn(SkillExecutor.world(), pos() + Vector2(0, -8), d, float(p.speed), float(p.range) * tile(), maker, {"team": actor.team, "visual": "arrow", "color": Color(1, 0.9, 0.6)})
		hit_done = true
	if t >= dur: finish()

# ---------- trap: 덫 화살 ----------
func _start_trap() -> void:
	dur = 0.3
	pose("attack", 1.5)
	var n := int(p.get("count", 1))
	for i in n:
		var side := dir().orthogonal() * (i - (n - 1) / 2.0) * 22
		var z := Zone.new()
		z.team = actor.team; z.radius = float(p.radius) * tile(); z.duration = float(p.duration); z.hits = 0
		z.trap = true; z.visual = "trap"; z.color = Color(0.9, 0.8, 0.4)
		var m := float(p.mult)
		z.hit_maker = func(_v):
			actor.begin_action("skill")
			return hit(m)
		z.global_position = pos() + dir() * float(p.distance) * tile() + side
		SkillExecutor.world().add_child(z)
	hit_done = true

# ---------- aimed_shot: 관통 저격 ----------
func _start_aimed_shot() -> void:
	dur = float(p.aim) + 0.25
	st = {"fired": false}
	pose("charge", 1.0)

func _update_aimed_shot(_dt: float) -> void:
	if actor is Player: player.velocity = Vector2.ZERO
	if not st.fired:
		if Engine.get_physics_frames() % 3 == 0:
			var c := pos() + Vector2(0, -8)
			Fx.line(c, c + dir() * float(p.range) * tile(), Color(1, 0.3, 0.3, 0.35 + 0.5 * t / float(p.aim)), 1, 0.06)
		if t >= float(p.aim):
			st.fired = true
			var m := float(p.mult)
			var maker := func():
				actor.begin_action("skill")
				return hit(m)
			Projectile.spawn(SkillExecutor.world(), pos() + Vector2(0, -8), dir(), float(p.speed), float(p.range) * tile(), maker, {"team": actor.team, "visual": "beam_star", "color": Color(1, 0.95, 0.8), "pierce": int(p.pierce)})
			Fx.shake(2.0)
			hit_done = true
	if t >= dur: finish()

# ---------- zone: 화살비, 별빛 낙하, 유성, 블랙홀 ----------
func _start_zone() -> void:
	dur = 0.35
	pose("attack", 1.2)
	var at := _target_point(float(p.distance))
	_make_zone(at, float(p.mult), float(p.radius) * tile() * float(p.get("radius_mult", 1.0) if p.get("visual", "") != "blackhole" else 1.0))
	if p.has("extra_meteors"):
		for i in int(p.extra_meteors):
			var off := Vector2.from_angle(TAU * i / 3.0 + 0.5) * 36
			var z := Zone.new()
			z.team = actor.team; z.radius = 18; z.delay = float(p.delay) + 0.25 + i * 0.15; z.duration = 0; z.hits = 1
			z.visual = "meteor"; z.color = Color(1, 0.55, 0.25)
			var m := float(p.mult) * 0.35
			z.hit_maker = func(_v):
				actor.begin_action("skill"); return hit(m)
			z.global_position = at + off
			SkillExecutor.world().add_child(z)
	hit_done = true

func _make_zone(at: Vector2, mult: float, radius: float) -> void:
	var z := Zone.new()
	z.team = actor.team
	z.radius = radius
	z.delay = float(p.get("delay", 0.0))
	z.duration = float(p.get("duration", 0.0))
	z.hits = int(p.get("hits", 1))
	z.visual = p.get("visual", "circle")
	z.color = {"arrows": Color(0.95, 0.9, 0.7, 0.7), "star": Color(1, 0.95, 0.7), "meteor": Color(1, 0.55, 0.25), "blackhole": Color(0.6, 0.3, 0.9)}.get(z.visual, Color(1, 1, 1, 0.6))
	if p.has("pull"):
		z.pull = float(p.pull) * float(p.get("radius_mult", 1.0))   # Lv5: 끌어당기는 범위·세기 2배
	var effects: Array = p.get("effects", [])
	z.hit_maker = func(_v):
		actor.begin_action("skill")
		return hit(mult)
	if p.has("end_mult"):
		var em := float(p.end_mult)
		z.on_end = func(zz):
			Fx.shake(3.0)
			SkillExecutor.burst(actor, zz.global_position, zz.radius * 1.2, em * level_mult(), Color(0.7, 0.4, 1.0), [], "skill")
	if p.has("after_zone"):
		var aft := float(p.after_zone)
		var m := mult
		z.on_end = func(zz):
			var lz := Zone.new()
			lz.team = actor.team; lz.radius = zz.radius; lz.duration = aft; lz.hits = 6; lz.visual = "light"; lz.color = Color(1, 0.95, 0.7, 0.6)
			lz.hit_maker = func(_v):
				actor.begin_action("skill"); return hit(0.5)
			lz.global_position = zz.global_position
			SkillExecutor.world().add_child(lz)
	z.global_position = at
	SkillExecutor.world().add_child(z)

# ---------- frozen_arrows: 멈춘 화살들 ----------
func _start_frozen_arrows() -> void:
	dur = 0.25
	hit_done = true
	if not actor is Player: return
	player.frozen_left = float(p.duration)
	player.frozen_mult = float(p.mult) * level_mult()
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(0.8, 0.95, 1))
	Fx.ring(pos(), 30, Color(0.8, 0.95, 1), 0.5, 1)

# ---------- chain: 번개 사슬 ----------
func _start_chain() -> void:
	dur = 0.3
	pose("attack", 1.5)
	var first := Combat.aim_target(pos(), dir(), 40, float(p.range) * tile())
	if first == null: first = Combat.nearest(pos(), float(p.range) * tile(), actor.team)
	if first == null:
		Fx.line(pos() + Vector2(0, -8), pos() + Vector2(0, -8) + dir() * 60, Color(0.8, 0.9, 1), 2, 0.15)
		return
	var hitlist := []
	var cur: Node = first
	var from := pos() + Vector2(0, -8)
	for i in int(p.targets):
		if cur == null: break
		hitlist.append(cur)
		var to: Vector2 = cur.global_position + Vector2(0, -8)
		_zigzag(from, to)
		actor.begin_action("skill")
		var h := hit(float(p.mult))
		h.dir = (to - from).normalized()
		actor.deal(cur, h)
		from = to
		cur = Combat.nearest(to, float(p.jump) * tile(), actor.team, hitlist)
	hit_done = true

func _zigzag(a: Vector2, b: Vector2) -> void:
	var prev := a
	for i in range(1, 5):
		var q := a.lerp(b, i / 4.0) + (Vector2(randf_range(-5, 5), randf_range(-5, 5)) if i < 4 else Vector2.ZERO)
		Fx.line(prev, q, Color(0.8, 0.9, 1.0), 2, 0.2)
		prev = q

# ---------- shield: 마력 보호막 ----------
func _start_shield() -> void:
	dur = 0.25
	hit_done = true
	if not actor is Player: return
	player.add_buff("mana_shield", float(p.duration), {}, [], {"left_amount": player.max_hp * float(p.amount), "break_mult": float(p.get("break_mult", 0.0)) * level_mult()})
	Fx.ring(pos() + Vector2(0, -8), 16, Color(0.6, 0.8, 1), 0.6, 2)

# ---------- blink ----------
func _start_blink() -> void:
	dur = 0.12
	hit_done = true
	var d: Vector2 = player.move_input if actor is Player and player.move_input != Vector2.ZERO else dir()
	if actor is Player: player.blink(d, float(p.distance) * tile())

# ---------- 크로노 스킬 ----------
func _start_slow_field() -> void:
	dur = 0.3
	hit_done = true
	var z := Zone.new()
	z.team = actor.team; z.radius = float(p.radius) * tile(); z.duration = float(p.duration); z.hits = 0
	z.visual = "slow"; z.follow = actor; z.apply_status = "slow"
	z.status_opts = {"speed_mult": 1.0 - float(p.slow)}
	z.status_opts_boss = {"speed_mult": 1.0 - float(p.boss_slow)}
	z.global_position = pos()
	SkillExecutor.world().add_child(z)
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(0.8, 0.95, 1))

func _start_rewind() -> void:
	dur = 0.3
	hit_done = true
	if not actor is Player: return
	var target_t := Clock.game_time - float(p.seconds)
	var pick: Array = []
	for h in player.history:
		if h[0] <= target_t: pick = h
	if pick.is_empty() and not player.history.is_empty(): pick = player.history[0]
	if pick.is_empty(): return
	for i in 6: Fx.line(pos() + Vector2(0, -8), pick[1] + Vector2(0, -8), Color(0.8, 0.95, 1, 0.5), 1, 0.3)
	player.global_position = pick[1]
	player.hp = minf(player.max_hp, pick[2])
	Fx.ring(pos() + Vector2(0, -8), 24, Color(0.8, 0.95, 1), 0.5, 2)
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(0.8, 0.95, 1))

func _start_echo() -> void:
	dur = 0.25
	hit_done = true
	if actor is Player: player.echo_left = float(p.duration)
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(0.8, 0.95, 1))

func _start_time_stop() -> void:
	dur = 0.3
	hit_done = true
	var view := Rect2(pos() - Vector2(340, 200), Vector2(680, 400))
	for e in Combat.enemies_of(actor.team):
		if not view.has_point(e.global_position): continue
		var d := float(p.boss_duration) if e.is_boss() else float(p.duration)
		e.statuses.add("time_stop", d, 0.0, {"force": true})
		e.accumulate = true
	Fx.ring(pos(), 200, Color(0.8, 0.95, 1), 0.6, 2)
	Fx.text(pos() + Vector2(0, -34), skill.name, Color(0.8, 0.95, 1))

func _start_chrono_burst() -> void:
	dur = 0.4
	var spent := float(skill.stamina) + player.data.stamina
	player.data.stamina = 0
	var mult := spent * float(p.per_stamina)
	Fx.hitstop("finisher")
	Fx.shake(4.0)
	SkillExecutor.burst(actor, pos(), float(p.radius) * tile(), mult * level_mult(), Color(0.8, 0.97, 1.0), [], "skill")
	hit_done = true
