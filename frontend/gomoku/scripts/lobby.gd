# lobby.gd — 로컬 대전 / 방 만들기 / 방 참가

extends Control

@onready var status_label: Label = $RootMargin/HBox/MenuCenter/VBox/StatusLabel
@onready var room_input: LineEdit = $RootMargin/HBox/MenuCenter/VBox/JoinChoices/RoomInput
@onready var single_player_choices: HBoxContainer = $RootMargin/HBox/MenuCenter/VBox/SinglePlayerChoices
@onready var join_choices: HBoxContainer = $RootMargin/HBox/MenuCenter/VBox/JoinChoices
@onready var quick_match_button: Button = $RootMargin/HBox/MenuCenter/VBox/QuickMatchButton

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_configure_server_urls()
	_style_primary_button(quick_match_button)
	status_label.text = "모드를 선택하세요."


func _style_primary_button(btn: Button) -> void:
	# 빠른 대전만 앰버 포인트 (모던 로비 강조)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.90, 0.62, 0.18, 1)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 16
	normal.content_margin_top = 10
	normal.content_margin_right = 16
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.96, 0.70, 0.28, 1)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.78, 0.52, 0.12, 1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.10, 0.08, 0.05, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.04, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.03, 1))


func _configure_server_urls() -> void:
	# 웹: 같은 오리진(nginx). 데스크톱: 로컬 백엔드 기본값 유지.
	if not OS.has_feature("web"):
		return
	var origin := str(JavaScriptBridge.eval("window.location.origin", true)).strip_edges().trim_suffix("/")
	if origin.is_empty() or origin == "null":
		return
	GameSession.server_http = origin
	if origin.begins_with("https://"):
		GameSession.server_ws = "wss://" + origin.substr(8)
	elif origin.begins_with("http://"):
		GameSession.server_ws = "ws://" + origin.substr(7)


func _on_single_player_pressed() -> void:
	join_choices.visible = false
	single_player_choices.visible = not single_player_choices.visible


func _on_join_menu_pressed() -> void:
	single_player_choices.visible = false
	join_choices.visible = not join_choices.visible
	if join_choices.visible:
		room_input.grab_focus()


func _on_local_pressed() -> void:
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://board.tscn")


func _on_ai_pressed() -> void:
	GameSession.start_ai_match()
	get_tree().change_scene_to_file("res://board.tscn")


func _on_quick_match_pressed() -> void:
	_configure_server_urls()
	GameSession.start_quick_match()
	get_tree().change_scene_to_file("res://board.tscn")


func _on_create_pressed() -> void:
	_configure_server_urls()
	status_label.text = "방 생성 중…"
	var err := _http.request(
		GameSession.server_http + "/api/rooms",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		""
	)
	if err != OK:
		status_label.text = "요청 실패 (서버 연결 확인)"


func _on_join_pressed() -> void:
	_configure_server_urls()
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
