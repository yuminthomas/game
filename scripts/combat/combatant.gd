class_name Combatant
extends CharacterBody2D
## 플레이어와 몬스터의 공통 바탕. 피해 파이프라인, 상태이상, 그로기, 넉백, 번쩍임, 띄우기.

signal died(who: Combatant)
signal damaged(amount: float, hit: HitInfo)

var team := "enemy"
var level := 1
var rank := "normal"            # normal, elite, midboss, boss
var max_hp := 100.0
var hp := 100.0
var defense_value := 0.0
var hurt_radius := 6.0
var facing := Vector2.DOWN
var dead := false
var statuses := StatusSet.new()
var superarmor := 0              # 0보다 크면 슈퍼아머 (중첩 가능)
var invuln_time := 0.0           # 무적 (대시 등)
var groggy_value := 0.0
var groggy_max := 0.0            # 0 이면 그로기 게이지 없음
var groggy_idle := 0.0
var knock_vel := Vector2.ZERO
var air_height := 0.0            # 띄우기 표현용 높이
var flash_frames := 0
var visual: Node2D               # 번쩍임·높이를 적용할 그림 노드
var last_hit_time := -99.0
var time_stop_pending := 0.0     # 시간 정지 중 누적된 피해
var accumulate := false          # 크로노 '시간 정지': 피해를 모았다가 해제 시 한꺼번에

func _enter_tree() -> void:
	add_to_group("combatant")

func setup_visual(v: Node2D) -> void:
	visual = v
	visual.material = flash_material_cached()

func flash_material_cached() -> ShaderMaterial:
	return Combat.flash_material()

func is_boss() -> bool:
	return rank == "boss" or rank == "midboss"

func attack_power() -> float:
	return 10.0

func damage_reduction() -> float:
	return minf(defense_value / (defense_value + float(Data.bal("derived.dr_const"))), float(Data.bal("derived.dr_cap")))

func hittable() -> bool:
	return true

func hurt_offset() -> Vector2:
	return Vector2(0, -6)

func is_invulnerable() -> bool:
	return invuln_time > 0.0 or (team == "player" and Game.god_mode)

## 엔티티 고유 시간 배율 (둔화·시간 정지 포함)
func time_mult() -> float:
	var m := statuses.speed_mult()
	return m

# ---------- 피해 파이프라인 ----------
## 반환: {result: "hit"/"dodged"/"parried"/"guarded"/"immune", damage, crit, killed}
func take_hit(hit: HitInfo) -> Dictionary:
	if dead: return {"result": "immune", "damage": 0}
	var pre := _pre_hit(hit)
	if pre != "": return {"result": pre, "damage": 0}
	var r := Combat.compute(hit, self)
	var dmg: float = r.damage * _damage_taken_mult(hit)
	dmg = round(dmg)
	# 크로노 '시간 정지' 중이면 피해를 모아뒀다 해제 시 한꺼번에
	if accumulate and statuses.has("time_stop") and hit.team == "player":
		time_stop_pending += dmg
		Fx.number(global_position + Vector2(0, -20), dmg, "dot")
		return {"result": "hit", "damage": dmg, "crit": r.crit, "killed": false}
	_apply_damage(dmg, hit, r.crit)
	return {"result": "hit", "damage": dmg, "crit": r.crit, "killed": dead}

## 패링·가드·무적 처리용 (Player 가 재정의). 빈 문자열이면 맞는다.
func _pre_hit(hit: HitInfo) -> String:
	if is_invulnerable(): return "dodged"
	return ""

func _damage_taken_mult(_hit: HitInfo) -> float:
	return 1.0

func _apply_damage(dmg: float, hit: HitInfo, crit: bool) -> void:
	hp -= dmg
	last_hit_time = Clock.game_time
	damaged.emit(dmg, hit)
	var head := global_position + Vector2(0, -22 - air_height)
	if not hit.silent:
		if team == "player": Fx.number(head, dmg, "taken")
		elif hit.kind == "dot": Fx.number(head, dmg, "dot")
		else: Fx.number(head, dmg, "crit" if crit else "normal")
	if hit.kind != "dot":
		flash_frames = int(Data.bal("hit_flash_frames", 2)) + (1 if crit else 0)
		_hit_effects(hit, crit)
		for s in hit.statuses:
			statuses.add(s.status, float(s.get("duration", 0)), hit.base_attack, s)
		if hit.launch > 0 and not is_boss(): statuses.add("airborne", hit.launch)
		_add_groggy(hit)
		if superarmor <= 0 and not is_boss():
			knock_vel = hit.dir.normalized() * hit.knockback * 4.0
			_on_stagger(hit)
	if hp <= 0:
		hp = 0
		_die(hit)

func _hit_effects(hit: HitInfo, crit: bool) -> void:
	var p := global_position + hurt_offset()
	if hit.team == "player":
		Fx.hitstop("crit" if crit else hit.hitstop)
		if hit.shake != null: Fx.shake(hit.shake)
		Fx.sparks(p, hit.dir, Color(1, 0.9, 0.55) if not crit else Color(1, 0.8, 0.2))
		Fx.burst(p, Color(0.75, 0.95, 1.0), 4, 50, 0.35)   # 결정 조각
		Fx.glow(p, 10 if not crit else 16, Color(1, 1, 0.9), 0.12)
	else:
		Fx.burst(p, Color(1, 0.35, 0.35), 6, 60, 0.3)
		Fx.hitstop("normal")
		Fx.shake(1.5 if not hit.unblockable else 3.0)

func _add_groggy(hit: HitInfo) -> void:
	var g := hit.groggy
	if hit.team == "player": g *= Game.data.groggy_mult()
	_add_groggy_raw(g)

func _add_groggy_raw(g: float) -> void:
	if groggy_max <= 0 or statuses.has("groggy"): return
	groggy_value += g
	groggy_idle = 0.0
	if groggy_value >= groggy_max:
		groggy_value = 0.0
		statuses.add("groggy", float(Data.bal("groggy.duration")))
		Fx.text(global_position + Vector2(0, -30), "그로기!", Color(1, 0.85, 0.2))
		Fx.ring(global_position, 30, Color(1, 0.85, 0.2), 0.5, 3)

func _on_stagger(_hit: HitInfo) -> void:
	pass

func _die(_hit: HitInfo) -> void:
	dead = true
	died.emit(self)

func heal(amount: float, show := true) -> void:
	if dead or amount <= 0: return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if show and hp - before >= 1: Fx.number(global_position + Vector2(0, -24), hp - before, "heal")

## 매 프레임 공통 처리. 이동 가능한 dt 를 받는다.
func common_update(dt: float) -> void:
	if invuln_time > 0: invuln_time -= dt
	statuses.owner_max_hp = max_hp
	statuses.is_boss = is_boss()
	var was_stopped := statuses.has("time_stop")
	for t in statuses.update(dt):
		var h := HitInfo.new()
		h.team = "dot"; h.kind = "dot"; h.base_attack = t[0]; h.mult = 1.0; h.ignore_defense = true
		h.knockback = 0
		if not dead:
			var r := Combat.compute(h, self)
			_apply_damage(r.damage, h, false)
	if was_stopped and not statuses.has("time_stop"): accumulate = false
	if not statuses.has("time_stop") and time_stop_pending > 0 and not dead:
		var h := HitInfo.new()
		h.team = "player"; h.kind = "proc"; h.base_attack = time_stop_pending; h.ignore_defense = true; h.no_crit = true
		time_stop_pending = 0
		var r := Combat.compute(h, self)
		Fx.ring(global_position, 24, Color(0.8, 0.95, 1), 0.4, 3)
		_apply_damage(r.damage, h, true)
	# 그로기 감소
	if groggy_max > 0 and groggy_value > 0:
		groggy_idle += dt
		if groggy_idle > float(Data.bal("groggy.decay_delay")):
			groggy_value = maxf(0, groggy_value - groggy_max * float(Data.bal("groggy.decay_per_sec")) * dt)
	# 띄우기 높이
	var target_h := float(Data.bal("control.airborne_height")) if statuses.has("airborne") else 0.0
	air_height = move_toward(air_height, target_h, 140 * dt)
	# 넉백
	if knock_vel.length() > 1:
		var col := move_and_collide(knock_vel * dt)
		if col: knock_vel = Vector2.ZERO
		knock_vel = knock_vel.lerp(Vector2.ZERO, minf(1.0, float(Data.bal("knockback.decay")) * dt))
	_update_visual()

func _update_visual() -> void:
	if visual == null: return
	if visual.material:
		var f := 1.0 if flash_frames > 0 else 0.0
		(visual.material as ShaderMaterial).set_shader_parameter("flash", f)
	if flash_frames > 0 and not Clock.in_hitstop(): flash_frames -= 1
	visual.position.y = -air_height
