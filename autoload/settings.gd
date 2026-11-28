extends Node
## 설정 저장 (user://settings.cfg). 게임 진행 저장과 분리된다 (GDD 12-8).

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"gameplay": {"shake": 1.0, "damage_numbers": true, "aim_assist": true, "hud_scale": 1.0, "hud_fade": false},
	"control": {"input_buffer": 0.15, "wasd": false},
	"debug": {"hitboxes": false},
}

var cfg := ConfigFile.new()

func _ready() -> void:
	var err := cfg.load(PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("[Settings] 설정 파일을 읽지 못함: %d" % err)

func get_value(section: String, key: String, default = null):
	if default == null: default = DEFAULTS.get(section, {}).get(key)
	if not cfg.has_section_key(section, key): return default
	return cfg.get_value(section, key)

func set_value(section: String, key: String, value, save_now := true) -> void:
	cfg.set_value(section, key, value)
	if save_now: save()
	changed.emit(section, key)

func save() -> void:
	var err := cfg.save(PATH)
	if err != OK: push_warning("[Settings] 저장 실패: %d" % err)

# 창 위치 (메이플식 위치 기억)
func window_pos(id: String, default: Vector2) -> Vector2:
	return cfg.get_value("windows", id, default)

func set_window_pos(id: String, pos: Vector2) -> void:
	set_value("windows", id, pos)
