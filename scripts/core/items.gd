class_name Items
## 아이템 인스턴스 생성, 추가 옵션 추첨, 표시용 텍스트. 인스턴스는 직렬화하기 쉽게 Dictionary 로 둔다.

static var _uid := 0

static func next_uid() -> int:
	_uid += 1
	return _uid

static func make_weapon(id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var d: Dictionary = Data.weapons.get(id, {})
	if d.is_empty(): return {}
	var it := {"uid": next_uid(), "kind": "weapon", "id": id, "grade": d.grade, "level": int(d.level),
		"slot": "weapon", "options": [], "enhance": 0, "locked": false, "new": true}
	it.options = roll_options(d.grade, "weapon", rng)
	return it

static func make_armor(id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var d: Dictionary = Data.armor.get(id, {})
	if d.is_empty(): return {}
	var it := {"uid": next_uid(), "kind": "armor", "id": id, "grade": d.grade, "level": int(d.level),
		"slot": d.slot, "options": [], "enhance": 0, "locked": false, "new": true}
	var n: int = int(Data.grades[d.grade].options)
	if d.slot in ["ring", "necklace"]: n += 1     # 장신구는 방어력 대신 옵션 1개 더 (GDD 9-2)
	it.options = roll_options(d.grade, d.slot, rng, n)
	return it

static func make(id: String) -> Dictionary:
	if Data.weapons.has(id): return make_weapon(id)
	if Data.armor.has(id): return make_armor(id)
	return {}

## 추가 옵션: 등급별 개수, 수치는 등급이 높을수록 큰 구간에서 뽑는다.
static func roll_options(grade: String, slot: String, rng: RandomNumberGenerator = null, count := -1) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new(); rng.randomize()
	var g: Dictionary = Data.grades[grade]
	if count < 0: count = int(g.options)
	var band: int = int(g.band)
	var grade_idx: int = Data.grade_order.find(grade)
	var pool := []
	var weights := []
	var bias: Dictionary = Data.raw.grades.get("slot_option_bias", {}).get(slot, {})
	for o in Data.option_pool:
		if o.has("min_grade") and grade_idx < Data.grade_order.find(o.min_grade): continue
		pool.append(o); weights.append(float(bias.get(o.id, 1)))
	var out := []
	for i in count:
		if pool.is_empty(): break
		var total := 0.0
		for w in weights: total += w
		var r := rng.randf() * total
		var pick := 0
		for j in weights.size():
			r -= weights[j]
			if r <= 0: pick = j; break
		var o: Dictionary = pool[pick]
		pool.remove_at(pick); weights.remove_at(pick)
		var lo: float = lerp(float(o.min), float(o.max), band / 5.0)
		var hi: float = lerp(float(o.min), float(o.max), (band + 1) / 5.0)
		out.append({"id": o.id, "value": int(round(rng.randf_range(lo, hi)))})
	return out

static func def_of(it: Dictionary) -> Dictionary:
	return Data.item_def(it.get("id", ""))

static func name_of(it: Dictionary) -> String:
	var n: String = def_of(it).get("name", "?")
	if int(it.get("enhance", 0)) > 0: n += " +%d" % it.enhance
	return n

static func enhance_mult(it: Dictionary) -> float:
	return 1.0 + float(Data.bal("enhance.per_level", 0.06)) * int(it.get("enhance", 0))

static func weapon_attack(it: Dictionary) -> int:
	return int(round(float(def_of(it).get("attack", 0)) * enhance_mult(it)))

static func armor_defense(it: Dictionary) -> int:
	return int(round(Data.armor_defense(int(it.level), it.grade, it.slot) * enhance_mult(it)))

static func option_def(id: String) -> Dictionary:
	for o in Data.option_pool:
		if o.id == id: return o
	return {}

static func option_text(o: Dictionary) -> String:
	var d := option_def(o.id)
	return "%s +%d%s" % [d.get("name", o.id), o.value, d.get("unit", "")]

## 옵션을 스탯 수정치로 변환 (% 단위는 0.01 배)
static func option_mods(it: Dictionary) -> Dictionary:
	var m := {}
	for o in it.get("options", []):
		var d := option_def(o.id)
		var v: float = float(o.value)
		if d.get("unit", "") == "%": v *= 0.01
		m[o.id] = m.get(o.id, 0.0) + v
	return m

static func slot_name(slot: String) -> String:
	return {"weapon": "무기", "helmet": "투구", "chest": "갑옷", "gloves": "장갑", "boots": "신발",
		"ring": "반지", "ring1": "반지", "ring2": "반지", "necklace": "목걸이"}.get(slot, slot)

## 툴팁용 줄 목록 [[텍스트, 색], ...]. compare 가 있으면 수치 비교(오름 초록, 내림 빨강).
static func tooltip_lines(it: Dictionary, compare: Dictionary = {}, pdata = null) -> Array:
	var d := def_of(it)
	var lines := []
	lines.append([name_of(it), Data.grade_color(it.grade)])
	var sub := "%s · %s" % [Data.grades[it.grade].name, slot_name(it.slot)]
	if it.kind == "weapon": sub = "%s · %s" % [Data.grades[it.grade].name, Data.class_name_ko(d.class)]
	lines.append([sub, Color(0.7, 0.7, 0.75)])
	var lv_col := Color(0.85, 0.85, 0.85)
	if pdata != null and pdata.level < int(it.level): lv_col = Color(1, 0.4, 0.4)
	lines.append(["요구 레벨 %d" % it.level, lv_col])
	if it.kind == "weapon":
		var a := weapon_attack(it)
		var t := "공격력 %d%s" % [a, _diff(a, weapon_attack(compare) if not compare.is_empty() else a, compare)]
		lines.append([t, diff_color(t)])
		var cd: Dictionary = Data.classes[d.class]
		lines.append(["공격속도 %.2f · 사거리 %s칸" % [cd.speed, str(cd.range)], Color(0.8, 0.8, 0.8)])
	elif int(Data.armor_defense(int(it.level), it.grade, it.slot)) > 0:
		var df := armor_defense(it)
		var t := "방어력 %d%s" % [df, _diff(df, armor_defense(compare) if not compare.is_empty() else df, compare)]
		lines.append([t, diff_color(t)])
	if not it.options.is_empty():
		var cmp := option_mods(compare) if not compare.is_empty() else {}
		var mine := option_mods(it)
		for o in it.options:
			var t := option_text(o)
			var col := Color(0.6, 0.85, 1.0)
			if not compare.is_empty():
				var dv: float = mine.get(o.id, 0.0) - cmp.get(o.id, 0.0)
				if dv > 0.0001: col = Color(0.5, 1.0, 0.5)
				elif dv < -0.0001: col = Color(1.0, 0.45, 0.45)
			lines.append([t, col])
		if not compare.is_empty():
			for k in cmp:
				if not mine.has(k):
					lines.append(["(%s 없음)" % option_def(k).get("name", k), Color(1.0, 0.45, 0.45)])
	if d.has("unique"):
		lines.append(["◆ " + d.unique.desc, Color(1.0, 0.8, 0.4)])
	if d.has("desc"): lines.append([d.desc, Color(0.75, 0.75, 0.8)])
	if d.has("design"): lines.append([d.design, Color(0.55, 0.55, 0.62)])
	if not compare.is_empty(): lines.append(["(현재 장착: %s)" % name_of(compare), Color(0.6, 0.6, 0.65)])
	return lines

static func _diff(a: int, b: int, compare: Dictionary) -> String:
	if compare.is_empty() or a == b: return ""
	return " (%s%d)" % ["+" if a > b else "", a - b]

static func diff_color(text: String) -> Color:
	if text.contains("(+"): return Color(0.5, 1.0, 0.5)
	if text.contains("(-"): return Color(1.0, 0.45, 0.45)
	return Color.WHITE
