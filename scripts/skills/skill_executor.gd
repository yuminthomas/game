class_name SkillExecutor
## 스킬 시전 창구: 조건 확인(습득, 무기군, 쿨타임, 기력) → SkillRun 생성. 공용 연출 도우미도 여기 있다.

const DAMAGING := ["strike", "dash_strike", "spin", "multi_teleport", "beam", "aura", "leap", "charge_slam", "multi_slam",
	"teleport_behind", "projectile", "backstep_shot", "aimed_shot", "zone", "chain", "chrono_burst"]

static func params_for(skill: Dictionary, level: int) -> Dictionary:
	var p: Dictionary = skill.behavior.duplicate(true)
	if level >= int(Data.bal("skills.max_level", 5)):
		for k in skill.get("lv5", {}):
			if k == "effects":
				p["effects"] = p.get("effects", []) + skill.lv5.effects
			else:
				p[k] = skill.lv5[k]
		if p.has("effect_duration"):
			for e in p.get("effects", []): e.duration = p.effect_duration
	return p

static func cooldown_for(player: Player, skill: Dictionary, level: int) -> float:
	var cd := float(skill.cooldown) * (1.0 - player.data.cdr())
	if level >= 3: cd *= 1.0 - float(Data.bal("skills.lv3_cdr"))
	return cd

## 실패하면 이유 문자열, 성공하면 ""
static func try_start(player: Player, id: String, slot := "") -> String:
	var s: Dictionary = Data.skills.get(id, {})
	if s.is_empty(): return "없는 스킬"
	var lv := player.data.skill_level(id)
	if lv <= 0: return "배우지 않은 스킬"
	if s.cls != "chrono" and s.cls != player.data.weapon_class(): return "%s 스킬" % Data.class_name_ko(s.cls)
	var p := params_for(s, lv)
	var on_cd := player.cooldowns.has(id)
	if on_cd and int(player.skill_charges.get(id, 0)) <= 0: return "쿨타임"
	var cost := float(s.stamina)
	var u := player.data.weapon_unique()
	if u.get("type", "") == "free_skill" and randf() < float(u.params.chance):
		cost = 0.0
		Fx.text(player.global_position + Vector2(0, -40), "기력 소모 0", Color(0.8, 0.6, 1))
	if player.data.stamina < cost: return "기력 부족"
	player.data.stamina -= cost
	if s.behavior.type == "chrono_burst": cost = 0   # 남은 기력을 실행 시 전부 쓴다
	if on_cd:
		player.skill_charges[id] = int(player.skill_charges[id]) - 1
	else:
		var cd := cooldown_for(player, s, lv)
		player.cooldowns[id] = cd
		player.cooldown_total[id] = cd
		player.skill_charges[id] = int(p.get("charges", 1)) - 1
	player.mark_combat_if_near()
	player.begin_action("skill")
	var run := SkillRun.new(player, s, lv, 1.0, slot)
	run.start()
	if not run.done: player.start_skill_state(run)
	elif player.state == Player.S.ATTACK: player.set_state(Player.S.IDLE)
	# 크로노 '잔상': 1초 뒤 50% 위력으로 한 번 더 (피해 주는 스킬만)
	if player.echo_left > 0 and s.cls != "chrono" and s.behavior.type in DAMAGING:
		var pos := player.global_position
		var dir := player.aim_dir
		player.get_tree().create_timer(1.0, false).timeout.connect(func(): GhostActor.cast(player, s, lv, pos, dir, 0.5))
	return ""

# ---------- 공용 도우미 ----------
static func world() -> Node:
	return Game.world.entities

## 즉시 원형 폭발
static func burst(actor, pos: Vector2, radius: float, mult: float, col: Color, effects: Array = [], kind := "proc") -> void:
	Fx.ring(pos, radius, col, 0.35, 3)
	Fx.burst(pos, col, 18, 100, 0.45)
	Fx.glow(pos, radius * 0.7, col, 0.2)
	Fx.debug_shape(Combat.circle(pos, radius), Color(1, 0.6, 0.2))
	actor.begin_action(kind)
	for t in Combat.targets_in(Combat.circle(pos, radius), actor.team):
		var h: HitInfo = actor.make_hit(mult, kind)
		h.dir = (t.global_position - pos).normalized()
		for e in effects: h.statuses.append(e.duplicate())
		actor.deal(t, h)

static func delayed_blast(actor, pos: Vector2, radius: float, mult: float, delay: float, col: Color) -> void:
	var z := Zone.new()
	z.team = actor.team; z.radius = radius; z.delay = delay; z.duration = 0.0; z.hits = 1
	z.visual = "meteor"; z.color = col
	z.hit_maker = func(_t): return _proc_hit(actor, mult)
	z.global_position = pos
	world().add_child(z)

static func rain(actor, pos: Vector2, radius: float, count: int, mult: float, duration: float, delay := 0.0) -> void:
	var z := Zone.new()
	z.team = actor.team; z.radius = radius; z.delay = delay; z.duration = duration; z.hits = count
	z.visual = "arrows"; z.color = Color(0.95, 0.9, 0.7, 0.6)
	z.hit_maker = func(_t): return _proc_hit(actor, mult)
	z.global_position = pos
	world().add_child(z)

static func poison_pool(actor, pos: Vector2, radius: float, duration: float) -> void:
	var z := Zone.new()
	z.team = actor.team; z.radius = radius; z.duration = duration; z.hits = 0
	z.visual = "pool"; z.color = Color(0.4, 0.9, 0.3, 0.7)
	z.apply_status = "poison"
	z.global_position = pos
	world().add_child(z)

static func _proc_hit(actor, mult: float) -> HitInfo:
	actor.begin_action("proc")
	return actor.make_hit(mult, "proc")
