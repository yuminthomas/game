class_name LayeredCharacter
extends Node2D
## 레이어 캐릭터 (GDD 11-3): 그림자 → 뒷망토 → 몸 → 신발 → 갑옷 → 장갑 → 결정 무늬 → 머리 → 투구 → 무기 → 앞망토.
## 원점은 발밑 중앙. 시트 규격은 docs/ASSETS.md.

const ORDER := ["cape_back", "body", "feet", "armor", "hands", "crystal", "hair", "helmet", "cape_front"]
const DIR_ROWS := [2, 1, 0, 1, 2, 3, 4, 3]       # 8방향(오른쪽부터 시계방향) → 시트 행
const DIR_FLIP := [false, false, false, true, true, true, false, false]
const HAND := [Vector2(2, -9), Vector2(6, -9), Vector2(7, -10), Vector2(-6, -9), Vector2(-2, -9), Vector2(-6, -10), Vector2(-7, -10), Vector2(6, -10)]

var layers := {}
var variants := {}
var tints := {}
var shadow: Sprite2D
var weapon_sprite: Sprite2D
var anim := "idle"
var anim_speed := 1.0
var anim_loop := true
var frame_t := 0.0
var frame := 0
var dir8 := 2                  # 0 오른쪽, 2 아래, 4 왼쪽, 6 위
var weapon_angle_override = null   # null 이면 기본 자세
var weapon_extend := 0.0
var weapon_class := "sword"
var weapon_id := ""

func _ready() -> void:
	shadow = Sprite2D.new()
	shadow.texture = _shadow_tex()
	shadow.position = Vector2(0, -1)
	shadow.modulate = Color(0, 0, 0, 0.35)
	add_child(shadow)
	for l in ORDER:
		var s := Sprite2D.new()
		s.centered = false
		s.position = Vector2(-24, -42)
		s.use_parent_material = true
		layers[l] = s
		add_child(s)
		variants[l] = "default"
		tints[l] = Color.WHITE
	weapon_sprite = Sprite2D.new()
	weapon_sprite.centered = false
	weapon_sprite.offset = -SpriteFactory.WEAPON_PIVOT
	weapon_sprite.use_parent_material = true
	add_child(weapon_sprite)
	move_child(weapon_sprite, get_child_count() - 2)   # 앞망토 바로 아래
	variants.armor = "none"; variants.helmet = "none"; variants.crystal = "0"
	_refresh_all()

static var _shadow: Texture2D
func _shadow_tex() -> Texture2D:
	if _shadow == null:
		var img := Image.create(14, 5, false, Image.FORMAT_RGBA8)
		for x in 14:
			for y in 5:
				var dx := (x - 6.5) / 7.0
				var dy := (y - 2.0) / 2.5
				if dx * dx + dy * dy <= 1.0: img.set_pixel(x, y, Color.WHITE)
		_shadow = ImageTexture.create_from_image(img)
	return _shadow

## 장비·외형 반영. look = {hair, cape, cape_style, armor_color, helmet_style, helmet_color, gloves_color, boots_color, crystal, weapon_id}
func apply_look(look: Dictionary) -> void:
	tints.hair = SpriteFactory.HAIR_COLORS[int(look.get("hair", 0)) % 6]
	var cape: Color = SpriteFactory.CAPE_COLORS[int(look.get("cape", 0)) % 6]
	tints.cape_back = cape; tints.cape_front = cape
	variants.cape_back = look.get("cape_style", "default"); variants.cape_front = variants.cape_back
	if look.get("armor_color") != null:
		variants.armor = "plate"; tints.armor = Color(look.armor_color) * 1.25
	else: variants.armor = "none"
	variants.helmet = look.get("helmet_style", "none")
	tints.helmet = Color(look.get("helmet_color", "#a0a0a0")) * 1.25
	tints.hands = Color(look.gloves_color) * 1.3 if look.get("gloves_color") != null else SpriteFactory.SKIN / SpriteFactory.G2.r
	tints.feet = Color(look.get("boots_color", "#5a4030")) * 1.3
	variants.crystal = str(look.get("crystal", 0))
	weapon_id = look.get("weapon_id", "")
	weapon_class = Data.weapons.get(weapon_id, {}).get("class", "sword")
	weapon_sprite.texture = SpriteFactory.weapon_texture(weapon_id) if weapon_id != "" else null
	_refresh_all()

func _refresh_all() -> void:
	for l in ORDER:
		var s: Sprite2D = layers[l]
		s.texture = SpriteFactory.player_sheet(l, variants[l], anim)
		s.hframes = SpriteFactory.anim_frames(anim)
		s.vframes = SpriteFactory.DIRS
		s.modulate = tints[l]
	_apply_frame()

func play(name: String, speed := 1.0, loop := true) -> void:
	anim_speed = speed
	anim_loop = loop
	if name == anim: return
	anim = name
	frame = 0; frame_t = 0.0
	_refresh_all()

func set_facing(v: Vector2) -> void:
	if v.length() < 0.01: return
	dir8 = posmod(int(round(v.angle() / (PI / 4))), 8)
	_apply_frame()

func _process(delta: float) -> void:
	var dt := Clock.dt(delta, true)
	var n := SpriteFactory.anim_frames(anim)
	frame_t += dt * 10.0 * anim_speed
	while frame_t >= 1.0:
		frame_t -= 1.0
		frame += 1
		if frame >= n: frame = 0 if anim_loop else n - 1
	_apply_frame()

func _apply_frame() -> void:
	var row: int = DIR_ROWS[dir8]
	var flip: bool = DIR_FLIP[dir8]
	for l in ORDER:
		var s: Sprite2D = layers[l]
		s.frame = row * s.hframes + mini(frame, s.hframes - 1)
		s.flip_h = flip
		s.position.x = -24 if not flip else -24
	_update_weapon()

func _update_weapon() -> void:
	if weapon_sprite == null: return
	var face := Vector2.from_angle(dir8 * PI / 4)
	weapon_sprite.position = HAND[dir8] + Vector2.from_angle(weapon_sprite.rotation) * weapon_extend
	var ang: float
	if weapon_angle_override != null: ang = weapon_angle_override
	elif weapon_class in ["bow", "staff"]: ang = face.angle() - (0.0 if weapon_class == "bow" else 0.9 * signf(face.x if abs(face.x) > 0.1 else 1.0))
	else: ang = face.angle() + (1.1 if face.x >= -0.1 else -1.1)
	weapon_sprite.rotation = ang
	weapon_sprite.flip_v = cos(ang) < 0 and weapon_class != "bow"
	weapon_sprite.z_index = -1 if dir8 in [5, 6, 7] else 0

## 대시 잔상 (청백색 반투명)
func make_ghost() -> Node2D:
	var g := Node2D.new()
	g.global_position = global_position
	g.z_index = z_index - 1
	for l in ORDER:
		var s: Sprite2D = layers[l].duplicate()
		s.use_parent_material = false
		s.material = null
		g.add_child(s)
	g.modulate = Color(0.7, 0.95, 1.0, 0.55)
	return g
