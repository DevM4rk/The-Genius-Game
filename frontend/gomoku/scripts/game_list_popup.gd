# game_list_popup.gd — 게임목록 공통 팝업 (규칙 / 혼자하기 / 매칭선택)
class_name GameListPopup
extends Control

enum Mode { RULES, SOLO, MATCH_PICK }

signal closed
signal start_requested(game_id: String, local_hotseat: bool, prefer_first: bool)
signal match_pick_confirmed(game_id: String)

@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _list: VBoxContainer = $Panel/Margin/VBox/ListScroll/List
@onready var _detail: RichTextLabel = $Panel/Margin/VBox/Detail
@onready var _solo_row: HBoxContainer = $Panel/Margin/VBox/SoloRow
@onready var _solo_toggle: CheckButton = $Panel/Margin/VBox/SoloRow/SoloToggle
@onready var _solo_hint: Label = $Panel/Margin/VBox/SoloRow/SoloHint
@onready var _turn_row: HBoxContainer = $Panel/Margin/VBox/TurnRow
@onready var _turn_toggle: CheckButton = $Panel/Margin/VBox/TurnRow/TurnToggle
@onready var _turn_hint: Label = $Panel/Margin/VBox/TurnRow/TurnHint
@onready var _action_row: HBoxContainer = $Panel/Margin/VBox/ActionRow
@onready var _action_button: Button = $Panel/Margin/VBox/ActionRow/ActionButton
@onready var _panel: PanelContainer = $Panel

var _mode: Mode = Mode.RULES
var _selected_id: String = ""
var _list_group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	visible = false
	_list_group.allow_unpress = false
	_style_panel()
	_solo_toggle.toggled.connect(_on_solo_toggle_toggled)
	_turn_toggle.toggled.connect(_on_turn_toggle_toggled)
	_refresh_solo_hint()
	_refresh_turn_hint()


func _style_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.18, 1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 4
	style.content_margin_top = 4
	style.content_margin_right = 4
	style.content_margin_bottom = 4
	style.border_color = Color(0.35, 0.37, 0.42, 1)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	_title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.97, 1))
	_detail.add_theme_color_override("default_color", Color(0.82, 0.84, 0.88, 1))
	_solo_hint.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88, 1))
	_turn_hint.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88, 1))


func open(mode: Mode) -> void:
	_mode = mode
	_selected_id = ""
	_detail.text = ""
	_detail.visible = false
	_rebuild_list()
	match _mode:
		Mode.RULES:
			_title.text = "게임 규칙"
			_solo_row.visible = false
			_turn_row.visible = false
			_action_row.visible = false
			_detail.visible = true
			_detail.text = "규칙을 볼 게임을 선택하세요."
		Mode.SOLO:
			_title.text = "혼자하기"
			_solo_row.visible = true
			_turn_row.visible = false  # 게임 선택 후 지원 여부에 따라 표시
			_action_row.visible = true
			_action_button.text = "시작"
			_action_button.disabled = true
			_solo_toggle.button_pressed = true
			_turn_toggle.button_pressed = true
			_refresh_solo_hint()
			_refresh_turn_hint()
		Mode.MATCH_PICK:
			_title.text = "게임 선택"
			_solo_row.visible = false
			_turn_row.visible = false
			_action_row.visible = true
			_action_button.text = "확인"
			_action_button.disabled = true
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	for game in GameCatalog.all():
		var btn := Button.new()
		btn.text = str(game.get("name", "?"))
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		btn.button_group = _list_group
		var gid := str(game.get("id", ""))
		btn.pressed.connect(_on_game_pressed.bind(gid))
		_list.add_child(btn)


func _on_game_pressed(game_id: String) -> void:
	_selected_id = game_id
	match _mode:
		Mode.RULES:
			var game := GameCatalog.by_id(game_id)
			_detail.visible = true
			_detail.text = str(game.get("rules_text", "설명이 없습니다."))
		Mode.SOLO:
			_action_button.disabled = _selected_id.is_empty()
			var game := GameCatalog.by_id(game_id)
			_turn_row.visible = bool(game.get("supports_turn_choice", false))
		Mode.MATCH_PICK:
			_action_button.disabled = _selected_id.is_empty()


func _on_solo_toggle_toggled(_pressed: bool) -> void:
	_refresh_solo_hint()


func _on_turn_toggle_toggled(_pressed: bool) -> void:
	_refresh_turn_hint()


func _refresh_solo_hint() -> void:
	if _solo_toggle.button_pressed:
		_solo_hint.text = "혼자(2인)"
	else:
		_solo_hint.text = "AI와 대전"


func _refresh_turn_hint() -> void:
	if _turn_toggle.button_pressed:
		_turn_hint.text = "선"
	else:
		_turn_hint.text = "후"


func _on_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _on_close_pressed() -> void:
	close()


func _on_action_pressed() -> void:
	if _selected_id.is_empty():
		return
	match _mode:
		Mode.SOLO:
			start_requested.emit(
				_selected_id,
				_solo_toggle.button_pressed,
				_turn_toggle.button_pressed
			)
			close()
		Mode.MATCH_PICK:
			match_pick_confirmed.emit(_selected_id)
			close()
		_:
			pass
