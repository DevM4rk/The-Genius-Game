extends Control
## Lobby: choose AI / private / rank. Brand-first entry for the platform.

@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	GameSession.parse_browser_room_code()
	if not GameSession.url_room_code.is_empty():
		_enter_private(GameSession.url_room_code)


func _on_ai_pressed() -> void:
	GameSession.mode = GameSession.Mode.AI
	GameSession.game_id = "omok"
	status_label.text = "AI 싱글플레이 — 서버 연결 없이 C++ 코어 사용"
	get_tree().change_scene_to_file("res://scenes/omok_board.tscn")


func _on_private_pressed() -> void:
	# Phase 2: POST /rooms then navigate. Phase 0 opens board with placeholder.
	GameSession.mode = GameSession.Mode.PRIVATE
	GameSession.game_id = "omok"
	status_label.text = "사설 방 생성 요청 (백엔드 연동은 Phase 2)"
	_enter_private("")


func _on_rank_pressed() -> void:
	GameSession.mode = GameSession.Mode.RANK
	GameSession.game_id = "omok"
	status_label.text = "랭크 매칭은 Phase 3 (OAuth + Redis)"
	# Keep user on lobby until auth lands.


func _enter_private(code: String) -> void:
	GameSession.room_id = code
	get_tree().change_scene_to_file("res://scenes/omok_board.tscn")
