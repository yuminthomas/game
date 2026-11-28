extends Node
## 데이터 로더. data/*.json 을 읽고 검증한다. 코드는 수치를 직접 갖지 않고 여기서 꺼내 쓴다.

const FILES := ["balance", "weapon_classes", "grades", "weapons", "skills", "status_effects", "items", "monsters"]
const CLASSES := ["sword", "greatsword", "dagger", "spear", "bow", "staff"]
const SKILL_BEHAVIORS := ["strike", "dash_strike", "spin", "counter", "multi_teleport", "beam", "aura", "buff", "leap",
	"charge_slam", "multi_slam", "teleport_behind", "clones", "projectile", "throw_recall", "backstep_shot", "trap",
	"aimed_shot", "zone", "frozen_arrows", "chain", "shield", "blink", "slow_field", "rewind", "echo", "time_stop", "chrono_burst"]
const UNIQUE_TYPES := ["just_dodge_next_attack", "crit_stamina", "finisher_echo", "revive", "steal_time",
	"charge_shockwave_radius", "on_hit_status", "charge_guard", "finisher_rocks", "charge_time_stop",
	"dash_trail_damage", "backstab_crit", "just_dodge_all_crit", "bleed_master", "execute",
	"extra_pierce", "dash_attack_boost", "nth_hit_lightning", "kill_star_beam", "long_reach",
	"first_hit_mark", "charge_frost_burst", "charge_arrow_rain", "arrow_bounce", "delayed_repeat",
	"triple_bolt", "poison_pool", "charge_sun", "free_skill", "crystal_ring"]

var raw := {}
var balance := {}
var classes := {}
var grades := {}
var grade_order: Array = []
var weapons := {}          # id -> dict
var skills := {}           # id -> dict
var skill_tiers := {}
var statuses := {}
var armor := {}
var consumables := {}
var materials := {}
var skillbooks := {}
var monsters := {}
var items_cfg := {}
var option_pool: Array = []
var errors: Array[String] = []
var warnings: Array[String] = []

func _ready() -> void:
	load_all()
	validate()
	for w in warnings: print("[Data] 참고: " + w)
	for e in errors: push_error("[Data] " + e)
	print("[Data] 무기 %d, 스킬 %d, 방어구 %d, 소모품 %d, 재료 %d / 오류 %d, 경고 %d" % [weapons.size(), skills.size(), armor.size(), consumables.size(), materials.size(), errors.size(), warnings.size()])

func load_all() -> void:
	errors.clear(); warnings.clear()
	for f in FILES:
		var path := "res://data/%s.json" % f
		var txt := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(txt)
		if parsed == null:
			errors.append("%s 를 읽을 수 없음 (JSON 오류)" % path)
			raw[f] = {}
		else:
			raw[f] = parsed
	balance = raw.balance
	classes = raw.weapon_classes.get("classes", {})
	grades = raw.grades.get("grades", {})
	grade_order = raw.grades.get("order", [])
	option_pool = raw.grades.get("option_pool", [])
	weapons.clear()
	for w in raw.weapons.get("weapons", []): weapons[w.id] = w
	skills.clear()
	for s in raw.skills.get("skills", []): skills[s.id] = s
	skill_tiers = raw.skills.get("tiers", {})
	statuses = raw.status_effects.get("effects", {})
	items_cfg = raw.items
	armor.clear(); consumables.clear(); materials.clear()
	for a in items_cfg.get("armor", []): armor[a.id] = a
	for c in items_cfg.get("consumables", []): consumables[c.id] = c
	for m in items_cfg.get("materials", []): materials[m.id] = m
	skillbooks = items_cfg.get("skillbooks", {})
	monsters = raw.monsters.get("monsters", {})

## "control.dash.speed" 같은 경로로 balance 값을 꺼낸다.
func bal(path: String, default = null):
	var cur = balance
	for part in path.split("."):
		if cur is Dictionary and cur.has(part): cur = cur[part]
		else:
			push_warning("[Data] balance 경로 없음: " + path)
			return default
	return cur

func weapon_attack_formula(level: int, grade: String, cls: String) -> int:
	var f: Dictionary = balance.weapon_attack_formula
	return int(round((f.base + level * f.per_level) * float(grades[grade].mult) * float(classes[cls].coef)))

func armor_defense(level: int, grade: String, slot: String) -> int:
	var f: Dictionary = balance.armor_formula
	if not f.slot_mult.has(slot): return 0
	return int(round((f.base + level * f.per_level) * float(grades[grade].mult) * float(f.slot_mult[slot])))

func item_def(id: String) -> Dictionary:
	if weapons.has(id): return weapons[id]
	if armor.has(id): return armor[id]
	if consumables.has(id): return consumables[id]
	if materials.has(id): return materials[id]
	return {}

func grade_color(grade: String) -> Color:
	return Color(grades.get(grade, {}).get("color", "#ffffff"))

func class_name_ko(cls: String) -> String:
	if cls == "chrono": return "크로노"
	return classes.get(cls, {}).get("name", cls)

func skills_of(cls: String) -> Array:
	var out := []
	for s in skills.values():
		if s.cls == cls: out.append(s)
	return out

## 검증: 개수, 공식 일치, 참조 무결성. 오류는 errors, 기획 대비 차이는 warnings.
func validate() -> void:
	# 무기
	if weapons.size() != 54: errors.append("무기는 54종이어야 함 (현재 %d)" % weapons.size())
	var per_class := {}
	for w in weapons.values():
		for key in ["id", "name", "class", "grade", "level", "attack"]:
			if not w.has(key): errors.append("무기 %s: %s 없음" % [w.get("id", "?"), key])
		if not classes.has(w.class): errors.append("무기 %s: 알 수 없는 무기군 %s" % [w.id, w.class]); continue
		if not grades.has(w.grade): errors.append("무기 %s: 알 수 없는 등급 %s" % [w.id, w.grade]); continue
		per_class[w.class] = per_class.get(w.class, {})
		per_class[w.class][w.grade] = per_class[w.class].get(w.grade, 0) + 1
		var f := weapon_attack_formula(int(w.level), w.grade, w.class)
		if f != int(w.attack):
			warnings.append("무기 %s(%s) 공격력 표 %d ≠ 공식 %d (표 값을 사용)" % [w.name, w.id, w.attack, f])
		if grades[w.grade].unique and not w.has("unique"):
			errors.append("무기 %s: %s 등급은 고유 효과가 필요" % [w.id, w.grade])
		if w.has("unique") and not w.unique.type in UNIQUE_TYPES:
			errors.append("무기 %s: 구현되지 않은 고유 효과 %s" % [w.id, w.unique.type])
	var expect := {"common": 2, "rare": 2, "epic": 2, "legendary": 2, "mythic": 1}
	for c in CLASSES:
		for g in expect:
			if per_class.get(c, {}).get(g, 0) != expect[g]:
				errors.append("%s %s 무기 수 %d (기대 %d)" % [c, g, per_class.get(c, {}).get(g, 0), expect[g]])
	# 스킬
	if skills.size() != 54: errors.append("스킬은 54개여야 함 (현재 %d)" % skills.size())
	for c in CLASSES + ["chrono"]:
		var n := skills_of(c).size()
		var want := 6 if c == "chrono" else 8
		if n != want: errors.append("%s 스킬 %d개 (기대 %d)" % [c, n, want])
	for s in skills.values():
		if not s.behavior.type in SKILL_BEHAVIORS: errors.append("스킬 %s: 알 수 없는 동작 %s" % [s.id, s.behavior.type])
		if not skill_tiers.has(s.tier): errors.append("스킬 %s: 알 수 없는 등급 %s" % [s.id, s.tier])
		for e in s.behavior.get("effects", []) + s.get("lv5", {}).get("effects", []):
			if not statuses.has(e.status): errors.append("스킬 %s: 상태이상 %s 없음" % [s.id, e.status])
	# 상태이상
	for k in ["bleed", "poison", "burn", "slow", "freeze", "stagger", "root", "mark"]:
		if not statuses.has(k): errors.append("상태이상 %s 없음" % k)
	# 방어구
	for a in armor.values():
		if not grades.has(a.grade): errors.append("방어구 %s 등급 오류" % a.id)
	# 무기 고유효과의 상태이상 참조
	for w in weapons.values():
		if w.has("unique") and w.unique.params.has("status") and not statuses.has(w.unique.params.status):
			errors.append("무기 %s: 상태이상 %s 없음" % [w.id, w.unique.params.status])
	# 몬스터
	for id in monsters:
		if not monsters[id].has("level"): errors.append("몬스터 %s level 없음" % id)
	# 밸런스 필수 키
	for p in ["control.move_speed", "control.input_buffer", "control.dash.charges", "control.parry.window", "stamina.max",
			"exp.req_base", "monster.hp_base", "derived.dr_const", "hitstop_frames.parry"]:
		if bal(p) == null: errors.append("balance 에 %s 없음" % p)
