extends Node
## 진입점: 테스트 구역과 UI 를 만든다.

func _ready() -> void:
	Clock.reset()
	var zone := TestZone.new()
	add_child(zone)
	var ui := UIRoot.new()
	add_child(ui)
