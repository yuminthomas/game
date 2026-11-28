class_name Enemy
extends Combatant
## 테스트 몬스터와 허수아비. AI 상태: 배회 → 추적 → 예고 → 공격 → 후퇴(쉬기), 그로기.
## 예고 중에는 테두리가 깜빡인다. 붉은 테두리 = 패링·가드 불가 (대시로만 피함).

enum A { IDLE, CHASE, TELEGRAPH, ATTACK, RECOVER, STAGGER }

var kind := "test_brute"
var def := {}
var ai := A.IDLE
var ai_t := 0.0
var cur_attack := {}
var attack_cd := 1.0
var spawn_pos := Vector2.ZERO
var sprite: Sprite2D
var telegraph_ring := 0.0
var respawn := true
var exp_given := false
var dps_log: Array = []      # 허수아비: [시각, 피해]
var label: Label
var move_speed := 50.0
var lunge_vel := Vector2.ZERO
var _attack_hit := false

static func create(kind_id: String, lv := -1, rank_id := "") -> Enemy:
	var e := Enemy.new()
	e.kind = kind_id
	e.def = Data.monsters[kind_id]
	e.level = lv if lv > 0 else int(e.def.level)
	e.rank = rank_id if rank_id != "" else e.def.get("rank", "normal")
	return e

func _ready() -> void:
	team = "enemy"
	add_to_group("enemy")
	hurt_radius = float(def.get("radius", 7))
	move_speed = float(def.get("speed", 50))
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new(); sh.radius = hurt_radius - 1
	col.shape = sh
	col.position = Vector2(0, -3)
	add_child(col)
	collision_layer = 2
	collision_mask = 4 | 2
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var holder := Node2D.new()
	add_child(holder)
	sprite = Sprite2D.new()
	sprite.texture = SpriteFactory.enemy_texture(kind)
	sprite.offset = Vector2(0, -16)
	sprite.use_parent_material = true
	holder.add_child(sprite)
	setup_visual(holder)
	if def.get("immovable", false):
		superarmor = 999
	spawn_pos = global_position
	recalc_stats()
	hp = max_hp
	facing = Vector2.DOWN
	if def.get("infinite", false):
		label = Label.new()
		label.add_theme_font_size_override("font_size", 9)
		label.add_theme_font_override("font", load("res://assets/fonts/Galmuri9.ttf"))
		label.position = Vector2(-30, -44)
		label.size = Vector2(60, 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
		add_child(label)

func recalc_stats() -> void:
	var m: Dictionary = Data.balance.monster
	var r: Dictionary = m.rank.get(rank, {"hp": 1, "atk": 1})
	max_hp = round(float(m.hp_base) * pow(float(m.hp_growth), level - 1) * float(r.hp) * float(def.get("hp_mult", 1)))
	defense_value = level * float(m.def_per_level)
	groggy_max = 0.0
	if rank != "normal": groggy_max = {"elite": 100.0, "midboss": 160.0, "boss": 220.0}.get(rank, 100.0)

func attack_power() -> float:
	var m: Dictionary = Data.balance.monster
	var r: Dictionary = m.rank.get(rank, {"hp": 1, "atk": 1})
	return float(m.atk_base) * pow(float(m.atk_growth), level - 1) * float(r.atk) * float(def.get("atk_mult", 1))

func display_name() -> String:
	var n: String = def.get("name", kind)
	if rank == "elite": n = "[정예] " + n
	elif rank == "midboss": n = "[중간보스] " + n
	elif rank == "boss": n = "[보스] " + n
	return n

func hittable() -> bool:
	return not dead

# ---------- 매 프레임 ----------
func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta)
	if dt <= 0: return
	if dead: return
	common_update(dt)
	if def.get("infinite", false):
		_dummy_update()
		return
	if statuses.disabled() or Clock.time_stopped:
		if ai in [A.TELEGRAPH, A.ATTACK]: _set_ai(A.RECOVER)
		velocity = Vector2.ZERO
		sprite.modulate = Color(0.8, 0.95, 1.0) if statuses.has("time_stop") or statuses.has("freeze") else Color.WHITE
		return
	sprite.modulate = Color.WHITE
	var tm := time_mult()
	var sdt := dt * tm
	ai_t += sdt
	attack_cd -= sdt
	var pl: Player = Game.player
	match ai:
		A.IDLE:
			velocity = Vector2.ZERO
			if pl and not pl.dead and pl.global_position.distance_to(global_position) < 160: _set_ai(A.CHASE)
		A.CHASE:
			if pl == null or pl.dead:
				_set_ai(A.IDLE); return
			var to := pl.global_position - global_position
			facing = to.normalized()
			_choose_attack(to.length())
			if ai != A.CHASE: return
			var want := 0.0 if to.length() < 22 else move_speed
			if statuses.no_move(): want = 0
			velocity = facing * want * tm
			move_and_slide()
		A.TELEGRAPH:
			velocity = Vector2.ZERO
			if pl and cur_attack.get("track", true): facing = (pl.global_position - global_position).normalized()
			if ai_t >= float(cur_attack.telegraph): _begin_attack()
		A.ATTACK:
			_update_attack(sdt)
		A.RECOVER:
			velocity = Vector2.ZERO
			if ai_t >= 0.45: _set_ai(A.CHASE)
	sprite.flip_h = facing.x < 0
	queue_redraw()

func _set_ai(s: int) -> void:
	ai = s
	ai_t = 0.0

func _choose_attack(dist: float) -> void:
	if attack_cd > 0: return
	var choices := []
	var total := 0.0
	for a in def.get("attacks", []):
		if dist <= float(a.range) + 6:
			choices.append(a); total += float(a.get("weight", 1))
	if choices.is_empty(): return
	var r := randf() * total
	for a in choices:
		r -= float(a.get("weight", 1))
		if r <= 0:
			cur_attack = a; break
	_set_ai(A.TELEGRAPH)

## 저스트 회피 판정용: 지금 준비 중인 공격이 target 에게 닿기까지 남은 시간
func threat_eta(target: Node) -> float:
	if ai != A.TELEGRAPH or cur_attack.get("projectile", false): return INF
	if target.global_position.distance_to(global_position) > float(cur_attack.range) + 12: return INF
	return (float(cur_attack.telegraph) - ai_t) / maxf(0.05, time_mult() * Clock.world_slow) + 0.06

func _begin_attack() -> void:
	_set_ai(A.ATTACK)
	_attack_hit = false
	var cd: Array = def.get("attack_cooldown", [1.0, 1.5])
	attack_cd = randf_range(float(cd[0]), float(cd[1]))
	if cur_attack.get("projectile", false):
		var dir := facing
		var maker := func():
			var h := HitInfo.make(self, float(cur_attack.damage), "enemy")
			h.knockback = 30
			return h
		var pr := Projectile.spawn(Game.world.entities, global_position + Vector2(0, -12), dir, 150, float(cur_attack.range) * 1.6, maker,
			{"team": "enemy", "visual": "enemy_bolt", "color": Color(0.9, 0.5, 1.0), "radius": 4.0})
		pr.add_to_group("enemy_projectile")
	else:
		lunge_vel = facing * (170.0 if cur_attack.id == "lunge" else 120.0)

func _update_attack(dt: float) -> void:
	if cur_attack.get("projectile", false):
		if ai_t > 0.3: _set_ai(A.RECOVER)
		return
	var active_end := 0.16
	if ai_t <= active_end:
		move_and_collide(lunge_vel * dt)
		if not _attack_hit:
			var pl: Player = Game.player
			var reach := 16.0 if cur_attack.id == "lunge" else 26.0
			var shape := Combat.arc(global_position + Vector2(0, -6), reach + 6, facing.angle(), 120 if cur_attack.id == "lunge" else 200)
			Fx.debug_shape(shape, Color(1, 0.2, 0.2))
			if pl and not pl.dead and Combat.overlaps(shape, pl.global_position + pl.hurt_offset(), pl.hurt_radius):
				_attack_hit = true
				var h := HitInfo.make(self, float(cur_attack.damage), "enemy")
				h.dir = facing
				h.can_parry = bool(cur_attack.get("parry", false))
				h.unblockable = bool(cur_attack.get("unblockable", false))
				h.knockback = 40 if not h.unblockable else 90
				pl.take_hit(h)
			if cur_attack.id == "heavy" and ai_t < dt * 1.5:
				Fx.swoosh(global_position + Vector2(0, -6), reach, facing.angle() - 1.7, facing.angle() + 1.7, Color(1, 0.3, 0.3), 4, 0.2)
			elif ai_t < dt * 1.5:
				Fx.swoosh(global_position + Vector2(0, -6), reach, facing.angle() - 1.0, facing.angle() + 1.0, Color(1, 0.9, 0.8), 3, 0.15)
	elif ai_t > active_end + 0.35:
		_set_ai(A.RECOVER)

func on_parried() -> void:
	_set_ai(A.STAGGER)
	ai = A.RECOVER
	ai_t = -0.6

func _on_stagger(_hit: HitInfo) -> void:
	if ai == A.TELEGRAPH and not is_boss() and rank == "normal":
		_set_ai(A.RECOVER)   # 일반 몬스터는 맞으면 공격 준비가 끊긴다

# ---------- 허수아비 ----------
func _dummy_update() -> void:
	hp = max_hp
	knock_vel = Vector2.ZERO
	var now := Clock.game_time
	dps_log = dps_log.filter(func(e): return now - e[0] <= 5.0)
	var total := 0.0
	for e in dps_log: total += e[1]
	var span := 5.0
	if not dps_log.is_empty(): span = clampf(now - dps_log[0][0], 1.0, 5.0)
	if label: label.text = "DPS %d" % int(total / span) if total > 0 else "허수아비 Lv%d" % level

func _apply_damage(dmg: float, hit: HitInfo, crit: bool) -> void:
	if def.get("infinite", false):
		dps_log.append([Clock.game_time, dmg])
		hp = max_hp + dmg   # 죽지 않게
	super._apply_damage(dmg, hit, crit)
	if not def.get("infinite", false) and not dead and ai == A.IDLE: _set_ai(A.CHASE)

func _die(hit: HitInfo) -> void:
	super._die(hit)
	collision_layer = 0
	Fx.burst(global_position + Vector2(0, -10), Color(0.8, 0.95, 1.0), 26, 70, 0.9)   # 빛 가루
	Fx.glow(global_position + Vector2(0, -10), 18, Color(0.8, 0.95, 1.0), 0.4)
	if not exp_given:
		exp_given = true
		var e := PlayerData.monster_exp(level, rank, Game.data.level)
		Game.data.gain_exp(e, true)
		Fx.text(global_position + Vector2(0, -26), "+%d EXP" % int(e), Color(0.7, 1.0, 0.7))
		LootDrop.roll_drops(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): visible = false)
	if respawn:
		get_tree().create_timer(4.0, false).timeout.connect(_respawn)

func _respawn() -> void:
	if not is_inside_tree(): return
	dead = false
	exp_given = false
	statuses.clear()
	groggy_value = 0
	global_position = spawn_pos
	recalc_stats()
	hp = max_hp
	modulate.a = 1.0
	visible = true
	collision_layer = 2
	_set_ai(A.IDLE)
	Fx.burst(global_position + Vector2(0, -10), Color(0.7, 0.5, 1.0), 16, 50, 0.6)

func _draw() -> void:
	if dead: return
	# 예고 표시
	if ai == A.TELEGRAPH:
		var k := ai_t / maxf(0.01, float(cur_attack.telegraph))
		var red: bool = cur_attack.get("unblockable", false)
		var col := Color(1, 0.15, 0.15) if red else Color(1, 0.95, 0.6)
		var blink := 0.5 + 0.5 * sin(ai_t * 40.0)
		draw_arc(Vector2(0, -14 - air_height), 14, 0, TAU, 20, Color(col.r, col.g, col.b, 0.4 + 0.5 * blink), 2.0 if red else 1.0)
		if not cur_attack.get("projectile", false):
			var reach := 22.0 if cur_attack.id == "lunge" else 30.0
			var pts := PackedVector2Array([Vector2.ZERO])
			var half := deg_to_rad(60.0 if cur_attack.id == "lunge" else 100.0)
			for i in 9: pts.append(Vector2.from_angle(facing.angle() - half + half * 2 * i / 8.0) * reach * (0.5 + 0.5 * k))
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.15 + 0.15 * k))
		else:
			draw_line(Vector2(0, -12), facing * 60 * k + Vector2(0, -12), Color(0.9, 0.5, 1.0, 0.5), 1)
	# 그림자
	draw_set_transform(Vector2(0, -1), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, hurt_radius, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	# 머리 위 작은 HP 바 (일반·정예)
	if not def.get("infinite", false) and (hp < max_hp or rank != "normal") and not is_boss():
		var w := 20.0 if rank == "normal" else 28.0
		var y := -36.0 - air_height
		draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 4), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2, y, w * hp / max_hp, 2), Color(0.9, 0.25, 0.25))
		if groggy_max > 0:
			draw_rect(Rect2(-w / 2, y + 3, w * groggy_value / groggy_max, 1), Color(1, 0.85, 0.2))
	# 상태 아이콘 (작은 점)
	var i := 0
	for s in statuses.icons():
		draw_rect(Rect2(-12 + i * 5, -44 - air_height, 4, 4), Color(Data.statuses[s.id].color))
		i += 1
