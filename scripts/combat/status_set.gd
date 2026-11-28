class_name StatusSet
extends RefCounted
## 상태이상 묶음. GDD 5-7. 지속 피해는 update() 가 [피해량, 상태id] 목록으로 돌려준다.

var list := {}       # id -> {left, stacks, atk, tick, max_stacks, bonus}
var owner_max_hp := 100.0
var is_boss := false

func add(id: String, duration: float, source_atk := 0.0, opts := {}) -> void:
	var def: Dictionary = Data.statuses.get(id, {})
	if def.is_empty(): return
	if is_boss and def.has("boss_replace") and not opts.get("force", false):
		id = def.boss_replace
		def = Data.statuses[id]
		if opts.has("boss_slow"): opts["speed_mult"] = 1.0 - float(opts.boss_slow)
	if duration <= 0: duration = float(def.get("duration", 1.0))
	var cur: Dictionary = list.get(id, {})
	if cur.is_empty():
		cur = {"left": duration, "stacks": 1, "atk": source_atk, "tick": float(def.get("tick", 0)), "max_stacks": int(opts.get("max_stacks", def.get("max_stacks", 1))), "bonus": float(opts.get("bonus", 0.0)), "speed_mult": float(opts.get("speed_mult", def.get("speed_mult", 1.0)))}
		list[id] = cur
	else:
		cur.left = maxf(cur.left, duration)
		cur.max_stacks = maxi(cur.max_stacks, int(opts.get("max_stacks", 1)))
		cur.stacks = mini(cur.stacks + 1, cur.max_stacks)
		cur.atk = maxf(cur.atk, source_atk)
		cur.bonus = maxf(cur.bonus, float(opts.get("bonus", 0.0)))

func has(id: String) -> bool:
	return list.has(id)

func remove(id: String) -> void:
	list.erase(id)

func clear() -> void:
	list.clear()

func disabled() -> bool:
	for id in list:
		if Data.statuses[id].get("disable", false): return true
	return false

func no_move() -> bool:
	return disabled() or list.has("root")

func speed_mult() -> float:
	var m := 1.0
	for id in list:
		if list[id].speed_mult < 1.0: m = minf(m, list[id].speed_mult)
	return m

func damage_taken_bonus() -> float:
	var b := 0.0
	for id in list: b += float(Data.statuses[id].get("damage_taken", 0.0))
	return b

## dt 만큼 진행. 지속 피해 [[amount, id], ...] 반환.
func update(dt: float) -> Array:
	var out := []
	for id in list.keys():
		var s: Dictionary = list[id]
		var def: Dictionary = Data.statuses[id]
		s.left -= dt
		if def.has("damage") and s.tick > 0:
			s["acc"] = s.get("acc", 0.0) + dt
			while s.acc >= s.tick:
				s.acc -= s.tick
				var dmg := 0.0
				var pct := float(def.damage.pct)
				if def.damage.source == "max_hp": dmg = owner_max_hp * pct
				else: dmg = s.atk * pct
				dmg *= s.stacks * (1.0 + s.bonus)
				out.append([dmg, id])
		if s.left <= 0: list.erase(id)
	return out

func icons() -> Array:
	var out := []
	for id in list:
		if not Data.statuses[id].get("hidden", false): out.append({"id": id, "left": list[id].left, "stacks": list[id].stacks})
	return out
