# black_white2_board.gd — 흑과백2 (온라인 전용)
#
# 서버가 상태의 유일한 권위자다. 상대에 대해서는 낸 포인트의 색(한 자릿수=흑,
# 두 자릿수=백)과 남은 포인트 표시등(5단계)만 받는다. 실제로 낸 포인트와
# 잔액은 게임이 끝난 뒤 기록으로만 받는다.
extends Control

const NetworkClientScript := preload("res://scripts/network_client.gd")
const GAME_ID := "black_white2"
const LAMP_COUNT := 5
const LAMP_STEP := 20
const CARD_SIZE := Vector2(76, 104)
const PREVIEW_SIZE := Vector2(40, 54)
const LAMP_SIZE := Vector2(40, 18)
const LAMP_ON := Color(0.96, 0.68, 0.20, 1)
const LAMP_OFF := Color(0.32, 0.29, 0.25, 0.35)

@onready var status_label: Label = $RootMargin/VBox/TopBar/StatusLabel
@onready var score_label: Label = $RootMargin/VBox/TitleBlock/ScoreLabel
@onready var round_label: Label = $RootMargin/VBox/TitleBlock/RoundLabel
@onready var prompt_label: Label = $RootMargin/VBox/PromptLabel
@onready var opponent_section: VBoxContainer = $RootMargin/VBox/OpponentSection
@onready var opp_lamp_row: HBoxContainer = $RootMargin/VBox/OpponentSection/OppLampRow
@onready var staging_row: HBoxContainer = $RootMargin/VBox/StagingRow
@onready var first_stage_slot: Control = $RootMargin/VBox/StagingRow/FirstStageCol/FirstStageSlot
@onready var first_stage_label: Label = $RootMargin/VBox/StagingRow/FirstStageCol/FirstStageLabel
@onready var second_stage_slot: Control = $RootMargin/VBox/StagingRow/SecondStageCol/SecondStageSlot
@onready var second_stage_label: Label = $RootMargin/VBox/StagingRow/SecondStageCol/SecondStageLabel
@onready var my_section: VBoxContainer = $RootMargin/VBox/MySection
@onready var my_points_label: Label = $RootMargin/VBox/MySection/MyPointsLabel
@onready var my_lamp_row: HBoxContainer = $RootMargin/VBox/MySection/MyLampRow
@onready var bid_row: HBoxContainer = $RootMargin/VBox/BidRow
@onready var bid_spin: SpinBox = $RootMargin/VBox/BidRow/BidSpin
@onready var bid_preview_slot: Control = $RootMargin/VBox/BidRow/BidPreviewSlot
@onready var bid_submit_button: Button = $RootMargin/VBox/BidRow/BidSubmitButton
@onready var bid_hint_label: Label = $RootMargin/VBox/BidHintLabel

@onready var result_overlay: Control = $ResultOverlay
@onready var result_panel: PanelContainer = $ResultOverlay/Panel
@onready var result_label: Label = $ResultOverlay/Panel/Margin/VBox/ResultLabel
@onready var result_detail_label: Label = $ResultOverlay/Panel/Margin/VBox/ScoreDetailLabel
@onready var result_next_button: Button = $ResultOverlay/Panel/Margin/VBox/NextButton

@onready var end_overlay: Control = $MatchEndOverlay
@onready var end_panel: PanelContainer = $MatchEndOverlay/Panel
@onready var end_title_label: Label = $MatchEndOverlay/Panel/Margin/VBox/TitleLabel
@onready var end_score_label: Label = $MatchEndOverlay/Panel/Margin/VBox/FinalScoreLabel
@onready var end_history_list: VBoxContainer = $MatchEndOverlay/Panel/Margin/VBox/HistoryScroll/HistoryList

@onready var rules_overlay: Control = $RulesOverlay
@onready var rules_panel: PanelContainer = $RulesOverlay/Panel
@onready var rules_text_label: RichTextLabel = $RulesOverlay/Panel/Margin/VBox/RulesText

var net: Node = null
var my_index: int = -1
var _last_state: Dictionary = {}
var _segment_shown: int = -1
var _last_result_key: String = ""
var _showing_result: bool = false
var _result_token: int = 0


func _ready() -> void:
	for panel: PanelContainer in [result_panel, end_panel, rules_panel]:
		_style_overlay_panel(panel)
	for label: Label in [result_label, result_detail_label, end_title_label, end_score_label]:
		_style_overlay_label(label)
	bid_spin.update_on_text_changed = true
	bid_spin.value_changed.connect(_on_bid_value_changed)
	_hide_board()
	status_label.text = "서버 연결 중…"
	_start_network()


func _style_overlay_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.14, 0.62)
	style.set_corner_radius_all(14)
	style.border_color = Color(1, 1, 1, 0.28)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)


func _style_overlay_label(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.99, 1))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.07, 0.95))
	label.add_theme_constant_override("outline_size", 6)


# ── 시각 요소 ──────────────────────────────────────────────────

static func _bid_color(amount: int) -> String:
	return "black" if amount < 10 else "white"


static func _lamp_level(points: int) -> int:
	return mini(LAMP_COUNT, floori(points / float(LAMP_STEP)) + 1)


static func _color_phrase(color_name: String) -> String:
	return "검은색(한 자릿수)" if color_name == "black" else "흰색(두 자릿수)"


func _make_card(color_name: String, number: int, size: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var black := color_name == "black"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 1) if black else Color(0.94, 0.94, 0.95, 1)
	style.set_corner_radius_all(8)
	style.border_color = Color(0.45, 0.45, 0.50, 1)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	if number >= 0:
		var label := Label.new()
		label.text = str(number)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(size.y * 0.30))
		label.add_theme_color_override(
			"font_color",
			Color(0.95, 0.95, 0.96, 1) if black else Color(0.10, 0.10, 0.11, 1)
		)
		panel.add_child(label)
	return panel


func _render_lamps(row: HBoxContainer, level: int) -> void:
	_clear_container(row)
	for i in LAMP_COUNT:
		var lamp := PanelContainer.new()
		lamp.custom_minimum_size = LAMP_SIZE
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = LAMP_ON if i < level else LAMP_OFF
		style.set_corner_radius_all(5)
		style.border_color = Color(0.25, 0.20, 0.14, 0.6)
		style.set_border_width_all(1)
		lamp.add_theme_stylebox_override("panel", style)
		row.add_child(lamp)


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _clear_staging() -> void:
	_clear_container(first_stage_slot)
	_clear_container(second_stage_slot)
	first_stage_label.text = ""
	second_stage_label.text = ""


func _fill_stage(slot: Control, label: Label, color_name: String, number: int, caption: String) -> void:
	_clear_container(slot)
	slot.add_child(_make_card(color_name, number, CARD_SIZE))
	label.text = caption


func _name(idx: int) -> String:
	return "나" if idx == my_index else "상대"


func _hide_board() -> void:
	opponent_section.visible = false
	staging_row.visible = false
	my_section.visible = false
	bid_row.visible = false
	bid_hint_label.visible = false
	score_label.visible = false
	round_label.visible = false
	_clear_staging()


func _show_board() -> void:
	opponent_section.visible = true
	staging_row.visible = true
	my_section.visible = true
	score_label.visible = true
	round_label.visible = true


func _close_overlays() -> void:
	_result_token += 1
	_showing_result = false
	result_overlay.visible = false
	end_overlay.visible = false


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
	net.connected.connect(func() -> void:
		status_label.text = "연결됨 — 상대 대기 중…"
	)
	GameSession.game_id = GAME_ID
	net.connect_to_room(GameSession.quick_ws_url())


func _on_net_message(data: Dictionary) -> void:
	var t := str(data.get("type", ""))
	match t:
		"queued":
			status_label.text = "상대를 찾는 중…"
		"matched":
			GameSession.room_id = str(data.get("room_id", ""))
			status_label.text = "매칭 완료! 입장 중…"
		"bw2_joined":
			my_index = int(data.get("you", -1))
			status_label.text = "방 %s" % GameSession.room_id
		"bw2_waiting":
			status_label.text = "상대를 기다리는 중…"
			prompt_label.text = "상대를 기다리는 중입니다…"
			_hide_board()
		"bw2_state":
			_apply_state(data)
		"bw2_opponent_left":
			_close_overlays()
			_hide_board()
			status_label.text = "상대가 나갔습니다."
			prompt_label.text = "상대가 나갔습니다. 로비로 돌아가 새 매칭을 시작하세요."
		"error":
			status_label.text = "오류: %s" % _error_text(str(data.get("message", "")))
			bid_submit_button.disabled = false
		_:
			pass


func _error_text(code: String) -> String:
	match code:
		"invalid_bid":
			return "낼 수 없는 포인트입니다."
		"not_your_turn":
			return "지금은 내 차례가 아닙니다."
		"game_already_over":
			return "이미 끝난 게임입니다."
		_:
			return code


func _on_net_disconnected() -> void:
	status_label.text = "서버 연결이 끊겼습니다."


func _apply_state(data: Dictionary) -> void:
	var seg := int(data.get("segment", 0))
	if seg != _segment_shown:
		_segment_shown = seg
		_last_result_key = ""
		_close_overlays()

	_last_state = data
	my_index = int(data.get("you", my_index))
	status_label.text = "방 %s" % GameSession.room_id
	_show_board()

	var last_result: Variant = data.get("last_result", null)
	if typeof(last_result) == TYPE_DICTIONARY:
		var key := "%d:%d" % [seg, int(last_result.get("round", -1))]
		if key != _last_result_key:
			_last_result_key = key
			_show_result(data)
			return

	# 결과 팝업을 보는 동안 상대가 다음 라운드 선으로 먼저 낼 수 있다.
	# 그 상태는 _last_state에만 담아 두고, 팝업을 닫을 때 그린다.
	if _showing_result or end_overlay.visible:
		return
	_render_round(data)


# ── 라운드 화면 ────────────────────────────────────────────────

func _render_score(data: Dictionary) -> void:
	var scores: Array = data.get("scores", [0, 0])
	var me := clampi(my_index, 0, 1)
	score_label.text = "나 %d : %d 상대" % [int(scores[me]), int(scores[1 - me])]


func _render_resources(data: Dictionary) -> void:
	my_points_label.text = "내 포인트 %d" % int(data.get("my_points", 0))
	_render_lamps(my_lamp_row, int(data.get("my_lamps", LAMP_COUNT)))
	_render_lamps(opp_lamp_row, int(data.get("opp_lamps", LAMP_COUNT)))


func _render_round(data: Dictionary) -> void:
	var round_index := int(data.get("round_index", 0))
	var max_rounds := int(data.get("max_rounds", 9))
	round_label.text = "라운드 %d / %d" % [mini(round_index + 1, max_rounds), max_rounds]
	_render_score(data)
	_render_resources(data)
	_clear_staging()

	var starter := int(data.get("starter", 0))
	var pending_v: Variant = data.get("pending_first_color", null)
	var pending_color := "" if pending_v == null else str(pending_v)
	if not pending_color.is_empty():
		var my_pending_v: Variant = data.get("my_pending_bid", null)
		var my_pending := -1 if my_pending_v == null else int(my_pending_v)
		_fill_stage(first_stage_slot, first_stage_label, pending_color, my_pending, "선 · %s" % _name(starter))

	var turn_v: Variant = data.get("turn", null)
	var turn := "" if turn_v == null else str(turn_v)
	match turn:
		"first":
			prompt_label.text = "내가 선입니다. 낼 포인트를 정하세요."
		"second":
			prompt_label.text = "상대가 %s을 냈습니다. 낼 포인트를 정하세요. (후)" % _color_phrase(pending_color)
		_:
			if not pending_color.is_empty():
				prompt_label.text = "상대가 포인트를 정하는 중입니다…"
			else:
				prompt_label.text = "상대가 선입니다. 기다려 주세요…"
	_set_bid_enabled(turn == "first" or turn == "second", int(data.get("my_points", 0)))


func _set_bid_enabled(enabled: bool, my_points: int) -> void:
	bid_row.visible = enabled
	bid_hint_label.visible = enabled
	if not enabled:
		return
	bid_spin.max_value = my_points
	bid_spin.value = clampi(int(bid_spin.value), 0, my_points)
	bid_submit_button.disabled = false
	_refresh_bid_preview()


func _on_bid_value_changed(_value: float) -> void:
	_refresh_bid_preview()


func _refresh_bid_preview() -> void:
	var amount := int(bid_spin.value)
	var color_name := _bid_color(amount)
	_clear_container(bid_preview_slot)
	bid_preview_slot.add_child(_make_card(color_name, amount, PREVIEW_SIZE))
	var left := int(_last_state.get("my_points", 0)) - amount
	bid_hint_label.text = "%s · 제출하면 남은 포인트 %d (표시등 %d개)" % [
		_color_phrase(color_name), left, _lamp_level(left)
	]


func _on_bid_submit_pressed() -> void:
	if net == null:
		return
	bid_spin.apply()
	bid_submit_button.disabled = true
	net.send_bw2_bid(int(bid_spin.value))


# ── 라운드 결과 / 게임 종료 ────────────────────────────────────

func _show_result(data: Dictionary) -> void:
	_showing_result = true
	var last_result: Dictionary = data.get("last_result", {})
	var starter := int(last_result.get("starter", 0))
	var second := 1 - starter
	var round_i := int(last_result.get("round", 0))
	var my_bids: Array = data.get("my_bids", [])
	var my_bid := int(my_bids[round_i]) if round_i < my_bids.size() else -1

	_set_bid_enabled(false, 0)
	_render_resources(data)
	_fill_stage(
		first_stage_slot, first_stage_label, str(last_result.get("starter_color", "black")),
		my_bid if starter == my_index else -1, "선 · %s" % _name(starter)
	)
	_fill_stage(
		second_stage_slot, second_stage_label, str(last_result.get("second_color", "black")),
		my_bid if second == my_index else -1, "후 · %s" % _name(second)
	)
	prompt_label.text = ""

	_result_token += 1
	var token := _result_token
	result_next_button.visible = false
	result_label.text = "모두 포인트를 냈습니다.\n승패를 공개합니다."
	result_detail_label.text = ""
	result_overlay.visible = true

	for n in range(3, 0, -1):
		if token != _result_token or not is_instance_valid(self):
			return
		result_detail_label.text = str(n)
		await get_tree().create_timer(1.0).timeout

	if token != _result_token or not is_instance_valid(self):
		return

	# 3·2·1 끝난 뒤에야 상단 점수를 갱신한다.
	_render_score(data)
	var winner := int(last_result.get("winner", -1))
	if winner < 0:
		result_label.text = "무승부!"
	elif winner == my_index:
		result_label.text = "승리!"
	else:
		result_label.text = "패배!"
	result_detail_label.text = score_label.text
	result_next_button.text = "결과 보기" if bool(data.get("is_over", false)) else "다음 라운드"
	result_next_button.visible = true


func _on_result_next_pressed() -> void:
	_result_token += 1
	_showing_result = false
	result_overlay.visible = false
	if bool(_last_state.get("is_over", false)):
		_show_match_end(_last_state)
	else:
		_render_round(_last_state)


func _show_match_end(data: Dictionary) -> void:
	_set_bid_enabled(false, 0)
	_clear_container(end_history_list)
	for record: Dictionary in data.get("reveal", []):
		var mine_first := int(record.get("starter", 0)) == my_index
		var my_bid := int(record.get("starter_bid" if mine_first else "second_bid", 0))
		var opp_bid := int(record.get("second_bid" if mine_first else "starter_bid", 0))
		var w := int(record.get("winner", -1))
		var outcome := "무승부"
		if w == my_index:
			outcome = "승"
		elif w >= 0:
			outcome = "패"
		var line := Label.new()
		line.text = "R%d (%s) - 나 %d vs %d 상대 -> %s" % [
			int(record.get("round", 0)) + 1,
			"선" if mine_first else "후",
			my_bid,
			opp_bid,
			outcome,
		]
		line.add_theme_font_size_override("font_size", 13)
		end_history_list.add_child(line)

	var winner := int(data.get("winner", -1))
	var reason := str(data.get("win_reason", ""))
	if winner < 0:
		end_title_label.text = "무승부"
	elif winner == my_index:
		end_title_label.text = "승리!"
	else:
		end_title_label.text = "패배"

	var reason_text := ""
	match reason:
		"five_points":
			reason_text = "승점 5점 선취"
		"points":
			reason_text = "승점 동점 — 남은 포인트로 결정"
		"draw":
			reason_text = "승점과 남은 포인트가 모두 같습니다"

	var scores: Array = data.get("scores", [0, 0])
	var final_v: Variant = data.get("final_points", null)
	var final_points: Array = final_v if typeof(final_v) == TYPE_ARRAY else [0, 0]
	var me := clampi(my_index, 0, 1)
	var lines: PackedStringArray = [
		"승점 나 %d : %d 상대" % [int(scores[me]), int(scores[1 - me])],
		"남은 포인트 나 %d : %d 상대" % [int(final_points[me]), int(final_points[1 - me])],
	]
	if not reason_text.is_empty():
		lines.append(reason_text)
	end_score_label.text = "\n".join(lines)
	end_overlay.visible = true


func _on_rematch_pressed() -> void:
	end_overlay.visible = false
	if net:
		net.send_bw2_rematch()
	status_label.text = "다음 판을 준비하는 중…"


func _on_lobby_pressed() -> void:
	if net != null and is_instance_valid(net) and net != GameSession.net:
		net.disconnect_from_room()
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://ui/genius_lobby.tscn")


# ── 규칙 팝업 ──────────────────────────────────────────────────

func _on_rules_pressed() -> void:
	var game := GameCatalog.by_id(GAME_ID)
	rules_text_label.text = str(game.get("rules_text", "설명이 없습니다."))
	rules_overlay.visible = true


func _on_rules_close_pressed() -> void:
	rules_overlay.visible = false


func _on_rules_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		rules_overlay.visible = false
