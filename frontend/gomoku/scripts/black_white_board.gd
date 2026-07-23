# black_white_board.gd — 흑과백 데스매치 (로컬 2인, 패스앤플레이)
#
# 흐름: [플레이어1 타일 배치] → (화면 넘김) → [플레이어2 타일 배치]
#       → (화면 넘김) → 라운드 반복 → 매치 종료(+동점이면 연장전).
#
# 배치(순서)는 매치 내내 고정된 슬롯 위치이며, 상대는 항상 그 슬롯의
# 색만 볼 수 있다(뒷면 색 상시 공개, 숫자는 비공개). 타일을 내면 그
# 슬롯은 완전히 빈 칸으로 남아 위치가 밀리지 않는다 — 상대가 "그
# 자리, 그 색" 조합으로 유추할 수 있게 하기 위함.
extends Control

const BlackWhiteMatchScript := preload("res://scripts/black_white_match.gd")
const NetworkClientScript := preload("res://scripts/network_client.gd")
const TILE_COUNT := 9
const PLAYER_NAMES := ["플레이어 1", "플레이어 2"]
const TILE_SIZE := Vector2(100, 138)
const STAGE_SIZE := Vector2(64, 88)
const TILE_SEP := 8

@onready var status_label: Label = $RootMargin/VBox/TopBar/StatusLabel
@onready var score_label: Label = $RootMargin/VBox/TitleBlock/ScoreLabel
@onready var round_label: Label = $RootMargin/VBox/TitleBlock/RoundLabel
@onready var prompt_label: Label = $RootMargin/VBox/PromptLabel
@onready var opponent_section: VBoxContainer = $RootMargin/VBox/OpponentSection
@onready var opponent_row: HBoxContainer = $RootMargin/VBox/OpponentSection/OpponentRow
@onready var staging_row: HBoxContainer = $RootMargin/VBox/StagingRow
@onready var first_stage_slot: Control = $RootMargin/VBox/StagingRow/FirstStageCol/FirstStageSlot
@onready var first_stage_label: Label = $RootMargin/VBox/StagingRow/FirstStageCol/FirstStageLabel
@onready var second_stage_slot: Control = $RootMargin/VBox/StagingRow/SecondStageCol/SecondStageSlot
@onready var second_stage_label: Label = $RootMargin/VBox/StagingRow/SecondStageCol/SecondStageLabel
@onready var hand_title_label: Label = $RootMargin/VBox/HandSection/HandTitleLabel
@onready var hand_row: HBoxContainer = $RootMargin/VBox/HandSection/HandRow
@onready var arrange_button_row: CenterContainer = $RootMargin/VBox/ArrangeButtonRow
@onready var arrange_done_button: Button = $RootMargin/VBox/ArrangeButtonRow/ArrangeDoneButton

@onready var pass_overlay: Control = $PassOverlay
@onready var pass_panel: PanelContainer = $PassOverlay/Panel
@onready var pass_label: Label = $PassOverlay/Panel/Margin/VBox/Label

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
@onready var rematch_button: Button = $MatchEndOverlay/Panel/Margin/VBox/ButtonsRow/RematchButton

@onready var rules_overlay: Control = $RulesOverlay
@onready var rules_panel: PanelContainer = $RulesOverlay/Panel
@onready var rules_text_label: RichTextLabel = $RulesOverlay/Panel/Margin/VBox/RulesText

enum Phase { ARRANGE, ROUND }

var bw_match: BlackWhiteMatch
var current_actor: int = 0
var _phase: Phase = Phase.ARRANGE
var _arranging_player: int = 0
var _arrangement_draft: Array = [[], []]
var _swap_selected_slot: int = -1
var _is_first_segment: bool = true
var _pending_starter: int = 0
var _pass_continue_action: Callable = Callable()
var _result_token: int = 0

# ── 온라인(랜덤매칭) 상태 ────────────────────────────────────────
# 온라인에서는 bw_match를 쓰지 않고, 서버가 보내주는 bw_state를 그대로
# 화면에 반영한다. 상대의 실제 숫자는 절대 클라이언트로 전달되지 않으며
# (색만 전달됨), 매치 종료 후에도 공개되지 않는다.
var online: bool = false
var net: Node = null
var my_index: int = -1
var _online_arrangement: Array = []
var _online_last_state: Dictionary = {}
var _online_segment_shown: int = -1
var _online_last_result_key: String = ""
var _online_history: Array = []


func _ready() -> void:
	_style_overlay_panel(pass_panel)
	_style_overlay_panel(result_panel)
	_style_overlay_panel(end_panel)
	_style_overlay_panel(rules_panel)
	_style_overlay_label(pass_label)
	_style_overlay_label(result_label)
	_style_overlay_label(result_detail_label)
	_style_overlay_label(end_title_label)
	_style_overlay_label(end_score_label)

	online = GameSession.mode == GameSession.Mode.ONLINE or GameSession.mode == GameSession.Mode.QUICK
	if online:
		status_label.visible = true
		_start_online()
	else:
		_start_new_match()


func _style_overlay_panel(panel: PanelContainer) -> void:
	if panel == null:
		push_error("overlay panel missing in black_white_board.tscn")
		return
	var style := StyleBoxFlat.new()
	# 배경은 비치게, 글씨는 패널 위에서 읽히게.
	style.bg_color = Color(0.10, 0.11, 0.14, 0.62)
	style.set_corner_radius_all(14)
	style.border_color = Color(1, 1, 1, 0.28)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)


func _style_overlay_label(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.99, 1))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.07, 0.95))
	label.add_theme_constant_override("outline_size", 6)


# ── 타일 시각 요소 ──────────────────────────────────────────────

func _make_tile_button(value: int, size: Vector2) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = size
	var black := BlackWhiteMatchScript.is_black(value)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 1) if black else Color(0.94, 0.94, 0.95, 1)
	style.set_corner_radius_all(8)
	style.border_color = Color(0.45, 0.45, 0.50, 1)
	style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.text = str(value)
	var font_color := Color(0.95, 0.95, 0.96, 1) if black else Color(0.10, 0.10, 0.11, 1)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_focus_color", font_color)
	btn.add_theme_color_override("font_disabled_color", font_color)
	btn.add_theme_font_size_override("font_size", int(size.y * 0.26))
	return btn


func _make_tile_view(value: int, show_number: bool, size: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var black := BlackWhiteMatchScript.is_black(value)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 1) if black else Color(0.94, 0.94, 0.95, 1)
	style.set_corner_radius_all(8)
	style.border_color = Color(0.45, 0.45, 0.50, 1)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	if show_number:
		var label := Label.new()
		label.text = str(value)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(size.y * 0.26))
		label.add_theme_color_override(
			"font_color",
			Color(0.95, 0.95, 0.96, 1) if black else Color(0.10, 0.10, 0.11, 1)
		)
		panel.add_child(label)
	return panel


## 값을 모르고 색만 아는 경우(온라인에서 상대 타일)에 쓰는 뒷면 뷰.
func _make_color_tile_view(color_name: String, size: Vector2) -> Control:
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
	return panel


func _make_gap(size: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(8)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _fill_stage_value(slot_container: Control, value: int, owner_label: Label, name_text: String) -> void:
	_clear_container(slot_container)
	slot_container.add_child(_make_tile_view(value, false, STAGE_SIZE))
	owner_label.text = "%s의 카드" % name_text


func _fill_stage_color(slot_container: Control, color_name: String, owner_label: Label, name_text: String) -> void:
	_clear_container(slot_container)
	slot_container.add_child(_make_color_tile_view(color_name, STAGE_SIZE))
	owner_label.text = "%s의 카드" % name_text


func _clear_staging() -> void:
	_clear_container(first_stage_slot)
	_clear_container(second_stage_slot)
	first_stage_label.text = ""
	second_stage_label.text = ""


## 팝업이 떠 있는 동안 뒤의 숫자만 숨긴다(색은 유지). 검정 전체 가림막은 쓰지 않음.
## 온라인에서는 기기를 공유하지 않으므로(각자 자기 화면) 적용하지 않는다.
func _hide_visible_numbers() -> void:
	if online:
		return
	if _phase == Phase.ARRANGE:
		_clear_container(hand_row)
		for slot in range(TILE_COUNT):
			var value: int = _arrangement_draft[_arranging_player][slot]
			hand_row.add_child(_make_tile_view(value, false, TILE_SIZE))
		return
	if bw_match == null:
		_clear_container(hand_row)
		_clear_container(opponent_row)
		return
	_rebuild_row(hand_row, current_actor, false)
	_rebuild_row(opponent_row, bw_match.other(current_actor), false)


# ── 매치 시작 / 배치 단계 ──────────────────────────────────────

func _start_new_match() -> void:
	_arrangement_draft[0] = range(TILE_COUNT)
	_arrangement_draft[1] = range(TILE_COUNT)
	if _is_first_segment:
		_pending_starter = 0 if GameSession.prefer_first else 1
		_is_first_segment = false
	else:
		_pending_starter = randi() % 2
	bw_match = null
	_clear_staging()
	_start_arrangement(0)


func _start_arrangement(player: int) -> void:
	_phase = Phase.ARRANGE
	_arranging_player = player
	_swap_selected_slot = -1

	arrange_button_row.visible = true
	opponent_section.visible = false
	staging_row.visible = false
	score_label.visible = false
	round_label.visible = false

	hand_title_label.text = "%s 의 타일 배치" % PLAYER_NAMES[player]
	prompt_label.text = "원하는 순서로 배치하세요. 바꿀 타일 두 장을 순서대로 탭하면 위치가 바뀝니다."
	_rebuild_arrange_row()


func _rebuild_arrange_row() -> void:
	_clear_container(hand_row)
	for slot in range(TILE_COUNT):
		var value: int = _arrangement_draft[_arranging_player][slot]
		var tile := _make_tile_button(value, TILE_SIZE)
		if slot == _swap_selected_slot:
			tile.modulate = Color(1.0, 0.82, 0.42, 1)
		tile.pressed.connect(_on_arrange_tile_pressed.bind(slot))
		hand_row.add_child(tile)


func _on_arrange_tile_pressed(slot: int) -> void:
	if _swap_selected_slot < 0:
		_swap_selected_slot = slot
	elif _swap_selected_slot == slot:
		_swap_selected_slot = -1
	else:
		var arr: Array = _arrangement_draft[_arranging_player]
		var tmp = arr[_swap_selected_slot]
		arr[_swap_selected_slot] = arr[slot]
		arr[slot] = tmp
		_swap_selected_slot = -1
	_rebuild_arrange_row()


func _on_arrange_done_pressed() -> void:
	arrange_button_row.visible = false
	if online:
		if net:
			net.send_bw_arrange(_online_arrangement)
		status_label.text = "배치를 서버로 전송했습니다."
		prompt_label.text = "상대가 타일을 배치할 때까지 기다려 주세요…"
		_clear_container(hand_row)
		return
	if _arranging_player == 0:
		_show_pass(
			"%s 님, 화면을 %s 님에게 넘겨주세요." % [PLAYER_NAMES[0], PLAYER_NAMES[1]],
			func() -> void: _start_arrangement(1)
		)
	else:
		_begin_round_phase()


func _begin_round_phase() -> void:
	_phase = Phase.ROUND
	bw_match = BlackWhiteMatchScript.new(
		_pending_starter, _arrangement_draft[0], _arrangement_draft[1]
	)
	current_actor = bw_match.starter
	opponent_section.visible = true
	staging_row.visible = true
	score_label.visible = true
	round_label.visible = true
	_clear_staging()
	_refresh_round_ui()


# ── 라운드 진행 ────────────────────────────────────────────────

func _refresh_round_ui() -> void:
	round_label.text = "라운드 %d / %d" % [bw_match.round_index + 1, TILE_COUNT]
	score_label.text = "%d : %d" % [bw_match.scores[0], bw_match.scores[1]]
	var role := "선" if not bw_match.has_pending_first() else "후"
	hand_title_label.text = "내 타일"
	prompt_label.text = "%s, 낼 타일을 선택하세요. (%s)" % [PLAYER_NAMES[current_actor], role]
	_rebuild_row(hand_row, current_actor, true)
	_rebuild_row(opponent_row, bw_match.other(current_actor), false)


func _rebuild_row(container: Container, player: int, mine: bool) -> void:
	_clear_container(container)
	for slot in range(TILE_COUNT):
		if bw_match.is_used(player, slot):
			container.add_child(_make_gap(TILE_SIZE))
			continue
		var value: int = bw_match.value_at(player, slot)
		if mine:
			var btn := _make_tile_button(value, TILE_SIZE)
			btn.pressed.connect(_on_hand_tile_pressed.bind(slot))
			container.add_child(btn)
		else:
			container.add_child(_make_tile_view(value, false, TILE_SIZE))


func _on_hand_tile_pressed(slot: int) -> void:
	if not bw_match.has_pending_first():
		bw_match.commit_first(slot)
		var acting_player := current_actor
		_fill_stage_value(first_stage_slot, bw_match.staged_first_value(), first_stage_label, PLAYER_NAMES[acting_player])
		var next_actor := bw_match.other(current_actor)
		_show_pass(
			"%s 님, 화면을 %s 님에게 넘겨주세요." % [PLAYER_NAMES[acting_player], PLAYER_NAMES[next_actor]],
			func() -> void:
				current_actor = next_actor
				_refresh_round_ui()
		)
	else:
		var acting_player := current_actor
		var record := bw_match.commit_second(slot)
		_fill_stage_value(second_stage_slot, int(record["second_tile"]), second_stage_label, PLAYER_NAMES[acting_player])
		# 후공이 낸 슬롯은 바로 빈 칸으로 (결과 팝업 떠 있는 동안에도 유지).
		_rebuild_row(hand_row, acting_player, false)
		_rebuild_row(opponent_row, bw_match.other(acting_player), false)
		_show_result(record)


func _show_pass(text: String, action: Callable) -> void:
	# 검정 전체 화면 대신, 숫자만 숨기고 팝업만 띄운다.
	_hide_visible_numbers()
	arrange_button_row.visible = false
	pass_label.text = text
	_pass_continue_action = action
	pass_overlay.visible = true


func _on_pass_continue_pressed() -> void:
	pass_overlay.visible = false
	var action := _pass_continue_action
	_pass_continue_action = Callable()
	if action.is_valid():
		action.call()


func _show_result(record: Dictionary) -> void:
	_result_token += 1
	var token := _result_token
	_hide_visible_numbers()
	result_next_button.visible = false
	result_label.text = "모두 카드를 냈습니다.\n승패를 공개합니다."
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
	score_label.text = "%d : %d" % [bw_match.scores[0], bw_match.scores[1]]

	var winner: int = record["winner"]
	if bw_match.is_over():
		if bw_match.is_tie():
			result_label.text = "동점!"
			result_detail_label.text = "연장전을 진행합니다.\n점수 %d : %d" % [
				bw_match.scores[0], bw_match.scores[1]
			]
		else:
			var segment_winner := bw_match.segment_winner()
			result_label.text = "%s 승!" % PLAYER_NAMES[segment_winner]
			result_detail_label.text = "데스매치 종료\n점수 %d : %d" % [
				bw_match.scores[0], bw_match.scores[1]
			]
		result_next_button.text = "결과 보기"
	else:
		var next_starter: int = bw_match.starter
		var look_away: int = bw_match.other(next_starter)
		if winner < 0:
			result_label.text = "무승부!"
		else:
			result_label.text = "%s 승!" % PLAYER_NAMES[winner]
		result_detail_label.text = "%s이 선입니다.\n%s은 보지 말아주세요.\n\n점수 %d : %d" % [
			PLAYER_NAMES[next_starter],
			PLAYER_NAMES[look_away],
			bw_match.scores[0],
			bw_match.scores[1],
		]
		result_next_button.text = "다음 라운드"
	result_next_button.visible = true


func _on_result_next_pressed() -> void:
	_result_token += 1
	result_overlay.visible = false
	result_next_button.visible = true
	_clear_staging()
	if online:
		if bool(_online_last_state.get("is_over", false)):
			_show_online_match_end(_online_last_state)
		else:
			_render_online_round(_online_last_state)
		return
	if bw_match.is_over():
		_show_match_end()
		return
	current_actor = bw_match.starter
	_refresh_round_ui()


func _show_match_end() -> void:
	_clear_container(end_history_list)
	for record: Dictionary in bw_match.history:
		var line := Label.new()
		var starter: int = int(record["starter"])
		var second: int = bw_match.other(starter)
		var w: int = int(record["winner"])
		var outcome := "무승부"
		if w >= 0:
			outcome = "%s 승" % PLAYER_NAMES[w]
		line.text = "R%d - %s %d vs %d %s -> %s" % [
			int(record["round"]) + 1,
			PLAYER_NAMES[starter], int(record["starter_tile"]),
			int(record["second_tile"]), PLAYER_NAMES[second],
			outcome,
		]
		line.add_theme_font_size_override("font_size", 13)
		end_history_list.add_child(line)

	if bw_match.is_tie():
		end_title_label.text = "동점! 연장전을 진행합니다."
		rematch_button.text = "연장전 시작"
	else:
		var w := bw_match.segment_winner()
		end_title_label.text = "%s 승리!" % PLAYER_NAMES[w]
		rematch_button.text = "다시 시작"
	end_score_label.text = "최종 점수 — %s %d : %d %s" % [
		PLAYER_NAMES[0], bw_match.scores[0], bw_match.scores[1], PLAYER_NAMES[1]
	]
	end_overlay.visible = true


func _on_rematch_pressed() -> void:
	end_overlay.visible = false
	if online:
		if net:
			net.send_bw_rematch()
		status_label.text = "다음 판을 준비하는 중…"
		return
	_start_new_match()


func _on_lobby_pressed() -> void:
	if online and net != null and is_instance_valid(net) and net != GameSession.net:
		net.disconnect_from_room()
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://ui/genius_lobby.tscn")


# ── 규칙 팝업 ──────────────────────────────────────────────────

func _on_rules_pressed() -> void:
	var game := GameCatalog.by_id("black_white")
	rules_text_label.text = str(game.get("rules_text", "설명이 없습니다."))
	rules_overlay.visible = true


func _on_rules_close_pressed() -> void:
	rules_overlay.visible = false


func _on_rules_dimmer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		rules_overlay.visible = false


# ── 온라인(랜덤매칭) ─────────────────────────────────────────────
# 서버가 상태의 유일한 권위자다. 클라이언트는 자기 배치를 보내고,
# 서버가 보내주는 bw_state(내 손패 값 + 상대 손패는 "색만")를 그대로
# 그린다. 라운드 결과도 승/무만 오고, 실제 숫자는 절대 오지 않는다.

func _start_online() -> void:
	bw_match = null
	my_index = -1
	_online_arrangement.clear()
	_online_segment_shown = -1
	_online_last_result_key = ""
	_online_history.clear()
	_clear_staging()
	status_label.text = "서버 연결 중…"
	prompt_label.text = ""
	opponent_section.visible = false
	staging_row.visible = false
	score_label.visible = false
	round_label.visible = false
	arrange_button_row.visible = false
	_start_network()


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
	var url := GameSession.quick_ws_url() if GameSession.mode == GameSession.Mode.QUICK else GameSession.ws_url()
	net.connect_to_room(url)


func _online_name(idx: int) -> String:
	return "나" if idx == my_index else "상대"


func _on_net_message(data: Dictionary) -> void:
	var t := str(data.get("type", ""))
	match t:
		"queued":
			status_label.text = "상대를 찾는 중…"
		"matched":
			GameSession.room_id = str(data.get("room_id", ""))
			status_label.text = "매칭 완료! 입장 중…"
		"bw_joined":
			my_index = int(data.get("you", -1))
			GameSession.my_color = my_index
			status_label.text = "방 %s" % GameSession.room_id
		"bw_waiting":
			status_label.text = "상대를 기다리는 중… (방 코드: %s)" % GameSession.room_id
			prompt_label.text = "상대를 기다리는 중입니다…"
			opponent_section.visible = false
			staging_row.visible = false
			score_label.visible = false
			round_label.visible = false
			arrange_button_row.visible = false
			_clear_container(hand_row)
		"bw_wait_arrange":
			status_label.text = "상대의 배치를 기다리는 중…"
			prompt_label.text = "상대가 타일을 배치할 때까지 기다려 주세요…"
		"bw_state":
			_apply_online_state(data)
		"bw_opponent_left":
			status_label.text = "상대가 나갔습니다. 새 상대를 기다립니다…"
			prompt_label.text = "상대가 나갔습니다. 새 상대를 기다리는 중입니다…"
			opponent_section.visible = false
			staging_row.visible = false
			score_label.visible = false
			round_label.visible = false
			arrange_button_row.visible = false
			_clear_container(hand_row)
		"error":
			status_label.text = "오류: %s" % str(data.get("message", ""))
		"pong":
			pass
		_:
			pass


func _on_net_disconnected() -> void:
	if not online:
		return
	status_label.text = "서버 연결이 끊겼습니다."


func _apply_online_state(data: Dictionary) -> void:
	var seg: int = int(data.get("segment", 0))
	if seg != _online_segment_shown:
		_online_segment_shown = seg
		_online_history.clear()
		_online_last_result_key = ""

	_online_last_state = data
	my_index = int(data.get("you", my_index))
	status_label.text = "방 %s" % GameSession.room_id

	if not bool(data.get("arranged", false)):
		_show_online_arrange_phase()
		return

	arrange_button_row.visible = false
	opponent_section.visible = true
	staging_row.visible = true
	score_label.visible = true
	round_label.visible = true

	if not bool(data.get("opp_arranged", false)):
		prompt_label.text = "상대가 타일을 배치할 때까지 기다려 주세요…"
		_render_online_round(data)
		return

	var last_result: Variant = data.get("last_result", null)
	if typeof(last_result) == TYPE_DICTIONARY:
		var key := "%d:%d" % [seg, int(last_result.get("round", -1))]
		if key != _online_last_result_key:
			_online_last_result_key = key
			_record_online_history(last_result, data)
			_show_online_result(data)
			return

	_render_online_round(data)


func _show_online_arrange_phase() -> void:
	_phase = Phase.ARRANGE
	if _online_arrangement.is_empty():
		_online_arrangement = range(TILE_COUNT)
	_swap_selected_slot = -1
	arrange_button_row.visible = true
	opponent_section.visible = false
	staging_row.visible = false
	score_label.visible = false
	round_label.visible = false
	hand_title_label.text = "내 타일 배치"
	prompt_label.text = "원하는 순서로 배치하세요. 바꿀 타일 두 장을 순서대로 탭하면 위치가 바뀝니다."
	_rebuild_online_arrange_row()


func _rebuild_online_arrange_row() -> void:
	_clear_container(hand_row)
	for slot in range(TILE_COUNT):
		var value: int = _online_arrangement[slot]
		var tile := _make_tile_button(value, TILE_SIZE)
		if slot == _swap_selected_slot:
			tile.modulate = Color(1.0, 0.82, 0.42, 1)
		tile.pressed.connect(_on_online_arrange_tile_pressed.bind(slot))
		hand_row.add_child(tile)


func _on_online_arrange_tile_pressed(slot: int) -> void:
	if _swap_selected_slot < 0:
		_swap_selected_slot = slot
	elif _swap_selected_slot == slot:
		_swap_selected_slot = -1
	else:
		var tmp = _online_arrangement[_swap_selected_slot]
		_online_arrangement[_swap_selected_slot] = _online_arrangement[slot]
		_online_arrangement[slot] = tmp
		_swap_selected_slot = -1
	_rebuild_online_arrange_row()


func _render_online_round(data: Dictionary) -> void:
	var round_index: int = int(data.get("round_index", 0))
	var scores: Array = data.get("scores", [0, 0])
	var turn := str(data.get("turn", ""))

	round_label.text = "라운드 %d / %d" % [round_index + 1, TILE_COUNT]
	score_label.text = "%d : %d" % [scores[0], scores[1]]
	hand_title_label.text = "내 타일"

	if turn == "first":
		prompt_label.text = "낼 타일을 선택하세요. (선)"
	elif turn == "second":
		prompt_label.text = "낼 타일을 선택하세요. (후)"
	else:
		prompt_label.text = "상대의 차례입니다. 기다려 주세요…"

	_rebuild_online_row(hand_row, data.get("my_hand", []), turn == "first" or turn == "second")
	_rebuild_online_opp_row(opponent_row, data.get("opp_hand", []))
	_refresh_online_staging(data)


func _rebuild_online_row(container: Container, hand_arr: Array, interactive: bool) -> void:
	_clear_container(container)
	for entry: Dictionary in hand_arr:
		var slot: int = int(entry.get("slot", 0))
		var used: bool = bool(entry.get("used", false))
		if used:
			container.add_child(_make_gap(TILE_SIZE))
			continue
		var value: int = int(entry.get("value", 0))
		if interactive:
			var btn := _make_tile_button(value, TILE_SIZE)
			btn.pressed.connect(_on_online_tile_pressed.bind(slot))
			container.add_child(btn)
		else:
			container.add_child(_make_tile_view(value, true, TILE_SIZE))


func _rebuild_online_opp_row(container: Container, hand_arr: Array) -> void:
	_clear_container(container)
	for entry: Dictionary in hand_arr:
		var used: bool = bool(entry.get("used", false))
		if used:
			container.add_child(_make_gap(TILE_SIZE))
			continue
		var color := str(entry.get("color", "black"))
		container.add_child(_make_color_tile_view(color, TILE_SIZE))


func _refresh_online_staging(data: Dictionary) -> void:
	_clear_staging()
	var pending_slot: int = int(data.get("pending_first_slot", -1))
	if pending_slot < 0:
		return
	var starter: int = int(data.get("starter", 0))
	var color_name := _online_color_for(starter, pending_slot, data)
	_fill_stage_color(first_stage_slot, color_name, first_stage_label, _online_name(starter))


func _online_color_for(player_idx: int, slot: int, data: Dictionary) -> String:
	if slot < 0:
		return "black"
	if player_idx == my_index:
		for entry: Dictionary in data.get("my_hand", []):
			if int(entry.get("slot", -1)) == slot:
				return "black" if BlackWhiteMatchScript.is_black(int(entry.get("value", 0))) else "white"
	else:
		for entry: Dictionary in data.get("opp_hand", []):
			if int(entry.get("slot", -1)) == slot:
				return str(entry.get("color", "black"))
	return "black"


func _on_online_tile_pressed(slot: int) -> void:
	if net == null:
		return
	net.send_bw_play(slot)


func _show_online_result(data: Dictionary) -> void:
	var last_result: Dictionary = data.get("last_result", {})
	var starter: int = int(last_result.get("starter", 0))
	var second: int = 1 - starter
	var starter_slot: int = int(last_result.get("starter_slot", -1))
	var second_slot: int = int(last_result.get("second_slot", -1))
	var winner: int = int(last_result.get("winner", -1))

	# 후공 제출 직후 손패/상대 행에서 낸 슬롯을 바로 빈 칸으로 반영.
	# 점수는 3·2·1 공개 전까지 이전 값을 유지한다.
	_rebuild_online_row(hand_row, data.get("my_hand", []), false)
	_rebuild_online_opp_row(opponent_row, data.get("opp_hand", []))

	_fill_stage_color(
		first_stage_slot,
		_online_color_for(starter, starter_slot, data),
		first_stage_label,
		_online_name(starter)
	)
	_fill_stage_color(
		second_stage_slot,
		_online_color_for(second, second_slot, data),
		second_stage_label,
		_online_name(second)
	)

	_result_token += 1
	var token := _result_token
	result_next_button.visible = false
	result_label.text = "모두 카드를 냈습니다.\n승패를 공개합니다."
	result_detail_label.text = ""
	result_overlay.visible = true

	for n in range(3, 0, -1):
		if token != _result_token or not is_instance_valid(self):
			return
		result_detail_label.text = str(n)
		await get_tree().create_timer(1.0).timeout

	if token != _result_token or not is_instance_valid(self):
		return

	var scores: Array = data.get("scores", [0, 0])
	# 3·2·1 끝난 뒤에야 상단 점수를 갱신한다.
	score_label.text = "%d : %d" % [scores[0], scores[1]]
	if bool(data.get("is_over", false)):
		if bool(data.get("is_tie", false)):
			result_label.text = "동점!"
			result_detail_label.text = "연장전을 진행합니다.\n점수 %d : %d" % [scores[0], scores[1]]
		else:
			var seg_winner := 0 if scores[0] > scores[1] else 1
			result_label.text = "%s 승!" % _online_name(seg_winner)
			result_detail_label.text = "데스매치 종료\n점수 %d : %d" % [scores[0], scores[1]]
		result_next_button.text = "결과 보기"
	else:
		if winner < 0:
			result_label.text = "무승부!"
		else:
			result_label.text = "%s 승!" % _online_name(winner)
		result_detail_label.text = "점수 %d : %d" % [scores[0], scores[1]]
		result_next_button.text = "다음 라운드"
	result_next_button.visible = true


func _record_online_history(last_result: Dictionary, data: Dictionary) -> void:
	# 진행 중에는 내 숫자만 기억. 종료 시 서버 reveal로 상대 숫자를 채운다.
	var starter: int = int(last_result.get("starter", 0))
	var my_role_starter := starter == my_index
	var my_slot: int = int(last_result.get("starter_slot", -1)) if my_role_starter else int(last_result.get("second_slot", -1))
	var my_value := -1
	for entry: Dictionary in data.get("my_hand", []):
		if int(entry.get("slot", -1)) == my_slot:
			my_value = int(entry.get("value", -1))
			break
	_online_history.append({
		"round": int(last_result.get("round", 0)),
		"my_role_starter": my_role_starter,
		"my_value": my_value,
		"opp_value": -1,
		"winner": int(last_result.get("winner", -1)),
	})


func _apply_reveal_to_history(data: Dictionary) -> void:
	var reveal: Array = data.get("reveal", [])
	if reveal.is_empty():
		return
	_online_history.clear()
	for record: Dictionary in reveal:
		var starter: int = int(record.get("starter", 0))
		var my_role_starter := starter == my_index
		var my_value: int
		var opp_value: int
		if my_role_starter:
			my_value = int(record.get("starter_tile", -1))
			opp_value = int(record.get("second_tile", -1))
		else:
			my_value = int(record.get("second_tile", -1))
			opp_value = int(record.get("starter_tile", -1))
		_online_history.append({
			"round": int(record.get("round", 0)),
			"my_role_starter": my_role_starter,
			"my_value": my_value,
			"opp_value": opp_value,
			"winner": int(record.get("winner", -1)),
		})


func _show_online_match_end(data: Dictionary) -> void:
	_apply_reveal_to_history(data)
	_clear_container(end_history_list)
	for record: Dictionary in _online_history:
		var w: int = int(record.get("winner", -1))
		var outcome := "무승부"
		if w == my_index:
			outcome = "승"
		elif w >= 0:
			outcome = "패"
		var line := Label.new()
		line.text = "R%d - 나 %d vs %d 상대 -> %s" % [
			int(record.get("round", 0)) + 1,
			int(record.get("my_value", -1)),
			int(record.get("opp_value", -1)),
			outcome,
		]
		line.add_theme_font_size_override("font_size", 13)
		end_history_list.add_child(line)

	var scores: Array = data.get("scores", [0, 0])
	var my_score: int = scores[my_index] if my_index >= 0 and my_index < scores.size() else scores[0]
	var opp_score: int = scores[1 - my_index] if my_index >= 0 and my_index < scores.size() else scores[1]
	if bool(data.get("is_tie", false)):
		end_title_label.text = "동점! 연장전을 진행합니다."
		rematch_button.text = "연장전 시작"
	else:
		var w := 0 if scores[0] > scores[1] else 1
		end_title_label.text = "%s 승리!" % _online_name(w)
		rematch_button.text = "다시 시작"
	end_score_label.text = "최종 점수 — 나 %d : %d 상대" % [my_score, opp_score]
	end_overlay.visible = true
