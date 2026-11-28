class_name PlayerData
extends RefCounted
## 플레이어 상태(로직). 화면 표시와 분리되어 있어 멀티플레이·저장에 그대로 쓸 수 있다. GDD 6장.

signal changed(what: String)   # "stats", "inventory", "equipment", "skills", "exp", "level"
signal leveled_up(level: int)
signal item_logged(text: String, color: Color)

const STATS := ["str", "dex", "int", "vit"]

var level := 1
var exp := 0.0
var stat_points := 0
var stats := {"str": 5, "dex": 5, "int": 5, "vit": 5}
var free_reset_used := false
var hp := 1.0
var stamina := 0.0
var potion_charges := 3
var potion_max := 3
var potion_upgraded := false
var appearance := {"hair": 0, "cape": 0}

var inv_equip: Array = []           # 48칸, null 허용
var inv_consume := {}               # id -> 개수
var inv_material := {}              # id -> 개수
var inv_books := {}                 # "tier:cls" -> 개수
var equipment := {"weapon": null, "helmet": null, "chest": null, "gloves": null, "boots": null, "ring1": null, "ring2": null, "necklace": null}
var cores: Array = [null, null, null, null, null, null]   # {region, level}
var skills := {}                    # skill_id -> 레벨
var slots := {}                     # cls -> [skill_id x4] (무기군별 따로)
var chrono_slots := ["", ""]
var mastery := {}                   # cls -> {level, exp}
var region_requirement := 0         # 현재 지역 요구 크로노포스
var buff_mods := {}                 # 전투 중 버프 (Player 노드가 set_buff_mods 로 넣어 준다)
var _mods_cache := {}
var _mods_valid := false

func _init() -> void:
	changed.connect(func(_w): _mods_valid = false)
	inv_equip.resize(int(Data.items_cfg.get("inventory", {}).get("equip_slots", 48)))
	for c in Data.CLASSES:
		slots[c] = ["", "", "", ""]
		mastery[c] = {"level": 1, "exp": 0.0}
	stats.str = int(Data.bal("stats.start", 5)); stats.dex = stats.str; stats.int = stats.str; stats.vit = stats.str
	potion_max = int(Data.bal("potion.charges", 3)); potion_charges = potion_max

func new_game() -> void:
	equipment.weapon = Items.make_weapon("sword_old_meridian")
	equipment.weapon.new = false
	hp = max_hp(); stamina = 0.0

# ---------- 장비 ----------
func weapon() -> Dictionary:
	return equipment.weapon if equipment.weapon != null else {}

func weapon_class() -> String:
	var w := weapon()
	return Data.weapons[w.id].class if not w.is_empty() else "sword"

func weapon_unique() -> Dictionary:
	var w := weapon()
	if w.is_empty(): return {}
	return Data.weapons[w.id].get("unique", {})

func can_equip(it: Dictionary) -> String:
	if it.is_empty(): return "아이템 없음"
	if level < int(it.level): return "레벨이 부족합니다 (요구 %d)" % it.level
	return ""

func equip_slot_for(it: Dictionary) -> String:
	if it.slot == "ring":
		if equipment.ring1 == null: return "ring1"
		if equipment.ring2 == null: return "ring2"
		return "ring1"
	return it.slot

## 인벤토리 칸 index 의 장비를 장착. 기존 장비는 그 칸으로 돌아간다.
func equip_from_inventory(index: int, target_slot := "") -> String:
	var it = inv_equip[index]
	if it == null: return "빈 칸"
	var why := can_equip(it)
	if why != "": return why
	var slot := target_slot if target_slot != "" else equip_slot_for(it)
	if not _slot_accepts(slot, it): return "맞지 않는 칸"
	var old = equipment[slot]
	equipment[slot] = it
	it.new = false
	inv_equip[index] = old
	changed.emit("equipment"); changed.emit("inventory"); changed.emit("stats")
	return ""

func unequip(slot: String) -> String:
	if slot == "weapon": return "무기는 비울 수 없습니다 (다른 무기로 교체)"
	if equipment[slot] == null: return ""
	var idx := inv_equip.find(null)
	if idx < 0: return "인벤토리가 가득 찼습니다"
	inv_equip[idx] = equipment[slot]
	equipment[slot] = null
	changed.emit("equipment"); changed.emit("inventory"); changed.emit("stats")
	return ""

func _slot_accepts(slot: String, it: Dictionary) -> bool:
	if slot.begins_with("ring"): return it.slot == "ring"
	return it.slot == slot

# ---------- 인벤토리 ----------
func add_item(it: Dictionary, log := true) -> bool:
	var idx := inv_equip.find(null)
	if idx < 0:
		item_logged.emit("인벤토리가 가득 찼습니다", Color(1, 0.4, 0.4))
		return false
	inv_equip[idx] = it
	if log: item_logged.emit(Items.name_of(it), Data.grade_color(it.grade))
	changed.emit("inventory")
	return true

func add_stack(id: String, count := 1, log := true) -> void:
	var cap := int(Data.items_cfg.get("material_stack", 999))
	if Data.consumables.has(id):
		cap = int(Data.consumables[id].get("max_stack", 99))
		inv_consume[id] = mini(inv_consume.get(id, 0) + count, cap)
	else:
		inv_material[id] = mini(inv_material.get(id, 0) + count, cap)
	if log: item_logged.emit("%s ×%d" % [Data.item_def(id).get("name", id), count], Color(0.85, 0.85, 0.85))
	changed.emit("inventory")

func add_book(tier: String, cls: String, count := 1, log := true) -> void:
	var key := "%s:%s" % [tier, cls]
	inv_books[key] = inv_books.get(key, 0) + count
	if log: item_logged.emit(book_name(key), Color(0.9, 0.85, 0.6))
	changed.emit("inventory")

static func book_name(key: String) -> String:
	var p := key.split(":")
	if p[0] == "chrono": return "크로노 스킬서"
	var tier_name := ""
	for t in Data.skillbooks.get("tiers", []):
		if t.id == p[0]: tier_name = t.name
	return "%s (%s)" % [tier_name, Data.classes.get(p[1], {}).get("book", p[1])]

func sort_equip(mode: String) -> void:
	var items := inv_equip.filter(func(x): return x != null)
	var gi := func(it): return Data.grade_order.find(it.grade)
	match mode:
		"grade": items.sort_custom(func(a, b): return gi.call(a) > gi.call(b) if gi.call(a) != gi.call(b) else a.level > b.level)
		"level": items.sort_custom(func(a, b): return a.level > b.level if a.level != b.level else gi.call(a) > gi.call(b))
		_: items.sort_custom(func(a, b): return (a.kind + a.slot) < (b.kind + b.slot) if (a.kind + a.slot) != (b.kind + b.slot) else gi.call(a) > gi.call(b))
	for i in inv_equip.size(): inv_equip[i] = items[i] if i < items.size() else null
	changed.emit("inventory")

# ---------- 스탯 ----------
func class_data() -> Dictionary:
	return Data.classes[weapon_class()]

func set_buff_mods(m: Dictionary) -> void:
	buff_mods = m
	_mods_valid = false

func gear_mods() -> Dictionary:
	if _mods_valid: return _mods_cache
	var m := {}
	for s in equipment:
		if equipment[s] != null:
			for k in Items.option_mods(equipment[s]): m[k] = m.get(k, 0.0) + Items.option_mods(equipment[s])[k]
	var cls := weapon_class()
	var ml: int = mastery[cls].level
	var passives: Dictionary = Data.classes[cls].get("mastery_passives", {})
	for lv in passives:
		if ml >= int(lv):
			for k in passives[lv].mods: m[k] = m.get(k, 0.0) + float(passives[lv].mods[k])
	for k in buff_mods: m[k] = m.get(k, 0.0) + buff_mods[k]
	_mods_cache = m
	_mods_valid = true
	return m

func core_bonus_main() -> int:
	var t := 0
	for c in cores:
		if c != null: t += int(c.level) * int(Data.bal("chronoforce.core_main_stat", 3))
	return t

func core_hp_pct() -> float:
	var t := 0.0
	for c in cores:
		if c != null: t += int(c.level) * float(Data.bal("chronoforce.core_hp_pct", 0.01))
	return t

func stat_total(s: String) -> int:
	var v: int = stats[s]
	var main: String = Data.bal("stats.main_stat")[weapon_class()]
	if s == main: v += core_bonus_main() + int(gear_mods().get("main_stat", 0))
	return v

func max_hp() -> float:
	var d: Dictionary = Data.balance.derived
	var base := float(d.hp_base) + level * float(d.hp_per_level) + stat_total("vit") * float(Data.bal("stats.vit_hp"))
	return round(base * (1.0 + gear_mods().get("max_hp_pct", 0.0) + core_hp_pct()))

func defense() -> float:
	var v := stat_total("vit") * float(Data.bal("stats.vit_def"))
	for s in equipment:
		var it = equipment[s]
		if it != null and it.kind == "armor": v += Items.armor_defense(it)
	return v

func damage_reduction() -> float:
	var df := defense()
	var d: Dictionary = Data.balance.derived
	return minf(df / (df + float(d.dr_const)), float(d.dr_cap))

func attack_power() -> float:
	var cls := weapon_class()
	var main: String = Data.bal("stats.main_stat")[cls]
	var sub: String = Data.bal("stats.sub_stat")[cls]
	var watk := float(Items.weapon_attack(weapon())) if not weapon().is_empty() else 5.0
	var m := gear_mods()
	var mult := 1.0 + stat_total(main) * float(Data.bal("stats.main_coef")) + stat_total(sub) * float(Data.bal("stats.sub_coef"))
	var mastery_mult := 1.0 + (int(mastery[cls].level) - 1) * float(Data.bal("mastery.attack_per_level"))
	return watk * mult * (1.0 + m.get("attack_pct", 0.0)) * mastery_mult

func crit_chance() -> float:
	return minf(float(Data.bal("derived.crit_base")) + stat_total("dex") * float(Data.bal("stats.dex_crit")) + gear_mods().get("crit_chance", 0.0), float(Data.bal("derived.crit_cap")))

func crit_damage() -> float:
	return float(Data.bal("derived.crit_damage")) + gear_mods().get("crit_damage", 0.0)

func attack_speed() -> float:
	var bonus := minf(stat_total("dex") * float(Data.bal("stats.dex_aspd")) + gear_mods().get("attack_speed", 0.0), float(Data.bal("derived.aspd_cap")))
	return float(class_data().speed) * (1.0 + bonus)

func move_speed() -> float:
	var m := gear_mods()
	return minf(float(Data.bal("control.move_speed")) + m.get("move_speed", 0.0), float(Data.bal("derived.move_cap"))) * (1.0 + m.get("move_pct", 0.0))

func cdr() -> float:
	return minf(gear_mods().get("cdr", 0.0), float(Data.bal("derived.cdr_cap")))

func stamina_max() -> float:
	return float(Data.bal("stamina.max")) + gear_mods().get("stamina_max", 0.0)

func stamina_gain_mult() -> float:
	var v = 1.0 + stat_total("int") * float(Data.bal("stats.int_stamina_gain")) + gear_mods().get("stamina_gain", 0.0)
	v += float(class_data().traits.get("stamina_gain", 0.0))
	return v

func skill_damage_mult() -> float:
	return 1.0 + stat_total("int") * float(Data.bal("stats.int_skill_dmg")) + gear_mods().get("skill_damage", 0.0)

func groggy_mult() -> float:
	var v = 1.0 + stat_total("str") * float(Data.bal("stats.str_groggy")) + gear_mods().get("groggy", 0.0)
	v *= float(class_data().traits.get("groggy_mult", 1.0))
	return v

func chronoforce() -> int:
	var t := 0
	for c in cores:
		if c != null: t += int(c.level) * int(Data.bal("chronoforce.core_per_level", 10))
	return t + int(gear_mods().get("chronoforce", 0))

## 크로노포스 보정 [주는 피해, 받는 피해]. 요구치 0 인 지역은 보정 없음 (decided).
func chrono_mults() -> Array:
	if region_requirement <= 0: return [1.0, 1.0]
	var ratio := float(chronoforce()) / region_requirement
	for row in Data.bal("chronoforce.table"):
		if ratio >= float(row[0]): return [float(row[1]), float(row[2])]
	return [0.1, 2.0]

func crystal_stage() -> int:
	var cf := chronoforce()
	var steps: Array = Data.bal("chronoforce.appearance_steps")
	var st := 0
	for i in steps.size():
		if cf >= int(steps[i]): st = i
	return st

func allocate(stat: String, n := 1) -> bool:
	if stat_points < n or not stat in STATS: return false
	stat_points -= n; stats[stat] += n
	changed.emit("stats")
	return true

func reset_stats(use_item := true) -> String:
	if free_reset_used:
		if not use_item or inv_consume.get("oblivion_sand", 0) <= 0: return "망각의 모래가 필요합니다"
		inv_consume.oblivion_sand -= 1
	free_reset_used = true
	var start := int(Data.bal("stats.start"))
	for s in STATS:
		stat_points += stats[s] - start
		stats[s] = start
	changed.emit("stats"); changed.emit("inventory")
	return ""

# ---------- 경험치 ----------
static func exp_to_next(lv: int) -> float:
	return floor(float(Data.bal("exp.req_base")) * pow(lv, float(Data.bal("exp.req_exp"))))

static func monster_exp(mon_level: int, rank: String, player_level: int) -> float:
	var e := float(Data.bal("exp.mon_base")) * pow(mon_level, float(Data.bal("exp.mon_exp")))
	e *= float(Data.bal("exp.rank_mult").get(rank, 1))
	for p in Data.bal("exp.penalty"):
		if player_level - mon_level >= int(p[0]):
			e *= float(p[1]); break
	return round(e)

func gain_exp(amount: float, from_kill := false) -> void:
	if amount <= 0: return
	var cap := int(Data.bal("exp.max_level"))
	exp += amount
	while level < cap and exp >= exp_to_next(level):
		exp -= exp_to_next(level)
		level += 1
		stat_points += int(Data.bal("stats.points_per_level"))
		hp = max_hp()
		leveled_up.emit(level)
	if level >= cap: exp = 0
	if from_kill: _gain_mastery(amount * float(Data.bal("mastery.exp_share")))
	changed.emit("exp")

func _gain_mastery(amount: float) -> void:
	var m: Dictionary = mastery[weapon_class()]
	var mx := int(Data.bal("mastery.max_level"))
	m.exp += amount
	while m.level < mx and m.exp >= mastery_to_next(m.level):
		m.exp -= mastery_to_next(m.level)
		m.level += 1
		item_logged.emit("%s 숙련도 Lv%d" % [Data.class_name_ko(weapon_class()), m.level], Color(1, 0.85, 0.4))
		changed.emit("stats")

static func mastery_to_next(lv: int) -> float:
	return round(float(Data.bal("mastery.req_base")) * pow(float(Data.bal("mastery.req_growth")), lv - 1))

func lose_exp_on_death() -> void:
	exp = maxf(0.0, exp - exp_to_next(level) * float(Data.bal("exp.death_loss")))
	changed.emit("exp")

# ---------- 스킬 ----------
func skill_level(id: String) -> int:
	return int(skills.get(id, 0))

func learn_skill(id: String) -> int:
	var mx := int(Data.bal("skills.max_level"))
	skills[id] = mini(skill_level(id) + 1, mx)
	# 처음 배우면 빈 슬롯에 자동 배치
	if skills[id] == 1:
		var s: Dictionary = Data.skills[id]
		if s.cls == "chrono":
			var i := chrono_slots.find("")
			if i >= 0: chrono_slots[i] = id
		else:
			var arr: Array = slots[s.cls]
			var i := arr.find("")
			if i >= 0: arr[i] = id
	changed.emit("skills")
	return skills[id]

func slot_skill(slot_action: String) -> String:
	if slot_action.begins_with("slot_skill_"):
		return slots[weapon_class()][int(slot_action.right(1)) - 1]
	if slot_action.begins_with("slot_chrono_"):
		return chrono_slots[int(slot_action.right(1)) - 1]
	return ""

func set_slot_skill(slot_action: String, id: String) -> void:
	if slot_action.begins_with("slot_skill_"):
		var arr: Array = slots[weapon_class()]
		var i := arr.find(id)
		if i >= 0: arr[i] = ""
		arr[int(slot_action.right(1)) - 1] = id
	elif slot_action.begins_with("slot_chrono_"):
		var i := chrono_slots.find(id)
		if i >= 0: chrono_slots[i] = ""
		chrono_slots[int(slot_action.right(1)) - 1] = id
	changed.emit("skills")

## 스킬서 제안: 3장. 안 배운 스킬 70% / 배운 스킬 30%, 최고 등급 최소 1장. GDD 8-1.
func skillbook_offers(key: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new(); rng.randomize()
	var p := key.split(":")
	var tier := p[0]
	var cls := p[1]
	var allowed_tiers := []
	var top := ""
	if tier == "chrono":
		allowed_tiers = ["chrono"]; top = "chrono"
	else:
		for t in Data.skillbooks.tiers:
			if t.id == tier: allowed_tiers = t.offers
		top = allowed_tiers[-1]
	var mx := int(Data.bal("skills.max_level"))
	var cand := []
	for s in Data.skills.values():
		if s.cls != cls or not s.tier in allowed_tiers: continue
		if skill_level(s.id) >= mx: continue
		if tier == "chrono" and int(s.get("req_level", 0)) > level: continue
		cand.append(s)
	var picks := []
	var want := int(Data.bal("skills.offer_count", 3))
	var w_new := float(Data.bal("skills.offer_new_weight"))
	while picks.size() < want and not cand.is_empty():
		var news := cand.filter(func(s): return skill_level(s.id) == 0)
		var olds := cand.filter(func(s): return skill_level(s.id) > 0)
		var pool: Array = news if (not news.is_empty() and (olds.is_empty() or rng.randf() < w_new)) else olds
		var s: Dictionary = pool[rng.randi() % pool.size()]
		picks.append(s); cand.erase(s)
	# 최고 등급 보정
	if not picks.any(func(s): return s.tier == top):
		var tops := cand.filter(func(s): return s.tier == top)
		if not tops.is_empty() and not picks.is_empty():
			picks[picks.size() - 1] = tops[rng.randi() % tops.size()]
	return picks.map(func(s): return {"id": s.id, "from": skill_level(s.id), "to": mini(skill_level(s.id) + 1, mx)})

func book_tier_level(key: String) -> int:
	var tier := key.split(":")[0]
	for t in Data.skillbooks.get("tiers", []):
		if t.id == tier: return int(t.level)
	return 1
