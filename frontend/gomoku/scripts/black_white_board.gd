# black_white_board.gd — 흑과백 데스매치 (로컬 2인, 패스앤플레이)
#
# 같은 기기에서 번갈아 화면을 보므로, 상대가 타일을 고른 뒤에는
# 반드시 PassOverlay를 거쳐 화면을 넘기게 해 서로의 선택을 가린다.
# 라운드 결과는 승/패/무만 공개하며, 실제로 낸 숫자는 매치가 끝난 뒤
# 전체 기록으로만 확인할 수 있다.
extends Control

const BlackWhiteMatchScript := preload("res://scripts/black_white_match.gd")
const TILE_COUNT := 9
const PLAYER_NAMES := ["플레이어 1", "플레이어 2"]

@onready var round_label: Label = $RootMargin/VBox/TopBar/RoundLabel
@onready var score_label: Label = $RootMargin/VBox/TopBar/ScoreLabel
@onready var prompt_label: Label = $RootMargin/VBox/PromptLabel
@onready var opponent_row: HBoxContainer = $RootMargin/VBox/OpponentSection/OpponentRow
@onready var hand_title_label: Label = $RootMargin/VBox/HandSection/HandTitleLabel
@onready var hand_row: HBoxContainer = $RootMargin/VBox/HandSection/HandRow

@onready var pass_overlay: Control = $PassOverlay
@onready var pass_panel: PanelContainer = $PassOverlay/Panel
@onready var pass_label: Label = $PassOverlay/Panel/Margin/VBox/Label

@onready var result_overlay: Control = $ResultOverlay
@onready var result_panel: PanelContainer = $ResultOverlay/Panel
@onready var result_label: Label = $ResultOverlay/Panel/Margin/VBox/ResultLabel
@onready var result_detail_label: Label = $ResultOverlay/Panel/Margin/VBox/ScoreDetailLabel

@onready var end_overlay: Control = $MatchEndOverlay
@onready var end_panel: PanelContainer = $MatchEndOverlay/Panel
@onready var end_title_label: Label = $MatchEndOverlay/Panel/Margin/VBox/TitleLabel
@onready var end_score_label: Label = $MatchEndOverlay/Panel/Margin/VBox/FinalScoreLabel
@onready var end_history_list: VBoxContainer = $MatchEndOverlay/Panel/Margin/VBox/HistoryScroll/HistoryList
@onready var rematch_button: Button = $MatchEndOverlay/Panel/Margin/VBox/ButtonsRow/RematchButton

var bw_match: BlackWhiteMatch
var current_actor: int = 0
var pending_first_value: int = -1
var _is_first_segment: bool = true
## 개인 메모용 표시(참고 범례 탭) — 게임 로직에는 영향 없음.
var eliminated_marks: Dictionary = {}


func _ready() -> void:
	_style_overlay_panel(pass_panel)
	_style_overlay_panel(result_panel)
	_style_overlay_panel(end_panel)
	_start_new_match()


func _style_overlay_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.18, 1)
	style.set_corner_radius_all(14)
	style.border_color = Color(0.35, 0.37, 0.42, 1)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)


func _start_new_match() -> void:
	eliminated_marks.clear()
	var starter: int
	if _is_first_segment:
		# 혼자하기 팝업의 선/후 토글: true면 플레이어 1이 1라운드 선.
		starter = 0 if GameSession.prefer_first else 1
		_is_first_segment = false
	else:
		starter = randi() % 2  # 연장전 선공은 매번 새로 무작위 결정.
	bw_match = BlackWhiteMatchScript.new(starter)
	current_actor = bw_match.starter
	pending_first_value = -1
	_build_legend_row()
	_refresh_round_ui()


func _build_legend_row() -> void:
	for child in opponent_row.get_children():
		child.queue_free()
	for value in range(TILE_COUNT):
		var tile := _make_tile_button(value, false)
		tile.tooltip_text = "숫자 %d — 참고용(탭하여 표시)" % value
		tile.pressed.connect(_on_legend_tile_pressed.bind(value, tile))
		_apply_elim_style(tile, eliminated_marks.get(value, false))
		opponent_row.add_child(tile)


func _on_legend_tile_pressed(value: int, tile: Button) -> void:
	var marked := not eliminated_marks.get(value, false)
	eliminated_marks[value] = marked
	_apply_elim_style(tile, marked)


func _apply_elim_style(tile: Button, marked: bool) -> void:
	tile.modulate = Color(1, 1, 1, 0.35) if marked else Color(1, 1, 1, 1)


func _make_tile_button(value: int, show_number: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(56, 78)
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
	btn.text = str(value) if show_number else ""
	btn.add_theme_color_override(
		"font_color",
		Color(0.95, 0.95, 0.96, 1) if black else Color(0.10, 0.10, 0.11, 1)
	)
	btn.add_theme_font_size_override("font_size", 22)
	return btn


func _refresh_round_ui() -> void:
	round_label.text = "라운드 %d / %d" % [bw_match.round_index + 1, TILE_COUNT]
	score_label.text = "%d : %d" % [bw_match.scores[0], bw_match.scores[1]]
	_rebuild_hand_row()
	var role := "선" if pending_first_value < 0 else "후"
	hand_title_label.text = "%s 의 타일 (%s)" % [PLAYER_NAMES[current_actor], role]
	prompt_label.text = "%s, 낼 타일을 선택하세요." % PLAYER_NAMES[current_actor]


func _rebuild_hand_row() -> void:
	for child in hand_row.get_children():
		child.queue_free()
	for value in bw_match.hands[current_actor]:
		var tile := _make_tile_button(value, true)
		tile.pressed.connect(_on_hand_tile_pressed.bind(value))
		hand_row.add_child(tile)


func _on_hand_tile_pressed(value: int) -> void:
	if pending_first_value < 0:
		pending_first_value = value
		var next_actor := bw_match.other(current_actor)
		pass_label.text = "%s 님, 화면을 %s 님에게 넘겨주세요." % [
			PLAYER_NAMES[current_actor], PLAYER_NAMES[next_actor]
		]
		current_actor = next_actor
		pass_overlay.visible = true
	else:
		var first_value := pending_first_value
		var second_value := value
		pending_first_value = -1
		var record := bw_match.play_round(first_value, second_value)
		_show_result(record)


func _on_pass_continue_pressed() -> void:
	pass_overlay.visible = false
	_refresh_round_ui()


func _show_result(record: Dictionary) -> void:
	var winner: int = record["winner"]
	result_label.text = "무승부" if winner < 0 else "%s 승리!" % PLAYER_NAMES[winner]
	result_detail_label.text = "점수 — %s %d : %d %s" % [
		PLAYER_NAMES[0], bw_match.scores[0], bw_match.scores[1], PLAYER_NAMES[1]
	]
	result_overlay.visible = true


func _on_result_next_pressed() -> void:
	result_overlay.visible = false
	if bw_match.is_over():
		_show_match_end()
		return
	current_actor = bw_match.starter
	_refresh_round_ui()


func _show_match_end() -> void:
	for child in end_history_list.get_children():
		child.queue_free()
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
