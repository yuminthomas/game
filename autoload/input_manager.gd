extends Node
## 입력 시스템: 키 배치(메이플식 키→기능), 재설정, 선입력 버퍼, 설정 저장. GDD 5-1, 12-4.

signal bindings_changed

const MOVE_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const REQUIRED := ["attack", "dash", "menu"]   # 비울 수 없는 기능 (이동은 별도 고정)
## 배정 가능한 기능 목록. 키 설정창 아래 팔레트에 이 순서로 나온다.
const BINDABLE := {
	"basic": ["attack", "dash", "parry", "interact"],
	"skill": ["slot_skill_1", "slot_skill_2", "slot_skill_3", "slot_skill_4", "slot_chrono_1", "slot_chrono_2"],
	"item": ["item_potion", "item_herb", "item_candy"],
	"window": ["win_inventory", "win_equipment", "win_stats", "win_skills", "win_keyconfig", "win_worldmap", "win_codex", "minimap", "menu"],
}
const DEFAULT_KEYS := {
	KEY_X: "attack", KEY_Z: "dash", KEY_C: "parry", KEY_SPACE: "interact",
	KEY_A: "slot_skill_1", KEY_S: "slot_skill_2", KEY_D: "slot_skill_3", KEY_F: "slot_skill_4",
	KEY_Q: "slot_chrono_1", KEY_W: "slot_chrono_2",
	KEY_1: "item_potion", KEY_2: "item_herb", KEY_3: "item_candy",
	KEY_I: "win_inventory", KEY_E: "win_equipment", KEY_T: "win_stats", KEY_K: "win_skills",
	KEY_O: "win_keyconfig", KEY_M: "win_worldmap", KEY_J: "win_codex", KEY_TAB: "minimap", KEY_ESCAPE: "menu",
}
const ARROWS := {KEY_UP: "move_up", KEY_DOWN: "move_down", KEY_LEFT: "move_left", KEY_RIGHT: "move_right"}
const WASD := {KEY_W: "move_up", KEY_S: "move_down", KEY_A: "move_left", KEY_D: "move_right"}

var keymap := {}            # keycode(int) -> action(String)
var wasd := false
var blocked := false        # 콘솔 입력 중 등 게임 입력 차단
var _pressed_at := {}       # action -> 눌린 시각(초)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_bindings()

func all_actions() -> Array:
	var out := MOVE_ACTIONS.duplicate()
	for cat in BINDABLE: out += BINDABLE[cat]
	return out

func move_keys() -> Dictionary:
	return WASD if wasd else ARROWS

# ---------- 저장/불러오기 ----------
func load_bindings() -> void:
	wasd = Settings.get_value("control", "wasd", false)
	var saved = Settings.get_value("keys", "map", null)
	keymap = {}
	if saved is Dictionary and not saved.is_empty():
		for k in saved: keymap[int(k)] = String(saved[k])
	else:
		keymap = DEFAULT_KEYS.duplicate()
		if wasd: _strip_move_keys(keymap)
	_apply()

func save_bindings() -> void:
	var out := {}
	for k in keymap: out[str(k)] = keymap[k]
	Settings.set_value("keys", "map", out, false)
	Settings.set_value("control", "wasd", wasd)

func defaults() -> Dictionary:
	var d := DEFAULT_KEYS.duplicate()
	if wasd: _strip_move_keys(d)
	return d

func _strip_move_keys(map: Dictionary) -> void:
	for k in WASD: map.erase(k)

## 편집용 복사본을 검증해서 적용. 필수 기능이 빠졌으면 그 이름 목록을 돌려준다.
func missing_required(map: Dictionary) -> Array:
	var have := map.values()
	var miss := []
	for r in REQUIRED:
		if not r in have: miss.append(r)
	return miss

func commit(map: Dictionary, use_wasd: bool) -> Array:
	var miss := missing_required(map)
	if not miss.is_empty(): return miss
	wasd = use_wasd
	keymap = map.duplicate()
	if wasd: _strip_move_keys(keymap)
	_apply()
	save_bindings()
	return []

## 키에 기능 배치. 기능이 이미 다른 키에 있으면 서로 자리를 바꾼다 (GDD 12-4).
static func assign(map: Dictionary, keycode: int, action: String) -> void:
	var old_key := -1
	for k in map:
		if map[k] == action: old_key = k
	var displaced = map.get(keycode)
	map[keycode] = action
	if old_key != -1 and old_key != keycode:
		if displaced != null: map[old_key] = displaced
		else: map.erase(old_key)

func _apply() -> void:
	for a in all_actions():
		if not InputMap.has_action(a): InputMap.add_action(a, 0.2)
		InputMap.action_erase_events(a)
	var mk := move_keys()
	for k in mk: _add_key(mk[k], k)
	if wasd:
		for k in ARROWS: _add_key(ARROWS[k], k)   # WASD 모드에서도 방향키 이동은 유지
	for k in keymap:
		if keymap[k] in all_actions(): _add_key(keymap[k], k)
	bindings_changed.emit()

func _add_key(action: String, keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func key_for(action: String) -> int:
	for k in keymap:
		if keymap[k] == action: return k
	return -1

func key_label(keycode: int) -> String:
	if keycode < 0: return "-"
	match keycode:
		KEY_SPACE: return "Spc"
		KEY_ESCAPE: return "Esc"
		KEY_TAB: return "Tab"
		KEY_SHIFT: return "Shft"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_ENTER: return "Ent"
		KEY_BACKSPACE: return "BS"
		KEY_QUOTELEFT: return "`"
	return OS.get_keycode_string(keycode)

# ---------- 선입력 버퍼 ----------
func _process(_dt: float) -> void:
	if blocked: return
	var now := Time.get_ticks_msec() / 1000.0
	for a in all_actions():
		if Input.is_action_just_pressed(a): _pressed_at[a] = now

func buffer_time() -> float:
	return float(Settings.get_value("control", "input_buffer", Data.bal("control.input_buffer", 0.15)))

## 최근(버퍼 시간 안)에 눌렸으면 true. 소비하지 않는다.
func buffered(action: String) -> bool:
	if blocked or not _pressed_at.has(action): return false
	return Time.get_ticks_msec() / 1000.0 - _pressed_at[action] <= buffer_time()

## 버퍼에 있으면 꺼내 쓰고 true.
func consume(action: String) -> bool:
	if buffered(action):
		_pressed_at.erase(action)
		return true
	return false

func clear_buffer() -> void:
	_pressed_at.clear()

func held(action: String) -> bool:
	return not blocked and InputMap.has_action(action) and Input.is_action_pressed(action)

func move_vector() -> Vector2:
	if blocked: return Vector2.ZERO
	var v := Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	return v.normalized() if v.length() > 0.1 else Vector2.ZERO
