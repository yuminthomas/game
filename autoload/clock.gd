extends Node
## 게임 시간 배율. 히트스톱, 저스트 회피 슬로우, 시간 정지를 한곳에서 관리한다.
## 게임 로직은 delta 대신 Clock.dt(delta, is_player) 를 쓴다.

var hitstop_frames := 0
var world_slow := 1.0        # 적·투사체에 적용 (저스트 회피 시 0.3)
var _slow_left := 0.0        # 실시간 기준 남은 시간
var time_stopped := false    # 크로노 '시간 정지' 중 적 정지
var game_time := 0.0         # 일시정지·히트스톱 제외 누적 시간

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = 100   # 다른 노드가 이번 프레임을 다 처리한 뒤에 줄인다

func _physics_process(delta: float) -> void:
	if hitstop_frames > 0:
		hitstop_frames -= 1
		return
	game_time += delta
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0: world_slow = 1.0

func hitstop(frames: int) -> void:
	hitstop_frames = max(hitstop_frames, frames)

func slow_world(scale: float, duration: float) -> void:
	world_slow = scale
	_slow_left = duration

func in_hitstop() -> bool:
	return hitstop_frames > 0

## 엔티티별 delta. 히트스톱 중엔 0.
func dt(delta: float, is_player := false) -> float:
	if hitstop_frames > 0: return 0.0
	return delta if is_player else delta * world_slow

func reset() -> void:
	hitstop_frames = 0; world_slow = 1.0; _slow_left = 0.0; time_stopped = false
