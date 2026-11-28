extends Node
## 게임 전역 상태: 플레이어 데이터, 현재 월드·플레이어 노드 참조.

signal world_ready
signal message(text: String, color: Color)

var data: PlayerData
var player: Node2D
var world: Node2D
var ui: CanvasLayer
var god_mode := false

func _ready() -> void:
	new_game()

func new_game() -> void:
	data = PlayerData.new()
	data.new_game()

func enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy")

func notify(text: String, color := Color.WHITE) -> void:
	message.emit(text, color)

func in_combat() -> bool:
	return player != null and player.has_method("is_in_combat") and player.is_in_combat()
