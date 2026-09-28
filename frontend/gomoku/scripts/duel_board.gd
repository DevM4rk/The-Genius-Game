# duel_board.gd — 공용 1:1 방(duel_*)을 쓰는 온라인 게임 화면 뼈대
#
# 화면 틀(상단바·제목·점수·안내문), 네트워크, 게임 종료/규칙 창을 코드로 만든다.
# 게임별 스크립트는 이 파일을 extends 하고 아래 가상 함수만 채운다.
#   _game_id()        catalog id
#   _build_content()  content(VBoxContainer)에 게임 UI 추가
#   _render_state()   서버가 보낸 duel_state 그리기
#   _end_lines() / _history_lines()  종료 창 내용
extends Control

const NetworkClientScript := preload("res://scripts/network_client.gd")
const LobbyTheme := preload("res://theme/lobby_theme.tres")
const Parchment := preload("res://art/bg_parchment.png")
const INK := Color(0.25, 0.20, 0.14, 1)
const MUTED := Color(0.40, 0.35, 0.28, 1)
const ACCENT := Color(0.55, 0.32, 0.08, 1)
const END_DELAY_SEC := 1.2

var net: Node = null
var my_index: int = -1
var state: Dictionary = {}
var content: VBoxContainer
var status_label: Label
var score_label: Label
var prompt_label: Label

var _segment_shown: int = -1
var _end_shown_segment: int = -1
var _end_overlay: Control
var _end_title: Label
var _end_body: Label
var _end_history: VBoxContainer
var _rules_overlay: Control
var _rules_text: RichTextLabel


# ── 게임별로 채우는 부분 ───────────────────────────────────────

func _game_id() -> String:
	return ""


func _build_content() -> void:
	pass


func _render_state(_data: Dictionary) -> void:
	pass


func _end_lines(_data: Dictionary) -> PackedStringArray:
	return PackedStringArray()


func _history_lines(_data: Dictionary) -> PackedStringArray:
	return PackedStringArray()


func _on_action_error(_code: String) -> void:
	pass


# ── 공용 도우미 ────────────────────────────────────────────────

func make_label(text: String, size: int, color: Color = INK, center: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func make_button(text: String, min_width: float = 120.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_width, 44)
	return btn


func make_card(text: String, bg: Color, fg: Color, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(8)
	style.border_color = Color(0.45, 0.45, 0.50, 1)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	if not text.is_empty():
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(size.y * 0.32))
		label.add_theme_color_override("font_color", fg)
		panel.add_child(label)
	return panel


func make_row(separation: int = 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", separation)
	return row


func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func who(idx: int) -> String:
	return "나" if idx == my_index else "상대"


func outcome_for_me(winner: int) -> String:
	if winner < 0:
		return "무승부"
	return "승" if winner == my_index else "패"


func send_action(action: Dictionary) -> void:
	if net == null:
		return
	var payload := action.duplicate()
	payload["type"] = "duel_action"
	net.send_dict(payload)


# ── 화면 틀 ────────────────────────────────────────────────────

func _ready() -> void:
	theme = LobbyTheme
	_build_layout()
	content.visible = false
	status_label.text = "서버 연결 중…"
	_start_network()


func _build_layout() -> void:
	var bg := TextureRect.new()
	bg.texture = Parchment
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	var back := Button.new()
	back.text = "← 로비"
	back.pressed.connect(_on_lobby_pressed)
	top.add_child(back)
	status_label = make_label("", 13, MUTED, false)
	top.add_child(status_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var rules := Button.new()
	rules.text = "규칙"
	rules.pressed.connect(_on_rules_pressed)
	top.add_child(rules)

	root.add_child(make_label(GameCatalog.display_name(_game_id()), 30, Color(0.18, 0.14, 0.10, 1)))
	score_label = make_label("", 22, ACCENT)
	root.add_child(score_label)
	prompt_label = make_label("", 15, INK)
	root.add_child(prompt_label)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	_build_content()

	_build_end_overlay()
	_build_rules_overlay()


func _make_overlay(width: float) -> Array:
	var overlay := Control.new()
	overlay.visible = false
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.14, 0.88)
	style.set_corner_radius_all(14)
	style.border_color = Color(1, 1, 1, 0.28)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_%s" % side, 22)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	return [overlay, v]


func _build_end_overlay() -> void:
	var parts := _make_overlay(480)
	_end_overlay = parts[0]
	var v: VBoxContainer = parts[1]
	_end_title = make_label("", 26, Color(0.98, 0.98, 0.99, 1))
	v.add_child(_end_title)
	_end_body = make_label("", 16, Color(0.92, 0.68, 0.28, 1))
	v.add_child(_end_body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	v.add_child(scroll)
	_end_history = VBoxContainer.new()
	_end_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_history.add_theme_constant_override("separation", 4)
	scroll.add_child(_end_history)
	var buttons := make_row(10)
	v.add_child(buttons)
	var rematch := make_button("다시 시작", 160)
	rematch.pressed.connect(_on_rematch_pressed)
	buttons.add_child(rematch)
	var lobby := make_button("로비로", 160)
	lobby.pressed.connect(_on_lobby_pressed)
	buttons.add_child(lobby)


func _build_rules_overlay() -> void:
	var parts := _make_overlay(480)
	_rules_overlay = parts[0]
	var v: VBoxContainer = parts[1]
	v.add_child(make_label("게임 규칙", 20, Color(0.96, 0.96, 0.97, 1)))
	_rules_text = RichTextLabel.new()
	_rules_text.custom_minimum_size = Vector2(0, 300)
	_rules_text.scroll_active = true
	_rules_text.add_theme_color_override("default_color", Color(0.85, 0.86, 0.89, 1))
	v.add_child(_rules_text)
	var close := make_button("닫기")
	close.pressed.connect(func() -> void: _rules_overlay.visible = false)
	v.add_child(close)


# ── 네트워크 ───────────────────────────────────────────────────

func _start_network() -> void:
	if GameSession.net != null and is_instance_valid(GameSession.net):
		net = GameSession.net
		net.message.connect(_on_net_message)
		net.disconnected.connect(_on_net_disconnected)
		status_label.text = "동기화 중…"
		for pending in GameSession.take_pending_messages():
			_on_net_message(pending)
		return

	net = NetworkClientScript.new()
	add_child(net)
	net.message.connect(_on_net_message)
	net.disconnected.connect(_on_net_disconnected)
	GameSession.game_id = _game_id()
	net.connect_to_room(GameSession.quick_ws_url())


func _on_net_message(data: Dictionary) -> void:
	var t := str(data.get("type", ""))
	match t:
		"queued":
			status_label.text = "상대를 찾는 중…"
		"matched":
			GameSession.room_id = str(data.get("room_id", ""))
		"duel_joined":
			my_index = int(data.get("you", -1))
		"duel_waiting":
			status_label.text = "상대를 기다리는 중…"
			prompt_label.text = "상대를 기다리는 중입니다…"
			content.visible = false
		"duel_state":
			_apply_state(data)
		"duel_opponent_left":
			_end_overlay.visible = false
			content.visible = false
			status_label.text = "상대가 나갔습니다."
			prompt_label.text = "상대가 나갔습니다. 로비로 돌아가 새 매칭을 시작하세요."
		"error":
			var code := str(data.get("message", ""))
			status_label.text = "오류: %s" % _error_text(code)
			_on_action_error(code)
		_:
			pass


func _error_text(code: String) -> String:
	match code:
		"invalid_bet":
			return "걸 수 없는 칩 수입니다."
		"invalid_hand":
			return "가위·바위·보 중 하나를 고르세요."
		"already_submitted":
			return "이번 라운드는 이미 냈습니다."
		"not_your_turn":
			return "지금은 내 차례가 아닙니다."
		"game_already_over":
			return "이미 끝난 게임입니다."
		"invalid_cards":
			return "카드 3장을 골라 주세요."
		_:
			return code


func _on_net_disconnected() -> void:
	status_label.text = "서버 연결이 끊겼습니다."


func _apply_state(data: Dictionary) -> void:
	var seg := int(data.get("segment", 0))
	if seg != _segment_shown:
		_segment_shown = seg
		_end_overlay.visible = false
	state = data
	my_index = int(data.get("you", my_index))
	status_label.text = "방 %s" % GameSession.room_id
	content.visible = true
	_render_state(data)

	if bool(data.get("is_over", false)) and _end_shown_segment != seg:
		_end_shown_segment = seg
		await get_tree().create_timer(END_DELAY_SEC).timeout
		if not is_instance_valid(self) or _segment_shown != seg:
			return
		_show_end(state)


func _show_end(data: Dictionary) -> void:
	var winner := int(data.get("winner", -1))
	if winner < 0:
		_end_title.text = "무승부"
	elif winner == my_index:
		_end_title.text = "승리!"
	else:
		_end_title.text = "패배"
	_end_body.text = "\n".join(_end_lines(data))
	clear_children(_end_history)
	for line in _history_lines(data):
		var label := make_label(line, 13, Color(0.88, 0.89, 0.92, 1), false)
		_end_history.add_child(label)
	_end_overlay.visible = true


func _on_rematch_pressed() -> void:
	_end_overlay.visible = false
	if net:
		net.send_dict({"type": "duel_rematch"})
	status_label.text = "다음 판을 준비하는 중…"


func _on_lobby_pressed() -> void:
	if net != null and is_instance_valid(net) and net != GameSession.net:
		net.disconnect_from_room()
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://ui/genius_lobby.tscn")


func _on_rules_pressed() -> void:
	_rules_text.text = str(GameCatalog.by_id(_game_id()).get("rules_text", "설명이 없습니다."))
	_rules_overlay.visible = true
