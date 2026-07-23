# genius_lobby.gd — 지니어스게임 메인 로비
extends Control

const GameListPopupScene := preload("res://ui/game_list_popup.tscn")

@onready var status_label: Label = $RootMargin/Center/VBox/StatusLabel
@onready var random_match_button: Button = $RootMargin/Center/VBox/RandomMatchButton
@onready var stub_popup: AcceptDialog = $StubDialog
@onready var match_choice: Control = $MatchChoicePopup

var _game_list: GameListPopup


func _ready() -> void:
	_configure_server_urls()
	_style_primary_button(random_match_button)
	_style_match_choice_panel()
	_game_list = GameListPopupScene.instantiate()
	add_child(_game_list)
	_game_list.start_requested.connect(_on_solo_start_requested)
	_game_list.match_pick_confirmed.connect(_on_match_pick_confirmed)
	match_choice.visible = false
	status_label.text = ""


func _style_match_choice_panel() -> void:
	var panel: PanelContainer = $MatchChoicePopup/Panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.18, 1)
	style.set_corner_radius_all(14)
	style.border_color = Color(0.35, 0.37, 0.42, 1)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	$MatchChoicePopup/Panel/Margin/VBox/Title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.97, 1))


func _style_primary_button(btn: Button) -> void:
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


func _on_rules_pressed() -> void:
	_game_list.open(GameListPopup.Mode.RULES)


func _on_solo_pressed() -> void:
	_game_list.open(GameListPopup.Mode.SOLO)


func _on_solo_start_requested(game_id: String, local_hotseat: bool, prefer_first: bool) -> void:
	var game := GameCatalog.by_id(game_id)
	if game.is_empty():
		status_label.text = "알 수 없는 게임입니다."
		return
	var scene_path := str(game.get("scene_path", ""))
	if scene_path.is_empty():
		status_label.text = "게임 씬이 없습니다."
		return
	if local_hotseat:
		GameSession.reset_to_local(game_id, prefer_first)
	else:
		if not bool(game.get("supports_ai", false)):
			status_label.text = "이 게임은 AI 대전을 지원하지 않습니다."
			return
		GameSession.start_ai_match(game_id, prefer_first)
	get_tree().change_scene_to_file(scene_path)


func _on_random_match_pressed() -> void:
	match_choice.visible = true


func _on_match_choice_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_match_choice_close()


func _on_match_choice_close() -> void:
	match_choice.visible = false


func _on_match_choice_a_pressed() -> void:
	match_choice.visible = false
	_game_list.open(GameListPopup.Mode.MATCH_PICK)


func _on_match_choice_b_pressed() -> void:
	match_choice.visible = false
	_enter_quick_queue("")


func _on_match_pick_confirmed(game_id: String) -> void:
	_enter_quick_queue(game_id)


func _enter_quick_queue(game_id: String) -> void:
	_configure_server_urls()
	GameSession.start_quick_match(game_id)
	get_tree().change_scene_to_file("res://ui/match_queue.tscn")


func _on_create_room_pressed() -> void:
	_show_stub("방만들기는 나중에 구현 예정입니다.")


func _show_stub(message: String) -> void:
	stub_popup.dialog_text = message
	stub_popup.popup_centered()
