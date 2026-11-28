extends Node
## UI 문구 모음 (GDD 12-8 "모든 문구를 한 파일에"). data/text_ko.json 에서 읽는다.

var strings := {}

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/text_ko.json"))
	if parsed is Dictionary: strings = parsed
	else: push_error("[Text] data/text_ko.json 을 읽을 수 없음")

## 키가 없으면 키 자체를 돌려준다. args 가 있으면 % 포맷.
func t(key: String, args = null) -> String:
	var s: String = strings.get(key, key)
	if args != null: return s % args
	return s
