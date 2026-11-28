class_name HitInfo
extends RefCounted
## 한 번의 타격 정보. 피해 파이프라인(Combatant.take_hit → Combat.compute)이 이것만 보고 처리한다.

var attacker: Node = null        # Combatant 또는 null
var team := "player"
var base_attack := 0.0            # 공격자 공격력 스냅샷
var mult := 1.0                   # 스킬/콤보 배율
var kind := "basic"               # basic, finisher, charge, skill, dash, counter, proc, dot, enemy
var skill_id := ""
var crit_forced := false
var crit_bonus := 0.0             # 추가 치명타 확률
var bonus := 0.0                  # 추가 피해 % 합 (가산)
var groggy := 1.0                 # 그로기 누적량
var stamina_gain := 0.0           # 적중 시 공격자 기력 획득
var statuses: Array = []          # [{status, duration}]
var knockback := 40.0
var dir := Vector2.RIGHT
var origin := Vector2.ZERO        # 공격 시작점 (뒤치기 판정)
var can_parry := false            # 적 근접 공격: 패링 가능
var unblockable := false          # 붉은 테두리: 패링·가드 불가
var projectile := false
var hitstop := "normal"
var shake = null                  # 문자열(Data shake 키) 또는 숫자
var launch := 0.0                 # 띄우기 시간
var ignore_defense := false
var no_crit := false
var silent := false               # 숫자·연출 없음
var tags := {}

static func make(attacker_node: Node, multiplier: float, hit_kind := "basic") -> HitInfo:
	var h := HitInfo.new()
	h.attacker = attacker_node
	h.mult = multiplier
	h.kind = hit_kind
	if attacker_node != null:
		h.team = attacker_node.team
		h.base_attack = attacker_node.attack_power()
		h.origin = attacker_node.global_position
	return h
