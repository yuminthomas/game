class_name GhostActor
extends Node2D
## 크로노 '잔상'이 남기는 분신. 1초 전 자리에서 같은 스킬을 50% 위력으로 다시 쓴다.
## SkillRun 이 쓰는 행위자 인터페이스(aim_dir, team, make_hit, deal, begin_action, move_by)를 갖는다.

var player: Player
var team := "player"
var aim_dir := Vector2.DOWN
var facing := Vector2.DOWN
var is_ghost := true
var run: SkillRun
var sprite: Node2D

static func cast(p: Player, skill: Dictionary, level: int, at: Vector2, dir: Vector2, power: float) -> void:
	if p == null or not is_instance_valid(p) or p.dead: return
	var g := GhostActor.new()
	g.player = p
	g.aim_dir = dir
	g.facing = dir
	g.global_position = at
	SkillExecutor.world().add_child(g)
	g.sprite = p.look.make_ghost()
	g.add_child(g.sprite)
	g.sprite.position = Vector2.ZERO
	g.sprite.modulate = Color(0.8, 0.95, 1.0, 0.45)
	g.run = SkillRun.new(g, skill, level, power)
	g.run.start()

func _physics_process(delta: float) -> void:
	var dt := Clock.dt(delta, true)
	if dt <= 0: return
	if run == null or run.done:
		modulate.a -= dt * 3
		if modulate.a <= 0: queue_free()
		return
	run.update(dt)

func attack_power() -> float:
	return player.attack_power()

func make_hit(mult: float, kind := "skill") -> HitInfo:
	var h := player.make_hit(mult, kind)
	h.origin = global_position
	return h

func deal(t: Node, h: HitInfo) -> Dictionary:
	return player.deal(t, h)

func begin_action(kind: String) -> Dictionary:
	return player.begin_action(kind)

func move_by(v: Vector2) -> bool:
	global_position += v
	return false
