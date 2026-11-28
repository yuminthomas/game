class_name SpriteFactory
## 그래픽 공급처. 정해진 경로에 PNG 가 있으면 그것을 쓰고, 없으면 코드로 임시 도트를 그린다.
## 경로와 규격은 docs/ASSETS.md 참고. 교체하려면 같은 경로에 같은 규격의 파일을 넣으면 된다.

const FRAME := 48
const DIRS := 5                    # 0 아래, 1 아래대각, 2 옆(오른쪽), 3 위대각, 4 위
const ANIMS := {"idle": 6, "run": 8, "dash": 4, "guard": 3, "hit": 2, "die": 8, "potion": 6, "interact": 4, "attack": 4, "charge": 4}
const LAYERS := ["cape_back", "body", "feet", "armor", "hands", "crystal", "hair", "helmet", "cape_front"]
const OUTLINE := Color("14121f")

const HAIR_COLORS := [Color("ffffff"), Color("9aa0b0"), Color("4a4a5c"), Color("c0704a"), Color("f0d070"), Color("8fb8ff")]
const CAPE_COLORS := [Color("4656a8"), Color("a83a3a"), Color("3f7a4a"), Color("44444e"), Color("7a4aa0"), Color("b09a6a")]
const HAIR_NAMES := ["은백", "잿빛", "칠흑", "적갈", "금빛", "청빛"]
const CAPE_NAMES := ["남색", "진홍", "숲빛", "먹빛", "자줏빛", "모래빛"]

static var _cache := {}

static func _path_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path): return load(path)
	return null

# =====================================================================
# 플레이어 레이어 시트: 열 = 프레임, 행 = 방향 5개
# =====================================================================
static func player_sheet(layer: String, variant: String, anim: String) -> Texture2D:
	var key := "p/%s/%s/%s" % [layer, variant, anim]
	if _cache.has(key): return _cache[key]
	var tex := _path_tex("res://assets/sprites/player/%s/%s/%s.png" % [layer, variant, anim])
	if tex == null:
		tex = ImageTexture.create_from_image(_gen_player_sheet(layer, variant, anim))
	_cache[key] = tex
	return tex

static func anim_frames(anim: String) -> int:
	return ANIMS.get(anim, 4)

## 프레임별 [다리 자세, 상체 위아래, 망토 흔들림, 앞으로 기울기]
static func _frame_params(anim: String, f: int) -> Array:
	match anim:
		"idle": return [0, [0, 0, 1, 1, 1, 0][f], [0, 1, 1, 0, 0, 0][f], 0]
		"run": return [[1, 1, 0, 0, 2, 2, 0, 0][f], [0, 1, 1, 0, 0, 1, 1, 0][f], 2, 1]
		"dash": return [1, 1, 2, 2]
		"guard": return [0, 1, 0, -1]
		"hit": return [0, 0, 1, -1]
		"die": return [0, mini(f, 6), 0, 0]
		"potion": return [0, [0, 0, -1, -1, 0, 0][f], 0, 0]
		"interact": return [0, 0, 0, [0, 1, 1, 0][f]]
		"attack": return [[0, 1, 1, 0][f], 0, [0, 2, 2, 1][f], [0, 1, 2, 1][f]]
		"charge": return [2, 1, [1, 2, 1, 2][f], -1]
	return [0, 0, 0, 0]

static func _gen_player_sheet(layer: String, variant: String, anim: String) -> Image:
	var n := anim_frames(anim)
	var img := Image.create(FRAME * n, FRAME * DIRS, false, Image.FORMAT_RGBA8)
	for d in DIRS:
		var parts := _player_parts(layer, variant, d)
		for f in n:
			var p := _frame_params(anim, f)
			var dst := Vector2i(f * FRAME, d * FRAME)
			var lean := Vector2i(int(p[3]) if d in [1, 2, 3] else 0, (int(p[3]) if d == 0 else (-int(p[3]) if d == 4 else 0)))
			if parts.has("legs"):
				img.blend_rect(parts.legs[p[0]], Rect2i(0, 0, FRAME, FRAME), dst)
			if parts.has("upper"):
				img.blend_rect(parts.upper, Rect2i(0, 0, FRAME, FRAME), dst + Vector2i(0, p[1]) + lean)
			if parts.has("sway"):
				img.blend_rect(parts.sway[p[2]], Rect2i(0, 0, FRAME, FRAME), dst + Vector2i(0, p[1]) + lean)
	return img

static func _blank() -> Image:
	return Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)

static func _r(img: Image, x: int, y: int, w: int, h: int, c) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c if c is Color else Color(c))

## 바깥 테두리 1px (투명 픽셀 중 불투명 이웃이 있으면 칠함)
static func _outline(img: Image) -> Image:
	var out := img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var used := img.get_used_rect()
	if used.size == Vector2i.ZERO: return out
	for y in range(maxi(0, used.position.y - 1), mini(h, used.end.y + 1)):
		for x in range(maxi(0, used.position.x - 1), mini(w, used.end.x + 1)):
			if img.get_pixel(x, y).a > 0.1: continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixelv(q).a > 0.5:
					out.set_pixel(x, y, OUTLINE); break
	return out

static func _player_parts(layer: String, variant: String, d: int) -> Dictionary:
	var key := "parts/%s/%s/%d" % [layer, variant, d]
	if _cache.has(key): return _cache[key]
	var r := {}
	match layer:
		"body":
			r.legs = [_outline(_legs(d, 0, false)), _outline(_legs(d, 1, false)), _outline(_legs(d, 2, false))]
			r.upper = _outline(_torso_head(d))
		"feet":
			r.legs = [_legs(d, 0, true), _legs(d, 1, true), _legs(d, 2, true)]
		"hair":
			r.upper = _outline(_hair(d))
		"cape_back", "cape_front":
			var front := layer == "cape_front"
			if (front and d >= 3) or (not front and d <= 2):
				r.sway = [_outline(_cape(d, 0, variant)), _outline(_cape(d, 1, variant)), _outline(_cape(d, 2, variant))]
		"armor":
			if variant != "none": r.upper = _outline(_armor(d))
		"hands":
			r.upper = _hands(d)
		"crystal":
			r.upper = _crystal(d, int(variant))
		"helmet":
			if variant != "none": r.upper = _outline(_helmet(d, variant))
	_cache[key] = r
	return r

const SKIN := Color("f0d6c0")
const SKIN_D := Color("d8b49c")
const TUNIC := Color("d9c9a3")
const TUNIC_D := Color("b8a67e")
const BELT := Color("6b4a2e")
const PANTS := Color("3d3550")
const EYE := Color("8f96a3")
const G1 := Color("e6e6ea")
const G2 := Color("bcbcc4")
const G3 := Color("8e8e98")

static func _legs(d: int, pose: int, boots: bool) -> Image:
	var img := _blank()
	var side := d == 2
	var pc := G2 if boots else PANTS
	var y0 := 37 if boots else 35
	if side or d in [1, 3]:
		var a = [0, -2, 2][pose]
		var xs := [22 + a, 25 - a] if side else [21 + a / 2, 25 - a / 2]
		for x in xs:
			_r(img, x, y0, 3, 42 - y0, pc)
			if boots: _r(img, x, 41, 3, 1, G3)
	else:
		var l = [0, -2, 0][pose]
		var rr = [0, 0, -2][pose]
		_r(img, 20, y0, 3, 42 - y0 + l, pc)
		_r(img, 25, y0, 3, 42 - y0 + rr, pc)
		if boots:
			_r(img, 20, 41 + l, 3, 1, G3); _r(img, 25, 41 + rr, 3, 1, G3)
	return img

static func _torso_head(d: int) -> Image:
	var img := _blank()
	# 몸통 (튜닉)
	match d:
		0, 4:
			_r(img, 19, 26, 10, 10, TUNIC); _r(img, 19, 33, 10, 2, TUNIC_D)
			_r(img, 17, 27, 2, 5, TUNIC_D); _r(img, 29, 27, 2, 5, TUNIC_D)   # 소매
		1, 3:
			_r(img, 19, 26, 10, 10, TUNIC); _r(img, 19, 33, 10, 2, TUNIC_D)
			_r(img, 18, 27, 2, 5, TUNIC_D); _r(img, 28, 27, 3, 5, TUNIC_D)
		2:
			_r(img, 20, 26, 8, 10, TUNIC); _r(img, 20, 33, 8, 2, TUNIC_D)
			_r(img, 23, 27, 3, 6, TUNIC_D)
	_r(img, 19 if d != 2 else 20, 31, 10 if d != 2 else 8, 2, BELT)
	# 목·얼굴
	_r(img, 22, 24, 4, 2, SKIN_D)
	match d:
		0:
			_r(img, 19, 15, 10, 10, SKIN); _r(img, 20, 24, 8, 1, SKIN_D)
			_r(img, 21, 20, 2, 2, EYE); _r(img, 25, 20, 2, 2, EYE)
			_r(img, 21, 21, 1, 1, OUTLINE); _r(img, 26, 21, 1, 1, OUTLINE)
		1:
			_r(img, 19, 15, 10, 10, SKIN)
			_r(img, 23, 20, 2, 2, EYE); _r(img, 27, 20, 1, 2, EYE)
			_r(img, 24, 21, 1, 1, OUTLINE)
		2:
			_r(img, 20, 15, 9, 10, SKIN); _r(img, 29, 20, 1, 2, SKIN)
			_r(img, 26, 20, 2, 2, EYE); _r(img, 27, 21, 1, 1, OUTLINE)
		3, 4:
			_r(img, 19, 15, 10, 10, SKIN_D)
	return img

static func _hair(d: int) -> Image:
	var img := _blank()
	match d:
		0:
			_r(img, 18, 12, 12, 5, G1); _r(img, 18, 17, 2, 6, G2); _r(img, 28, 17, 2, 6, G2)
			for x in [20, 23, 26]: _r(img, x, 17, 2, 2, G1)
			_r(img, 19, 11, 4, 1, G1); _r(img, 25, 11, 3, 1, G1)
		1:
			_r(img, 18, 12, 12, 5, G1); _r(img, 18, 17, 4, 7, G2); _r(img, 22, 17, 2, 2, G1); _r(img, 26, 17, 2, 1, G1)
			_r(img, 20, 11, 6, 1, G1)
		2:
			_r(img, 18, 12, 11, 5, G1); _r(img, 18, 17, 5, 8, G2); _r(img, 24, 17, 3, 1, G1)
			_r(img, 17, 19, 1, 4, G3); _r(img, 20, 11, 6, 1, G1)
		3:
			_r(img, 18, 12, 12, 13, G1); _r(img, 18, 22, 10, 3, G2); _r(img, 28, 17, 1, 5, SKIN_D)
			_r(img, 20, 11, 7, 1, G1)
		4:
			_r(img, 18, 12, 12, 13, G1); _r(img, 18, 21, 12, 4, G2)
			for x in [19, 23, 27]: _r(img, x, 25, 2, 1, G2)
			_r(img, 20, 11, 8, 1, G1)
	return img

static func _cape(d: int, sway: int, style: String) -> Image:
	var img := _blank()
	var bottom := {"short": 34, "long": 41}.get(style, 38)
	var dx = [0, 1, 2][sway]
	match d:
		0, 1:
			_r(img, 16, 25, 3, bottom - 25, G2); _r(img, 29, 25, 3, bottom - 25, G2)
			_r(img, 18, 24, 12, 2, G1)
		2:
			_r(img, 16 - dx, 25, 6, bottom - 25, G2); _r(img, 18, 24, 6, 2, G1)
			for i in 3: _r(img, 16 - dx + i * 2, bottom - (i % 2), 1, 1, G3)
		3, 4:
			_r(img, 17, 24, 14, bottom - 24, G2); _r(img, 17, 24, 14, 3, G1)
			_r(img, 23, 27, 2, bottom - 30, G3)
			for i in 7: _r(img, 17 + i * 2 + (dx % 2), bottom - 1 + (i % 2), 1, 1 - (i % 2), G3)
			if d == 3: _r(img, 30, 26, 1, bottom - 28, G3)
	return img

static func _armor(d: int) -> Image:
	var img := _blank()
	if d == 2:
		_r(img, 20, 26, 8, 6, G2); _r(img, 22, 25, 5, 2, G1)
	else:
		_r(img, 19, 26, 10, 6, G2); _r(img, 17, 25, 4, 3, G1); _r(img, 27, 25, 4, 3, G1)
		_r(img, 23, 27, 2, 4, G3)
	return img

static func _hands(d: int) -> Image:
	var img := _blank()
	match d:
		0, 4: _r(img, 17, 32, 2, 2, G2); _r(img, 29, 32, 2, 2, G2)
		1, 3: _r(img, 18, 32, 2, 2, G2); _r(img, 29, 32, 2, 2, G2)
		2: _r(img, 24, 33, 2, 2, G2)
	return img

static func _crystal(d: int, stage: int) -> Image:
	var img := _blank()
	if stage <= 0: return img
	var c := Color("bff3ff")
	var c2 := Color(0.75, 0.95, 1.0, 0.75)
	# 1단계: 손등
	if d != 2: _r(img, 17, 32, 1, 1, c); _r(img, 30, 32, 1, 1, c)
	else: _r(img, 25, 33, 1, 1, c)
	if stage >= 2:   # 팔과 목
		_r(img, 18 if d != 2 else 24, 28, 1, 3, c2); _r(img, 23, 24, 1, 2, c2)
		if d != 2: _r(img, 29, 28, 1, 3, c2)
	if stage >= 3 and d <= 2:   # 뺨, 눈
		if d == 0: _r(img, 21, 20, 2, 1, c); _r(img, 25, 20, 2, 1, c); _r(img, 20, 23, 1, 1, c2)
		elif d == 1: _r(img, 23, 20, 2, 1, c); _r(img, 27, 20, 1, 1, c)
		else: _r(img, 26, 20, 2, 1, c)
	if stage >= 4:
		for p in [Vector2i(20, 28), Vector2i(26, 30), Vector2i(22, 34), Vector2i(19, 36), Vector2i(27, 27)]:
			_r(img, p.x, p.y, 2, 1, c)
	return img

static func _helmet(d: int, style: String) -> Image:
	var img := _blank()
	if style == "hood":
		_r(img, 17, 11, 14, 6, G2)
		if d <= 2:
			_r(img, 17, 17, 2, 8, G3); _r(img, 29 if d != 2 else 17, 17, 2, 8, G3)
		else:
			_r(img, 17, 17, 14, 9, G2)
	else:
		_r(img, 18, 11, 12, 6, G1); _r(img, 18, 16, 12, 1, G3)
		if d == 0: _r(img, 23, 11, 2, 7, G2)
		if d >= 3: _r(img, 18, 17, 12, 5, G2)
	return img

# =====================================================================
# 무기: 손잡이가 (4, 8) 인 40×16 이미지, 오른쪽을 향함
# =====================================================================
const WEAPON_SIZE := Vector2i(40, 16)
const WEAPON_PIVOT := Vector2(4, 8)

static func weapon_texture(weapon_id: String) -> Texture2D:
	var key := "w/" + weapon_id
	if _cache.has(key): return _cache[key]
	var tex := _path_tex("res://assets/sprites/weapons/%s.png" % weapon_id)
	if tex == null:
		var d: Dictionary = Data.weapons.get(weapon_id, {"class": "sword", "grade": "common"})
		tex = ImageTexture.create_from_image(_outline(_weapon_image(d.class, d.grade)))
	_cache[key] = tex
	return tex

static func _weapon_image(cls: String, grade: String) -> Image:
	var img := Image.create(WEAPON_SIZE.x, WEAPON_SIZE.y, false, Image.FORMAT_RGBA8)
	var metal := Color("d8dce6")
	var metal_d := Color("9aa0b0")
	var wood := Color("8a5a34")
	var accent := Data.grade_color(grade)
	if grade == "common": accent = Color("b08a50")
	match cls:
		"sword":
			_r(img, 1, 7, 5, 2, wood); _r(img, 6, 5, 2, 6, accent)
			_r(img, 8, 7, 14, 2, metal); _r(img, 8, 8, 14, 1, metal_d); _r(img, 22, 7, 1, 1, metal)
		"greatsword":
			_r(img, 0, 7, 6, 2, wood); _r(img, 6, 4, 3, 8, accent)
			_r(img, 9, 6, 22, 4, metal); _r(img, 9, 9, 22, 1, metal_d); _r(img, 31, 7, 2, 2, metal)
		"dagger":
			_r(img, 2, 7, 4, 2, wood); _r(img, 6, 6, 1, 4, accent)
			_r(img, 7, 7, 7, 2, metal); _r(img, 7, 8, 7, 1, metal_d)
		"spear":
			_r(img, 0, 7, 30, 2, wood); _r(img, 28, 6, 2, 4, accent)
			_r(img, 30, 6, 6, 4, metal); _r(img, 36, 7, 2, 2, metal)
		"bow":
			for i in 13:
				var y := 1 + i
				var x := 6 + int(round(4.0 * sin(PI * i / 12.0)))
				_r(img, x, y, 2, 1, wood)
			_r(img, 6, 1, 1, 14, Color(0.9, 0.9, 0.9, 0.8)); _r(img, 9, 7, 2, 2, accent)
		"staff":
			_r(img, 0, 7, 24, 2, wood); _r(img, 24, 5, 3, 6, wood)
			_r(img, 26, 5, 5, 6, accent); _r(img, 27, 6, 3, 4, accent.lightened(0.5))
	return img

# =====================================================================
# 아이콘 16×16 (아이템, 스킬)
# =====================================================================
static func item_icon(id: String) -> Texture2D:
	var key := "i/" + id
	if _cache.has(key): return _cache[key]
	var tex := _path_tex("res://assets/sprites/icons/%s.png" % id)
	if tex == null: tex = ImageTexture.create_from_image(_outline(_item_icon_image(id)))
	_cache[key] = tex
	return tex

static func _item_icon_image(id: String) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	if Data.weapons.has(id):
		var w: Dictionary = Data.weapons[id]
		var src := _weapon_image(w.class, w.grade)
		var used := src.get_used_rect()
		# 대각선으로 축소해 담기
		var s := minf(1.0, 18.0 / maxf(1, used.size.x))
		for x in used.size.x:
			for y in used.size.y:
				var c := src.get_pixel(used.position.x + x, used.position.y + y)
				if c.a < 0.1: continue
				var fx := x * s
				var fy := (y - used.size.y / 2.0) * maxf(s, 0.6)
				var px := int(1 + fx * 0.72 - fy * 0.7)
				var py := int(14 - fx * 0.72 - fy * 0.7)
				if px >= 0 and py >= 0 and px < 16 and py < 16: img.set_pixel(px, py, c)
		return img
	if Data.armor.has(id):
		var a: Dictionary = Data.armor[id]
		var c := Color(a.get("look", {}).get("color", "#a0a0a0"))
		var acc := Data.grade_color(a.grade)
		match a.slot:
			"helmet": _r(img, 3, 4, 10, 6, c); _r(img, 2, 9, 12, 2, c.darkened(0.2)); _r(img, 7, 4, 2, 6, acc)
			"chest": _r(img, 3, 3, 10, 11, c); _r(img, 1, 3, 3, 5, c.darkened(0.2)); _r(img, 12, 3, 3, 5, c.darkened(0.2)); _r(img, 7, 4, 2, 9, acc)
			"gloves": _r(img, 4, 4, 7, 8, c); _r(img, 11, 6, 2, 4, c); _r(img, 4, 11, 7, 2, acc)
			"boots": _r(img, 4, 2, 5, 11, c); _r(img, 4, 11, 9, 3, c.darkened(0.2)); _r(img, 4, 2, 5, 2, acc)
			"ring": _r(img, 4, 6, 8, 7, Color("d8b84a")); _r(img, 6, 8, 4, 3, Color(0, 0, 0, 0)); _r(img, 6, 3, 4, 3, acc)
			"necklace": _r(img, 3, 2, 1, 6, Color("d8b84a")); _r(img, 12, 2, 1, 6, Color("d8b84a")); _r(img, 4, 8, 8, 1, Color("d8b84a")); _r(img, 6, 9, 4, 4, acc)
		return img
	var col := Color("9ad0ff")
	match id:
		"potion": _r(img, 6, 2, 4, 3, Color("c8b090")); _r(img, 4, 5, 8, 9, Color("e84a5a")); _r(img, 5, 6, 2, 3, Color("ffb0b8"))
		"herb_bundle": _r(img, 3, 6, 10, 4, Color("4aa04a")); _r(img, 7, 3, 2, 11, Color("6ac05a")); _r(img, 6, 9, 4, 2, Color("8a5a34"))
		"stamina_candy": _r(img, 4, 4, 8, 8, Color("9ff0ff")); _r(img, 1, 7, 3, 2, Color("c8f8ff")); _r(img, 12, 7, 3, 2, Color("c8f8ff"))
		"return_sand", "oblivion_sand", "time_sand":
			var sc = {"return_sand": Color("e0c070"), "oblivion_sand": Color("b090e0"), "time_sand": Color("f0d890")}[id]
			_r(img, 4, 2, 8, 2, Color("8a5a34")); _r(img, 4, 12, 8, 2, Color("8a5a34")); _r(img, 5, 4, 6, 3, sc); _r(img, 7, 7, 2, 2, sc); _r(img, 5, 9, 6, 3, sc)
		"antidote": _r(img, 6, 2, 4, 3, Color("c8b090")); _r(img, 4, 5, 8, 9, Color("6ad05a"))
		"chrono_shard": _r(img, 6, 2, 4, 12, Color("bff3ff")); _r(img, 4, 5, 8, 6, Color("9ae0ff"))
		_:
			if id.begins_with("dust_"): col = Data.grade_color(id.substr(5))
			_r(img, 4, 5, 8, 7, col); _r(img, 5, 4, 6, 9, col.lightened(0.2))
	return img

static func book_icon(key: String) -> Texture2D:
	var ck := "b/" + key
	if _cache.has(ck): return _cache[ck]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var tier := key.split(":")[0]
	var c := Color(Data.skill_tiers.get(tier, {}).get("color", "#a0a0a0"))
	_r(img, 3, 2, 10, 12, c.darkened(0.3)); _r(img, 4, 2, 8, 11, c); _r(img, 4, 12, 9, 1, Color("f0e8d0"))
	_r(img, 6, 5, 4, 1, Color("f0e8d0")); _r(img, 6, 7, 3, 1, Color("f0e8d0"))
	var tex := ImageTexture.create_from_image(_outline(img))
	_cache[ck] = tex
	return tex

static func skill_icon(skill_id: String) -> Texture2D:
	var key := "s/" + skill_id
	if _cache.has(key): return _cache[key]
	var tex := _path_tex("res://assets/sprites/skills/%s.png" % skill_id)
	if tex == null:
		var s: Dictionary = Data.skills.get(skill_id, {})
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var bg := Color(Data.skill_tiers.get(s.get("tier", "old"), {}).get("color", "#888888")).darkened(0.45)
		_r(img, 0, 0, 16, 16, bg); _r(img, 1, 1, 14, 14, bg.lightened(0.15))
		var c := Color("f4f0e0")
		match s.get("pose", "cast"):
			"slash":
				for i in 10: _r(img, 3 + i, 12 - i, 2, 1, c)
				_r(img, 3, 11, 3, 2, Color("c8a050"))
			"thrust": _r(img, 2, 7, 10, 2, c); _r(img, 12, 6, 2, 4, c); _r(img, 14, 7, 1, 2, c)
			"smash": _r(img, 7, 2, 2, 8, c); _r(img, 4, 10, 8, 2, c); _r(img, 2, 13, 12, 1, c)
			"spin":
				for i in 12:
					var a := i / 12.0 * TAU
					_r(img, int(7.5 + cos(a) * 5), int(7.5 + sin(a) * 5), 1, 1, c)
				_r(img, 7, 7, 2, 2, c)
			"shoot": _r(img, 2, 7, 11, 1, c); _r(img, 11, 5, 1, 5, c); _r(img, 12, 6, 2, 3, c); _r(img, 2, 6, 2, 3, Color("c8a050"))
			"guard": _r(img, 4, 3, 8, 8, c); _r(img, 5, 11, 6, 2, c); _r(img, 7, 13, 2, 1, c); _r(img, 6, 5, 4, 4, bg)
			_:
				_r(img, 7, 2, 2, 12, c); _r(img, 2, 7, 12, 2, c); _r(img, 5, 5, 6, 6, c.darkened(0.1))
				if s.get("cls", "") == "chrono": _r(img, 7, 4, 2, 4, bg); _r(img, 8, 7, 3, 2, bg)
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## 기본 행동 아이콘 (키 설정창용)
static func action_icon(action: String) -> Texture2D:
	var key := "a/" + action
	if _cache.has(key): return _cache[key]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var c := Color("f4f0e0")
	var bg := Color("2a3050")
	_r(img, 0, 0, 16, 16, bg)
	match action:
		"attack": for i in 10: _r(img, 3 + i, 12 - i, 2, 1, c)
		"dash": _r(img, 2, 7, 9, 2, c); _r(img, 10, 5, 2, 6, c); _r(img, 12, 6, 2, 4, c); _r(img, 1, 4, 4, 1, c); _r(img, 1, 11, 4, 1, c)
		"parry": _r(img, 4, 3, 8, 8, c); _r(img, 5, 11, 6, 2, c); _r(img, 6, 5, 4, 4, bg)
		"interact": _r(img, 5, 3, 3, 9, c); _r(img, 8, 6, 3, 6, c); _r(img, 4, 10, 8, 3, c)
		"item_potion": return item_icon("potion")
		"item_herb": return item_icon("herb_bundle")
		"item_candy": return item_icon("stamina_candy")
		"menu": _r(img, 3, 4, 10, 2, c); _r(img, 3, 7, 10, 2, c); _r(img, 3, 10, 10, 2, c)
		_:
			_r(img, 2, 3, 12, 10, c); _r(img, 3, 6, 10, 6, bg)
			var letter := {"win_inventory": Color("e0b060"), "win_equipment": Color("a0c0ff"), "win_stats": Color("ff9070"),
				"win_skills": Color("c090ff"), "win_keyconfig": Color("90e0a0"), "win_worldmap": Color("70d0d0"), "win_codex": Color("e0e080"), "minimap": Color("80b0e0")}
			_r(img, 6, 8, 4, 2, letter.get(action, c))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

# =====================================================================
# 몬스터·지형 (임시)
# =====================================================================
static func enemy_texture(kind: String) -> Texture2D:
	var key := "e/" + kind
	if _cache.has(key): return _cache[key]
	var tex := _path_tex("res://assets/sprites/enemies/%s.png" % kind)
	if tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		match kind:
			"dummy":
				_r(img, 15, 12, 2, 18, Color("7a522a")); _r(img, 8, 15, 16, 3, Color("7a522a"))
				_r(img, 11, 12, 10, 11, Color("d8b870")); _r(img, 12, 4, 8, 8, Color("e8cc88"))
				_r(img, 14, 7, 1, 1, OUTLINE); _r(img, 17, 7, 1, 1, OUTLINE); _r(img, 11, 18, 10, 1, Color("a07a40"))
			"test_brute":
				_r(img, 9, 8, 14, 18, Color("5a4a7a")); _r(img, 7, 12, 18, 12, Color("4a3a66"))
				_r(img, 11, 5, 10, 8, Color("6a5a8a")); _r(img, 13, 9, 2, 2, Color("ff6a6a")); _r(img, 17, 9, 2, 2, Color("ff6a6a"))
				_r(img, 9, 26, 3, 3, Color("4a3a66")); _r(img, 15, 26, 3, 4, Color("4a3a66")); _r(img, 20, 26, 3, 3, Color("4a3a66"))
				_r(img, 15, 15, 2, 3, Color("bff3ff"))
		tex = ImageTexture.create_from_image(_outline(img))
	_cache[key] = tex
	return tex

static func tile_texture(kind: String, variant := 0) -> Texture2D:
	var key := "t/%s/%d" % [kind, variant]
	if _cache.has(key): return _cache[key]
	var tex := _path_tex("res://assets/sprites/tiles/%s_%d.png" % [kind, variant])
	if tex == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var img: Image
		match kind:
			"grass", "flowers":
				img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
				img.fill(Color("5f9e48"))
				for i in 10:
					_r(img, rng.randi_range(0, 15), rng.randi_range(0, 14), 1, 2, Color("4f8a3c") if rng.randf() < 0.6 else Color("78b85a"))
				if kind == "flowers":
					for i in 3:
						var fc: Color = [Color("f4f0e0"), Color("f0d060"), Color("e890b0")][rng.randi() % 3]
						var p := Vector2i(rng.randi_range(1, 13), rng.randi_range(1, 13))
						_r(img, p.x, p.y, 1, 1, fc); _r(img, p.x + 1, p.y + 1, 1, 1, fc.darkened(0.2))
			"stone":
				img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
				img.fill(Color("8a8478"))
				_r(img, 0, 0, 16, 1, Color("6e695f")); _r(img, 0, 0, 1, 16, Color("6e695f"))
				_r(img, 8, 8, 8, 1, Color("6e695f")); _r(img, 8, 8, 1, 8, Color("6e695f"))
				for i in 4: _r(img, rng.randi_range(1, 14), rng.randi_range(1, 14), 1, 1, Color("a29c8f"))
			"tree":
				img = Image.create(32, 40, false, Image.FORMAT_RGBA8)
				_r(img, 13, 28, 6, 11, Color("6b4423"))
				_r(img, 3, 8, 26, 20, Color("2f6b2a")); _r(img, 6, 3, 20, 28, Color("2f6b2a"))
				_r(img, 7, 5, 12, 8, Color("3f8a35")); _r(img, 4, 12, 6, 6, Color("3f8a35"))
				_r(img, 3, 24, 26, 4, Color("245322"))
				img = _outline(img)
			"rock":
				img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
				_r(img, 2, 5, 12, 9, Color("8a8f98")); _r(img, 3, 4, 10, 10, Color("8a8f98"))
				_r(img, 4, 5, 6, 3, Color("b0b5bd")); _r(img, 3, 11, 10, 3, Color("5f646c"))
				img = _outline(img)
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func soft_light(radius: int) -> Texture2D:
	var key := "light/%d" % radius
	if _cache.has(key): return _cache[key]
	var g := GradientTexture2D.new()
	g.width = radius * 2; g.height = radius * 2
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	_cache[key] = g
	return g
