class_name Player
extends Combatant
## 플레이어: 상태 머신(대기, 이동, 공격, 차지, 대시, 패링, 피격, 스킬, 죽음), 방어 행동, 기력, 무기 고유 효과.
## 수치는 전부 data/balance.json 의 control 항목에서 읽는다.

enum S { IDLE, MOVE, ATTACK, CHARGE, DASH, PARRY, HIT, SKILL, DEAD }

signal state_changed(s: int)
signal just_dodged
signal parried

var data: PlayerData
var look: LayeredCharacter
var attacks: PlayerAttacks
var state := S.IDLE
var state_t := 0.0
var aim_dir := Vector2.DOWN
var move_input := Vector2.ZERO
var spawn_point := Vector2.ZERO

# 대시
var dash_charges := 2.0
var dash_dir := Vector2.ZERO
var dash_t := 0.0
var dash_start := -99.0
var dash_end := -99.0
var dash_just_used := false
var dash_hit: Array = []
var ghost_t := 0.0
var dash_speed_override := 0.0

# 패링·가드
var parry_cd := 0.0
var parry_t := 0.0

# 다음 공격 보정
var next_attack_crit := false
var post_parry_counter := false
var just_dodge_bonus := false
var all_crit_until := -1.0
var action := {}               # 현재 행동(스윙/스킬)의 보정 {id, crit, bonus}
var _action_id := 0
var _stamina_action := -1

# 기력·회복
var last_combat := -99.0
var heal_over_time: Array = []  # [{per_sec, left}]
var potion_slow_t := 0.0
var hit_stun := 0.0

# 스킬
var skill_run: SkillRun = null
var cooldowns := {}             # skill_id -> 남은 초
var skill_charges := {}         # skill_id -> 남은 사용 횟수 (Lv5 연속 사용)
var buffs: Array = []           # {id, left, mods, flags, on_hit_status, data}
var cooldown_total := {}        # skill_id -> 전체 쿨타임 (HUD 표시용)
var recast := {}                # skill_id -> 다시 누르면 실행할 Callable
var history: Array = []         # 되감기용 [time, pos, hp]
var _hist_t := 0.0

# 무기 고유 효과 상태
var steal_stacks := 0
var steal_left := 0.0
var hit_counter := 0
var stars := 0
var crystals := 0
var revive_ready_at := 0.0
var marked: Array = []
var move_boost_left := 0.0
var clones: Array = []
var clone_left := 0.0
var frozen_arrows: Array = []
var frozen_left := 0.0
var frozen_mult := 1.0
var echo_left := 0.0

func _ready() -> void:
	team = "player"
	data = Game.data
	hurt_radius = 6.0
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new(); shape.radius = 5.0
	col.shape = shape
	col.position = Vector2(0, -3)
	add_child(col)
	collision_layer = 1
	collision_mask = 4         # 지형만
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	look = LayeredCharacter.new()
	add_child(look)
	setup_visual(look)
	attacks = PlayerAttacks.new(self)
	spawn_point = global_position
	dash_charges = max_dash_charges()
	refresh_look()
	data.changed.connect(_on_data_changed)
	data.leveled_up.connect(_on_level_up)
	max_hp = data.max_hp()
	hp = data.hp if data.hp > 1 else max_hp
	Game.player = self

func _on_data_changed(what: String) -> void:
	if what in ["equipment", "stats", "skills"]:
		max_hp = data.max_hp()
		hp = minf(hp, max_hp)
		refresh_look()
		dash_charges = minf(dash_charges, max_dash_charges())

func _on_level_up(lv: int) -> void:
	max_hp = data.max_hp(); hp = max_hp
	Fx.text(global_position + Vector2(0, -30), "LEVEL UP!", Color(1, 0.9, 0.4))
	Fx.ring(global_position, 30, Color(1, 0.9, 0.4), 0.6, 3)
	Fx.burst(global_position + Vector2(0, -10), Color(1, 0.95, 0.6), 24, 90, 0.8)

func refresh_look() -> void:
	var eq := data.equipment
	var l := {"hair": data.appearance.hair, "cape": data.appearance.cape, "crystal": data.crystal_stage(),
		"weapon_id": data.weapon().get("id", "")}
	if eq.chest != null:
		var lk: Dictionary = Data.armor[eq.chest.id].get("look", {})
		l.armor_color = lk.get("color", "#a0a0a0"); l.cape_style = lk.get("cape", "default")
	if eq.helmet != null:
		var lk: Dictionary = Data.armor[eq.helmet.id].get("look", {})
		l.helmet_style = lk.get("layer", "hood"); l.helmet_color = lk.get("color", "#a0a0a0")
	if eq.gloves != null: l.gloves_color = Data.armor[eq.gloves.id].get("look", {}).get("color", "#8a6a3a")
	if eq.boots != null: l.boots_color = Data.armor[eq.boots.id].get("look", {}).get("color", "#4a3424")
	look.apply_look(l)

# ---------- 수치 ----------
func ctl(path: String, default = null):
	return Data.bal("control." + path, default)

func attack_power() -> float:
	return data.attack_power()

func damage_reduction() -> float:
	return data.damage_reduction()

func max_dash_charges() -> float:
	return float(ctl("dash.charges")) + float(data.class_data().traits.get("dash_charges", 0))

func is_in_combat() -> bool:
	return Clock.game_time - last_combat < float(Data.bal("stamina.combat_timeout"))

func mark_combat() -> void:
	last_combat = Clock.game_time

func gain_stamina(amount: float, apply_mult := true) -> void:
	if apply_mult: amount *= data.stamina_gain_mult()
	data.stamina = clampf(data.stamina + amount, 0, data.stamina_max())

func set_state(s: int) -> void:
	if state == S.SKILL and s != S.SKILL and skill_run != null:
		skill_run.interrupt()
		skill_run = null
	if state == S.CHARGE and s != S.CHARGE: attacks.end_charge()
	if state == S.ATTACK and s != S.ATTACK: attacks.end_attack()
	state = s
	state_t = 0.0
	state_changed.emit(s)

func can_act() -> bool:
	return not dead and not statuses.disabled()

# ---------- 메인 루프 ----------
func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta, true)
	if dt <= 0.0: return
	common_update(dt)
	data.hp = hp
	state_t += dt
	_timers(dt)
	if dead:
		_update_dead(dt)
		return
	move_input = InputManager.move_vector()
	if hit_stun > 0:
		hit_stun -= dt
		velocity = velocity.move_toward(Vector2.ZERO, 900 * dt)
		move_and_slide()
		if hit_stun <= 0 and state == S.HIT: set_state(S.IDLE)
		return
	if statuses.disabled():
		velocity = Vector2.ZERO
		look.play("hit", 0.5)
		return
	_handle_global_inputs()
	match state:
		S.IDLE, S.MOVE: _update_free(dt)
		S.ATTACK: attacks.update_attack(dt)
		S.CHARGE: attacks.update_charge(dt)
		S.DASH: _update_dash(dt)
		S.PARRY: _update_parry(dt)
		S.SKILL: _update_skill(dt)
		S.HIT: set_state(S.IDLE)
	move_and_slide()
	look.set_facing(facing)

func _timers(dt: float) -> void:
	var mx := max_dash_charges()
	if dash_charges < mx:
		dash_charges = minf(mx, dash_charges + dt / float(ctl("dash.recharge")))
	parry_cd = maxf(0, parry_cd - dt)
	for k in cooldowns.keys():
		cooldowns[k] -= dt
		if cooldowns[k] <= 0: cooldowns.erase(k)
	# 기력: 전투 밖에서 초당 5, 최대 50까지
	if not is_in_combat() and data.stamina < float(Data.bal("stamina.regen_cap")):
		data.stamina = minf(float(Data.bal("stamina.regen_cap")), data.stamina + float(Data.bal("stamina.regen_out_of_combat")) * dt)
	# 지속 회복
	for h in heal_over_time:
		var step := minf(dt, h.left)
		heal(h.per_sec * step, false)
		h.left -= dt
	heal_over_time = heal_over_time.filter(func(h): return h.left > 0)
	potion_slow_t = maxf(0, potion_slow_t - dt)
	_update_buffs(dt)
	# 되감기 기록 (0.1초마다, 3초 분량)
	_hist_t += dt
	if _hist_t >= 0.1:
		_hist_t = 0
		history.push_back([Clock.game_time, global_position, hp])
		while history.size() > 40: history.pop_front()

func _handle_global_inputs() -> void:
	if InputManager.consume("item_potion"): use_potion()
	if InputManager.consume("item_herb"): use_consumable("herb_bundle")
	if InputManager.consume("item_candy"): use_consumable("stamina_candy")
	if InputManager.consume("interact"): _interact()
	for slot in ["slot_skill_1", "slot_skill_2", "slot_skill_3", "slot_skill_4", "slot_chrono_1", "slot_chrono_2"]:
		if InputManager.buffered(slot) and _can_start_skill():
			var sid := data.slot_skill(slot)
			if sid == "":
				InputManager.consume(slot)
				continue
			# 같은 스킬을 다시 누르면 처리하는 동작 (창 투척 회수 등)
			if recast.has(sid) and recast[sid].is_valid():
				InputManager.consume(slot)
				var cb: Callable = recast[sid]
				recast.erase(sid)
				cb.call()
				continue
			var err := SkillExecutor.try_start(self, sid, slot)
			InputManager.consume(slot)
			if err != "": Fx.text(global_position + Vector2(0, -32), err, Color(1, 0.6, 0.6))
			break
	if InputManager.buffered("dash") and _can_dash():
		InputManager.consume("dash")
		start_dash()
	if InputManager.buffered("parry") and _can_parry():
		InputManager.consume("parry")
		start_parry()

func _can_start_skill() -> bool:
	match state:
		S.IDLE, S.MOVE, S.CHARGE: return true
		S.ATTACK: return true                    # 스킬 캔슬: 기본 공격 도중 즉시 연결
		S.DASH: return state_t > 0.05
	return false

func _can_dash() -> bool:
	if dash_charges < 1.0: return false
	match state:
		S.IDLE, S.MOVE, S.CHARGE, S.PARRY: return true
		S.ATTACK: return attacks.hit_done       # 대시 캔슬: 타격 판정이 나간 뒤부터
		S.SKILL: return skill_run != null and skill_run.cancel_ok()
	return false

func _can_parry() -> bool:
	return parry_cd <= 0 and state in [S.IDLE, S.MOVE, S.CHARGE] or (parry_cd <= 0 and state == S.ATTACK and attacks.hit_done)

# ---------- 이동 ----------
func current_move_speed() -> float:
	var sp := data.move_speed() * statuses.speed_mult()
	if potion_slow_t > 0: sp *= 1.0 - float(Data.bal("potion.move_slow"))
	if move_boost_left > 0: sp *= 1.0 + float(data.weapon_unique().get("params", {}).get("move", 0.2))
	if steal_left > 0: sp *= 1.0 + steal_stacks * 0.02
	return sp

func _update_free(dt: float) -> void:
	if InputManager.buffered("attack"):
		if Clock.game_time - dash_end <= float(ctl("dash.attack_window")):
			InputManager.consume("attack")
			attacks.start_dash_attack()
			return
		InputManager.consume("attack")
		attacks.start_combo()
		return
	var mv := move_input
	if statuses.no_move(): mv = Vector2.ZERO
	var target := mv * current_move_speed()
	var acc := float(ctl("move_accel")) if mv != Vector2.ZERO else float(ctl("move_decel"))
	velocity = velocity.move_toward(target, acc * dt)
	if mv != Vector2.ZERO:
		facing = _snap8(mv)
		aim_dir = facing
		if state != S.MOVE: set_state(S.MOVE)
		look.play("run", current_move_speed() / 100.0 * 1.2)
	else:
		if state != S.IDLE: set_state(S.IDLE)
		look.play("idle", 0.6)

static func _snap8(v: Vector2) -> Vector2:
	return Vector2.from_angle(round(v.angle() / (PI / 4)) * (PI / 4))

# ---------- 대시 ----------
func start_dash(dir := Vector2.ZERO, speed := 0.0) -> void:
	if dir == Vector2.ZERO: dir = move_input if move_input != Vector2.ZERO else facing
	dash_charges -= 1.0
	dash_dir = dir.normalized()
	dash_speed_override = speed
	facing = _snap8(dash_dir)
	set_state(S.DASH)
	dash_t = 0.0
	dash_start = Clock.game_time
	dash_just_used = false
	dash_hit.clear()
	ghost_t = 0.0
	invuln_time = maxf(invuln_time, float(ctl("dash.invuln")))
	look.play("dash", 1.5)
	Fx.burst(global_position, Color(0.75, 0.95, 1.0), 6, 40, 0.3)
	mark_combat_if_near()
	# 적 공격이 0.12초 안에 닿을 예정이었으면 저스트 회피
	if _threat_within(float(ctl("just_dodge.window"))): trigger_just_dodge()

func mark_combat_if_near() -> void:
	if Combat.nearest(global_position, 120) != null: mark_combat()

func _threat_within(window: float) -> bool:
	for e in Game.enemies():
		if e.has_method("threat_eta") and e.threat_eta(self) <= window: return true
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		var to: Vector2 = global_position - p.global_position
		if to.length() <= p.velocity.length() * window + 8 and p.velocity.dot(to) > 0: return true
	return false

func _update_dash(dt: float) -> void:
	dash_t += dt
	var sp := dash_speed_override if dash_speed_override > 0 else float(ctl("dash.speed"))
	velocity = dash_dir * sp
	ghost_t -= dt
	if ghost_t <= 0:
		ghost_t = float(ctl("dash.duration")) / 3.0
		_spawn_ghost()
	if data.crystal_stage() >= 3 and randf() < 0.5:
		Fx.burst(global_position + Vector2(0, -10), Color(0.75, 0.95, 1.0), 1, 30, 0.4)
	# 반딧불: 대시로 지나간 자리의 적에게 피해
	var u := data.weapon_unique()
	if u.get("type", "") == "dash_trail_damage":
		for t in Combat.targets_in(Combat.circle(global_position, 10), team):
			if t in dash_hit: continue
			dash_hit.append(t)
			begin_action("proc")
			deal(t, make_hit(float(u.params.mult), "proc"))
		Fx.burst(global_position, Color(0.7, 1.0, 0.5), 2, 20, 0.5)
	if dash_t >= float(ctl("dash.duration")):
		dash_end = Clock.game_time
		velocity = dash_dir * float(ctl("move_speed")) * 0.5
		set_state(S.IDLE)
		if InputManager.buffered("attack"):
			InputManager.consume("attack")
			attacks.start_dash_attack()

func _spawn_ghost() -> void:
	var g := look.make_ghost()
	get_parent().add_child(g)
	g.global_position = global_position
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.25)
	tw.tween_callback(g.queue_free)

func trigger_just_dodge() -> void:
	if dash_just_used: return
	dash_just_used = true
	Clock.slow_world(float(ctl("just_dodge.slow_scale")), float(ctl("just_dodge.slow_duration")))
	gain_stamina(float(ctl("just_dodge.stamina")))
	Fx.ring(global_position + Vector2(0, -8), 26, Color(0.75, 0.95, 1.0), 0.6, 2)
	Fx.text(global_position + Vector2(0, -34), "저스트 회피", Color(0.75, 0.95, 1.0))
	var u := data.weapon_unique()
	match u.get("type", ""):
		"just_dodge_next_attack": just_dodge_bonus = true
		"just_dodge_all_crit": all_crit_until = Clock.game_time + float(u.params.duration)
	mark_combat()
	just_dodged.emit()

# ---------- 패링·가드 (활: 물러나기 사격, 지팡이: 짧은 순간이동) ----------
func parry_window() -> float:
	return float(ctl("parry.window")) + float(data.class_data().traits.get("parry_window_bonus", 0.0))

func start_parry() -> void:
	parry_cd = float(ctl("parry.cooldown"))
	match data.class_data().traits.get("parry_replacement", ""):
		"backstep_shot":
			attacks.backstep_shot(); return
		"blink":
			var dir := move_input if move_input != Vector2.ZERO else -facing
			blink(dir, 2.5 * 16)
			return
	set_state(S.PARRY)
	parry_t = 0.0
	velocity = Vector2.ZERO
	look.play("guard", 1.0, false)

func _update_parry(dt: float) -> void:
	parry_t += dt
	velocity = velocity.move_toward(Vector2.ZERO, 900 * dt)
	if parry_t >= parry_window() + float(ctl("parry.guard_duration")):
		set_state(S.IDLE)

func in_parry_window() -> bool:
	return state == S.PARRY and parry_t <= parry_window()

func in_guard() -> bool:
	return state == S.PARRY

func blink(dir: Vector2, dist: float) -> void:
	Fx.burst(global_position + Vector2(0, -8), Color(0.75, 0.9, 1.0), 10, 50, 0.3)
	var from := global_position
	var col := move_and_collide(dir.normalized() * dist, true)
	global_position += col.get_travel() if col else dir.normalized() * dist
	Fx.line(from + Vector2(0, -8), global_position + Vector2(0, -8), Color(0.75, 0.9, 1.0, 0.6), 2, 0.2)
	Fx.burst(global_position + Vector2(0, -8), Color(0.75, 0.9, 1.0), 10, 50, 0.3)
	invuln_time = maxf(invuln_time, 0.1)

# ---------- 피격 ----------
func _pre_hit(hit: HitInfo) -> String:
	if Game.god_mode and hit.kind != "dot":
		return "immune"
	if invuln_time > 0.0 and hit.kind != "dot":
		if state == S.DASH and Clock.game_time - dash_start <= float(ctl("just_dodge.window")) + 0.02:
			trigger_just_dodge()
		return "dodged"
	if hit.kind == "dot": return ""
	if skill_run != null and skill_run.absorbs_hit(hit):
		return "countered"
	if in_parry_window() and hit.can_parry and not hit.unblockable and not hit.projectile:
		_parry_success(hit)
		return "parried"
	return ""

func _damage_taken_mult(hit: HitInfo) -> float:
	var m := 1.0
	if hit.kind != "dot" and in_guard() and not hit.unblockable:
		m *= 1.0 - float(ctl("parry.guard_reduction"))
		Fx.sparks(global_position + Vector2(0, -10), -hit.dir, Color(0.7, 0.85, 1.0))
	if state == S.CHARGE and data.weapon_unique().get("type", "") == "charge_guard":
		m *= 1.0 - float(data.weapon_unique().params.reduction)
	if skill_run != null and skill_run.damage_taken_mult() < 1.0:
		m *= skill_run.damage_taken_mult()
	# 마력 보호막
	return m

func _parry_success(hit: HitInfo) -> void:
	var src = hit.attacker
	if src and is_instance_valid(src) and not src.dead:
		src.statuses.add("stagger", float(ctl("parry.enemy_stun")), 0.0, {"force": not src.is_boss()})
		if src.has_method("on_parried"): src.on_parried()
		src._add_groggy_raw(float(Data.bal("groggy.parry")) * data.groggy_mult())
	gain_stamina(float(ctl("parry.stamina")) + float(data.gear_mods().get("parry_stamina", 0.0)))
	next_attack_crit = bool(ctl("parry.next_attack_crit"))
	if data.class_data().traits.get("post_parry_counter", 0.0) > 0: post_parry_counter = true
	Fx.hitstop("parry")
	Fx.shake(2.0)
	var p := global_position + Vector2(0, -10) + facing * 8
	Fx.sparks(p, facing, Color(1, 0.95, 0.6))
	Fx.sparks(p, -facing, Color(0.8, 0.95, 1.0))
	Fx.glow(p, 18, Color(1, 1, 0.85), 0.2)
	Fx.text(global_position + Vector2(0, -34), "패링!", Color(1, 0.95, 0.6))
	mark_combat()
	parried.emit()

func _apply_damage(dmg: float, hit: HitInfo, crit: bool) -> void:
	# 마력 보호막이 먼저 흡수
	for b in buffs:
		if b.id == "mana_shield" and b.data.left_amount > 0:
			var absorbed := minf(dmg, b.data.left_amount)
			b.data.left_amount -= absorbed
			dmg -= absorbed
			Fx.number(global_position + Vector2(0, -24), absorbed, "block")
			if b.data.left_amount <= 0:
				b.left = 0
				if b.data.get("break_mult", 0.0) > 0:
					SkillExecutor.burst(self, global_position, 40, float(b.data.break_mult), Color(0.6, 0.8, 1))
	if dmg <= 0: return
	mark_combat()
	if hp - dmg <= 0 and _try_revive():
		dmg = hp - 1
	super._apply_damage(dmg, hit, crit)
	if dead: return
	if hit.kind != "dot":
		invuln_time = maxf(invuln_time, float(ctl("player_invuln_after_hit")))
		if superarmor <= 0 and state != S.SKILL and not (state == S.ATTACK and attacks.superarmor_now()):
			set_state(S.HIT)
			hit_stun = float(ctl("hit_react_time"))
			look.play("hit", 1.0, false)
			velocity = hit.dir * 120

func _try_revive() -> bool:
	var u := data.weapon_unique()
	if u.get("type", "") != "revive" or Clock.game_time < revive_ready_at: return false
	revive_ready_at = Clock.game_time + float(u.params.cooldown)
	call_deferred("_do_revive", float(u.params.hp))
	return true

func _do_revive(pct: float) -> void:
	hp = max_hp * pct
	invuln_time = 1.0
	Fx.text(global_position + Vector2(0, -34), "불사조!", Color(1, 0.6, 0.2))
	Fx.burst(global_position, Color(1, 0.6, 0.2), 30, 100, 0.8)

func _die(hit: HitInfo) -> void:
	super._die(hit)
	set_state(S.DEAD)
	velocity = Vector2.ZERO
	look.play("die", 1.0, false)
	Fx.burst(global_position + Vector2(0, -10), Color(0.8, 0.95, 1.0), 40, 60, 1.5)
	data.lose_exp_on_death()
	Game.notify("쓰러졌다… 시작 지점에서 다시 깨어난다", Color(0.8, 0.8, 0.9))

func _update_dead(dt: float) -> void:
	look.modulate.a = maxf(0.0, 1.0 - state_t / 1.2)
	if state_t >= 2.5: respawn()

func respawn() -> void:
	dead = false
	statuses.clear()
	global_position = spawn_point
	max_hp = data.max_hp(); hp = max_hp
	data.potion_charges = data.potion_max
	look.modulate.a = 1.0
	invuln_time = 1.0
	set_state(S.IDLE)

# ---------- 소모품 ----------
func use_potion() -> void:
	if data.potion_charges <= 0:
		Fx.text(global_position + Vector2(0, -32), "물약 없음", Color(1, 0.6, 0.6)); return
	if hp >= max_hp: return
	data.potion_charges -= 1
	var pct := float(Data.bal("potion.upgraded_heal_pct")) if data.potion_upgraded else float(Data.bal("potion.heal_pct"))
	var dur := float(Data.bal("potion.duration"))
	heal_over_time.append({"per_sec": max_hp * pct / dur, "left": dur})
	potion_slow_t = dur
	Fx.burst(global_position + Vector2(0, -12), Color(1, 0.4, 0.5), 10, 40, 0.6)
	data.changed.emit("inventory")

func use_consumable(id: String) -> void:
	if data.inv_consume.get(id, 0) <= 0:
		Fx.text(global_position + Vector2(0, -32), "%s 없음" % Data.consumables[id].name, Color(1, 0.6, 0.6)); return
	var c: Dictionary = Data.consumables[id]
	match id:
		"herb_bundle": heal_over_time.append({"per_sec": max_hp * float(c.heal_pct) / float(c.duration), "left": float(c.duration)})
		"stamina_candy": gain_stamina(float(c.stamina), false)
		"antidote":
			for s in c.cure: statuses.remove(s)
		"return_sand": global_position = spawn_point
		"oblivion_sand":
			var err := data.reset_stats(true)
			if err != "": Game.notify(err); return
			data.changed.emit("inventory"); return
	data.inv_consume[id] -= 1
	data.changed.emit("inventory")

func _interact() -> void:
	var best: Node = null
	var bd := 22.0
	for d in get_tree().get_nodes_in_group("loot"):
		var dd := global_position.distance_to(d.global_position)
		if dd < bd and d.needs_interact(): best = d; bd = dd
	if best: best.pickup(self)

# ---------- 스킬 (SkillRun 이 쓰는 행위자 인터페이스) ----------
var is_ghost := false

func move_by(v: Vector2) -> bool:
	return move_and_collide(v) != null

func set_pose(anim: String, speed := 1.0) -> void:
	look.play(anim, speed, false)

func _update_skill(dt: float) -> void:
	if skill_run == null:
		set_state(S.IDLE); return
	skill_run.update(dt)
	if skill_run != null and skill_run.done:
		skill_run = null
		set_state(S.IDLE)

func start_skill_state(run: SkillRun) -> void:
	set_state(S.SKILL)
	skill_run = run
	velocity = Vector2.ZERO

func add_buff(id: String, duration: float, mods := {}, flags := [], extra := {}) -> void:
	for b in buffs:
		if b.id == id:
			b.left = duration; b.mods = mods; b.flags = flags; b.data = extra
			_sync_buff_mods(); return
	buffs.append({"id": id, "left": duration, "mods": mods, "flags": flags, "data": extra})
	if "superarmor" in flags: superarmor += 1
	_sync_buff_mods()

func has_buff(id: String) -> bool:
	return buffs.any(func(b): return b.id == id)

func buff_data(id: String) -> Dictionary:
	for b in buffs:
		if b.id == id: return b.data
	return {}

func _update_buffs(dt: float) -> void:
	var changed := false
	for b in buffs:
		b.left -= dt
		if b.left <= 0:
			changed = true
			if "superarmor" in b.flags: superarmor = maxi(0, superarmor - 1)
	if changed:
		buffs = buffs.filter(func(b): return b.left > 0)
		_sync_buff_mods()
	if steal_left > 0:
		steal_left -= dt
		if steal_left <= 0:
			steal_stacks = 0; _sync_buff_mods()
	move_boost_left = maxf(0, move_boost_left - dt)
	if clone_left > 0:
		clone_left -= dt
		if clone_left <= 0:
			for c in clones: if is_instance_valid(c): c.queue_free()
			clones.clear()
		else:
			for i in clones.size():
				var c: Node2D = clones[i]
				if is_instance_valid(c):
					var off := Vector2.from_angle(TAU * i / clones.size() + Clock.game_time * 1.5) * 18
					c.global_position = c.global_position.lerp(global_position + off, minf(1.0, dt * 10))
	if frozen_left > 0:
		frozen_left -= dt
		if frozen_left <= 0: release_frozen_arrows()
	echo_left = maxf(0, echo_left - dt)

func _sync_buff_mods() -> void:
	var m := {}
	for b in buffs:
		for k in b.mods: m[k] = m.get(k, 0.0) + b.mods[k]
	if steal_stacks > 0:
		m["attack_speed"] = m.get("attack_speed", 0.0) + steal_stacks * 0.02
	data.set_buff_mods(m)

func release_frozen_arrows() -> void:
	frozen_left = 0
	for a in frozen_arrows:
		if is_instance_valid(a): a.release()
	frozen_arrows.clear()

# ---------- 피해 주기 ----------
## 행동(스윙 1회, 스킬 1회) 시작 시 '다음 공격' 보정을 소비해 묶어 둔다.
func begin_action(kind: String) -> Dictionary:
	_action_id += 1
	action = {"id": _action_id, "crit": false, "bonus": 0.0, "kind": kind}
	if kind in ["basic", "finisher", "charge", "dash", "skill", "counter"]:
		if next_attack_crit: action.crit = true; next_attack_crit = false
		if post_parry_counter:
			action.bonus += float(data.class_data().traits.get("post_parry_counter", 0.0)); post_parry_counter = false
		if just_dodge_bonus:
			action.bonus += float(data.weapon_unique().params.get("bonus", 0.0)); just_dodge_bonus = false
	if Clock.game_time < all_crit_until: action.crit = true
	return action

func make_hit(mult: float, kind := "basic") -> HitInfo:
	var h := HitInfo.make(self, mult, kind)
	h.dir = aim_dir
	h.crit_forced = action.get("crit", false)
	h.bonus = action.get("bonus", 0.0)
	h.tags["action"] = action.get("id", -1)
	var m := data.gear_mods()
	match kind:
		"basic", "finisher":
			h.groggy = float(Data.bal("groggy.basic"))
			h.stamina_gain = float(Data.bal("stamina.hit"))
		"charge":
			h.groggy = float(Data.bal("groggy.charge"))
			h.stamina_gain = float(Data.bal("stamina.charge_hit"))
			h.bonus += m.get("charge_damage", 0.0)
			h.hitstop = "finisher"
		"dash":
			h.groggy = float(Data.bal("groggy.basic"))
			h.stamina_gain = float(Data.bal("stamina.hit"))
			h.bonus += m.get("dash_attack_damage", 0.0)
		"skill":
			h.groggy = 3
		_:
			h.groggy = 0.5
	if kind == "finisher":
		h.hitstop = "finisher"
		h.knockback = float(Data.bal("knockback.finisher"))
		h.shake = "finisher"
	else:
		h.knockback = float(Data.bal("knockback.normal"))
	if data.weapon_class() == "greatsword" and kind in ["basic", "finisher", "charge", "skill"]:
		h.shake = "greatsword"
	if has_buff("poison_coat"):
		h.statuses.append({"status": "poison", "duration": 6, "bonus": float(buff_data("poison_coat").get("poison_mult", 1.0)) - 1.0})
	return h

## 모든 플레이어 피해는 여기를 지난다: 대상별 보정 → take_hit → 기력·무기 고유 효과.
func deal(target: Node, h: HitInfo) -> Dictionary:
	if target == null or target.dead: return {}
	var m := data.gear_mods()
	var u := data.weapon_unique()
	var ut: String = u.get("type", "")
	# 뒤치기
	if Combat.is_backstab(h.origin, target):
		h.crit_bonus += float(data.class_data().traits.get("backstab_crit", 0.0))
		if ut == "backstab_crit": h.crit_bonus += float(u.params.bonus)
		h.bonus += m.get("backstab_damage", 0.0)
		h.tags["backstab"] = true
	if target.is_boss(): h.bonus += m.get("boss_damage", 0.0)
	if ut == "execute" and target.hp / target.max_hp <= float(u.params.threshold): h.bonus += float(u.params.bonus)
	if ut == "bleed_master":
		for s in h.statuses:
			if s.status == "bleed": s["max_stacks"] = int(u.params.max_stacks); s["bonus"] = float(u.params.bonus)
	if target.statuses.has("airborne"): pass   # 띄우기 +20% 는 상태 보정에서 처리
	var r: Dictionary = target.take_hit(h)
	if r.get("result", "") != "hit": return r
	mark_combat()
	# 기력: 한 행동당 한 번
	if h.stamina_gain > 0 and h.tags.get("action", -2) != _stamina_action:
		_stamina_action = h.tags.get("action", -2)
		gain_stamina(h.stamina_gain)
	if r.get("crit", false) and ut == "crit_stamina": gain_stamina(float(u.params.amount), false)
	_unique_on_hit(target, h, r, ut, u)
	if h.kind in ["basic", "finisher", "charge", "dash", "skill"] and clone_left > 0 and not h.tags.get("clone", false):
		_clone_followups(target, h)
	if r.get("killed", false): on_kill(target, h)
	return r

func _unique_on_hit(target: Node, h: HitInfo, r: Dictionary, ut: String, u: Dictionary) -> void:
	if h.kind == "proc" or h.kind == "dot": return
	match ut:
		"steal_time":
			steal_stacks = mini(steal_stacks + 1, int(u.params.max_stacks))
			steal_left = float(u.params.duration)
			_sync_buff_mods()
		"on_hit_status":
			if randf() < float(u.params.chance): target.statuses.add(u.params.status, float(u.params.duration), h.base_attack)
		"nth_hit_lightning":
			hit_counter += 1
			if hit_counter % int(u.params.n) == 0 and not target.dead:
				Fx.line(target.global_position + Vector2(0, -80), target.global_position + Vector2(0, -6), Color(0.8, 0.9, 1.0), 3, 0.2)
				Fx.glow(target.global_position, 14, Color(0.8, 0.9, 1.0), 0.15)
				begin_action("proc")
				deal(target, make_hit(float(u.params.mult), "proc"))
		"first_hit_mark":
			if not target in marked:
				marked.append(target)
				target.statuses.add("mark", 5.0)
		"poison_pool":
			if h.tags.get("staff_bolt", false):
				SkillExecutor.poison_pool(self, target.global_position, float(u.params.radius), float(u.params.duration))
		"delayed_repeat":
			if h.projectile and h.tags.get("bow_shot", false) and not h.tags.get("repeat", false):
				var pos: Vector2 = target.global_position
				var mult := h.mult * float(u.params.mult)
				get_tree().create_timer(float(u.params.delay), false).timeout.connect(func():
					Fx.line(pos + Vector2(-30, -40), pos + Vector2(0, -6), Color(0.85, 0.85, 1.0), 2, 0.15)
					for t in Combat.targets_in(Combat.circle(pos, 10), team):
						begin_action("proc")
						var hh := make_hit(mult, "proc"); hh.tags["repeat"] = true
						deal(t, hh))
		"crystal_ring":
			if h.kind == "skill":
				crystals += 1
				if crystals >= int(u.params.count):
					crystals = 0
					SkillExecutor.burst(self, global_position, 56, float(u.params.mult), Color(0.75, 0.95, 1.0))

func _clone_followups(target: Node, h: HitInfo) -> void:
	var mult := float(buff_data("clones").get("mult", 0.4))
	for c in clones:
		if not is_instance_valid(c) or target.dead: continue
		var hh := make_hit(h.mult * mult, h.kind)
		hh.tags["clone"] = true
		hh.origin = c.global_position
		hh.silent = false
		Fx.swoosh(target.global_position + Vector2(0, -8), 10, randf() * TAU, randf() * TAU + 2, Color(0.4, 0.4, 0.6), 2, 0.12)
		deal(target, hh)

func on_kill(target: Node, _h: HitInfo) -> void:
	var u := data.weapon_unique()
	match u.get("type", ""):
		"kill_star_beam":
			stars = mini(stars + 1, int(u.params.stars))
			Fx.text(global_position + Vector2(0, -32), "★%d" % stars, Color(1, 0.95, 0.6))
		"execute":
			dash_charges = max_dash_charges()
	if skill_run != null: skill_run.on_kill(target)
