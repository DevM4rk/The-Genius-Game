# lobby.gd — 로컬 대전 / 방 만들기 / 방 참가

extends Control

@onready var status_label: Label = $Center/VBox/StatusLabel
@onready var room_input: LineEdit = $Center/VBox/RoomRow/RoomInput
@onready var server_input: LineEdit = $Center/VBox/ServerInput

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	server_input.text = GameSession.server_http
	status_label.text = "로컬 또는 온라인 대전을 선택하세요."


func _apply_server_urls() -> void:
	var base := server_input.text.strip_edges().trim_suffix("/")
	GameSession.server_http = base
	if base.begins_with("https://"):
		GameSession.server_ws = "wss://" + base.substr(8)
	elif base.begins_with("http://"):
		GameSession.server_ws = "ws://" + base.substr(7)
	else:
		GameSession.server_http = "http://" + base
		GameSession.server_ws = "ws://" + base


func _on_local_pressed() -> void:
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://board.tscn")


func _on_quick_match_pressed() -> void:
	_apply_server_urls()
	GameSession.start_quick_match()
	get_tree().change_scene_to_file("res://board.tscn")


func _on_create_pressed() -> void:
	_apply_server_urls()
	status_label.text = "방 생성 중…"
	var err := _http.request(
		GameSession.server_http + "/api/rooms",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		""
	)
	if err != OK:
		status_label.text = "요청 실패 (서버 주소/실행 확인)"


func _on_join_pressed() -> void:
	_apply_server_urls()
	var rid := room_input.text.strip_edges().to_lower()
	if rid.is_empty():
		status_label.text = "방 코드를 입력하세요."
		return
	GameSession.start_online(rid)
	get_tree().change_scene_to_file("res://board.tscn")


func _on_http_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if response_code != 200:
		status_label.text = "방 생성 실패 (HTTP %d). 서버가 켜져 있는지 확인하세요." % response_code
		return

	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("room_id"):
		status_label.text = "응답 파싱 실패"
		return

	var rid: String = str(data["room_id"])
	room_input.text = rid
	status_label.text = "방 코드: %s — 입장합니다…" % rid
	GameSession.start_online(rid)
	get_tree().change_scene_to_file("res://board.tscn")
