# game_session.gd — 로비 ↔ 보드 사이 세션 상태 (Autoload)
extends Node

enum Mode { LOCAL, ONLINE, QUICK, AI }

var mode: Mode = Mode.LOCAL
var room_id: String = ""
var my_color: int = -1  # GomokuBoardExt.STONE_* 와 동일 값, 온라인에서만 의미
var server_http: String = "http://127.0.0.1:8000"
var server_ws: String = "ws://127.0.0.1:8000"

func reset_to_local() -> void:
	mode = Mode.LOCAL
	room_id = ""
	my_color = -1

func start_online(p_room_id: String) -> void:
	mode = Mode.ONLINE
	room_id = p_room_id
	my_color = -1

func start_quick_match() -> void:
	mode = Mode.QUICK
	room_id = ""
	my_color = -1

func start_ai_match() -> void:
	mode = Mode.AI
	room_id = ""
	my_color = -1

func ws_url() -> String:
	return "%s/ws/%s" % [server_ws, room_id]

func quick_ws_url() -> String:
	return "%s/ws/quick" % server_ws
