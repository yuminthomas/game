class_name Combat
## 피해 공식(GDD 6-2)과 판정 도형 질의. 모든 피해 계산은 compute() 한 곳에서 한다.

const FLASH_SHADER := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, flash_color.rgb, flash), c.a);
}
"""
static var _flash_shader: Shader

static func flash_material() -> ShaderMaterial:
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _flash_shader
	return m

## 최종 피해 = 공격력 × 배율 × (1 - 피해감소율) × 크로노포스 × 치명타 × 상태 보정 × 난수
## 반환: {damage, crit}
static func compute(hit: HitInfo, target: Node) -> Dictionary:
	var d: Dictionary = Data.balance.derived
	var pd: PlayerData = Game.data
	var dmg := hit.base_attack * hit.mult
	if not hit.ignore_defense and hit.kind != "dot":
		dmg *= 1.0 - target.damage_reduction()
	# 크로노포스 보정
	if hit.team == "player" and target.team != "player": dmg *= pd.chrono_mults()[0]
	elif target.team == "player": dmg *= pd.chrono_mults()[1]
	# 치명타 (플레이어 공격만)
	var crit := false
	if hit.team == "player" and hit.kind != "dot" and not hit.no_crit:
		crit = hit.crit_forced or randf() < minf(pd.crit_chance() + hit.crit_bonus, float(d.crit_cap))
		if crit: dmg *= pd.crit_damage()
	# 상태 보정 (표식·띄우기·그로기) + 추가 피해
	dmg *= 1.0 + target.statuses.damage_taken_bonus()
	dmg *= 1.0 + hit.bonus
	if hit.kind != "dot": dmg *= randf_range(float(d.random_min), float(d.random_max))
	return {"damage": maxf(1.0, round(dmg)), "crit": crit}

# ---------- 판정 도형 ----------
static func circle(c: Vector2, r: float) -> Dictionary:
	return {"type": "circle", "c": c, "r": r}

static func arc(c: Vector2, r: float, dir_angle: float, angle_deg: float) -> Dictionary:
	return {"type": "arc", "c": c, "r": r, "dir": dir_angle, "half": deg_to_rad(angle_deg) * 0.5}

static func line(a: Vector2, b: Vector2, w: float) -> Dictionary:
	return {"type": "line", "a": a, "b": b, "w": w}

static func overlaps(s: Dictionary, p: Vector2, r: float) -> bool:
	match s.type:
		"circle":
			return p.distance_to(s.c) <= s.r + r
		"arc":
			var dist := p.distance_to(s.c)
			if dist > s.r + r: return false
			if dist < r + 2: return true
			var diff: float = abs(angle_difference(s.dir, (p - s.c).angle()))
			return diff <= s.half + asin(clampf(r / dist, 0, 1))
		"line":
			return Geometry2D.get_closest_point_to_segment(p, s.a, s.b).distance_to(p) <= s.w * 0.5 + r
	return false

## team 이 아닌 쪽의 살아 있는 대상 중 도형에 닿는 것들
static func targets_in(s: Dictionary, attacker_team: String) -> Array:
	var out := []
	for n in Engine.get_main_loop().get_nodes_in_group("combatant"):
		if n.team == attacker_team or n.dead or not n.hittable(): continue
		if overlaps(s, n.global_position + n.hurt_offset(), n.hurt_radius): out.append(n)
	return out

static func enemies_of(team: String) -> Array:
	var out := []
	for n in Engine.get_main_loop().get_nodes_in_group("combatant"):
		if n.team != team and not n.dead and n.hittable(): out.append(n)
	return out

## 조준 보정: dir 기준 ±angle 안의 가장 가까운 적
static func aim_target(from: Vector2, dir: Vector2, angle_deg: float, max_range: float, team := "player") -> Node:
	var best: Node = null
	var best_d := max_range
	for n in enemies_of(team):
		var to: Vector2 = n.global_position - from
		var dd := to.length()
		if dd > best_d or dd < 1: continue
		if rad_to_deg(abs(dir.angle_to(to))) <= angle_deg:
			best = n; best_d = dd
	return best

static func nearest(from: Vector2, max_range: float, team := "player", exclude: Array = []) -> Node:
	var best: Node = null
	var best_d := max_range
	for n in enemies_of(team):
		if n in exclude: continue
		var dd := from.distance_to(n.global_position)
		if dd < best_d: best = n; best_d = dd
	return best

static func is_backstab(attacker_pos: Vector2, target: Node) -> bool:
	if not "facing" in target: return false
	var to_attacker = (attacker_pos - target.global_position).normalized()
	return target.facing.dot(to_attacker) < -0.3
