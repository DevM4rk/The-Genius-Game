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
const TILE_COUNT := 9
const PLAYER_NAMES := ["플레이어 1", "플레이어 2"]
const TILE_SIZE := Vector2(100, 138)
const STAGE_SIZE := Vector2(56, 78)
const TILE_SEP := 8

@onready var score_label: Label = $RootMargin/VBox/TitleBlock/ScoreLabel
@onready var round_label: Label = $RootMargin/VBox/TitleBlock/RoundLabel
@onready var prompt_label: Label = $RootMargin/VBox/PromptLabel
@onready var opponent_section: VBoxContainer = $RootMargin/VBox/OpponentSection
@onready var opponent_row: HBoxContainer = $RootMargin/VBox/OpponentSection/OpponentRow
@onready var staging_row: HBoxContainer = $RootMargin/VBox/StagingRow
@onready var first_stage_slot: Control = $RootMargin/VBox/StagingRow/FirstStageSlot
@onready var second_stage_slot: Control = $RootMargin/VBox/StagingRow/SecondStageSlot
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


func _ready() -> void:
	_style_overlay_panel(pass_panel)
	_style_overlay_panel(result_panel)
	_style_overlay_panel(end_panel)
	_style_overlay_panel(rules_panel)
	_start_new_match()


func _style_overlay_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.18, 1)
	style.set_corner_radius_all(14)
	style.border_color = Color(0.35, 0.37, 0.42, 1)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)


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


func _fill_stage(slot_container: Control, value: int) -> void:
	_clear_container(slot_container)
	slot_container.add_child(_make_tile_view(value, false, STAGE_SIZE))


func _clear_staging() -> void:
	_clear_container(first_stage_slot)
	_clear_container(second_stage_slot)


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
		_fill_stage(first_stage_slot, bw_match.staged_first_value())
		var acting_player := current_actor
		var next_actor := bw_match.other(current_actor)
		_show_pass(
			"%s 님, 화면을 %s 님에게 넘겨주세요." % [PLAYER_NAMES[acting_player], PLAYER_NAMES[next_actor]],
			func() -> void:
				current_actor = next_actor
				_refresh_round_ui()
		)
	else:
		var record := bw_match.commit_second(slot)
		_fill_stage(second_stage_slot, int(record["second_tile"]))
		_show_result(record)


func _show_pass(text: String, action: Callable) -> void:
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
	if bw_match.is_over():
		_show_match_end()
		return
	current_actor = bw_match.starter
	_refresh_round_ui()


func _show_match_end() -> void:
	_clear_container(end_history_list)
	for record: Dictionary in bw_match.history:
		var line := Label.new()
		var w: int = record["winner"]
		var outcome := "무승부" if w < 0 else "%s 승" % PLAYER_NAMES[w]
		line.text = "R%d — %s: %d vs %s: %d → %s" % [
			int(record["round"]) + 1,
			PLAYER_NAMES[record["starter"]], record["starter_tile"],
			PLAYER_NAMES[bw_match.other(record["starter"])], record["second_tile"],
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
	_start_new_match()


func _on_lobby_pressed() -> void:
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
