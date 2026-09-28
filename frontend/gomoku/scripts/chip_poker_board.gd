# chip_poker_board.gd — 칩 포커 대결 공용 화면 (인디언 포커 / 양면포커)
#
# 매 라운드 카드 한 장씩 받고 칩을 동시에 건다. 게임별 스크립트는 카드 영역
# 그리기(_render_cards)와 기록용 카드 문구(_card_text)만 채운다.
extends "res://scripts/duel_board.gd"

const CARD_SIZE := Vector2(96, 132)
const CARD_BG := Color(0.97, 0.95, 0.90, 1)
const CARD_FG := Color(0.18, 0.14, 0.10, 1)
const HIDDEN_BG := Color(0.30, 0.22, 0.16, 1)
const HIDDEN_FG := Color(0.95, 0.86, 0.70, 1)

var cards_row: HBoxContainer
var _last_label: Label
var _bet_row: HBoxContainer
var _bet_spin: SpinBox
var _submit: Button


func _render_cards(_cards: Dictionary) -> void:
	pass


func _card_text(card: Variant) -> String:
	return str(card)


func card_column(title: String, card: PanelContainer) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.add_child(make_label(title, 13, MUTED))
	var holder := CenterContainer.new()
	holder.add_child(card)
	col.add_child(holder)
	return col


func _build_content() -> void:
	cards_row = make_row(40)
	cards_row.custom_minimum_size = Vector2(0, 160)
	content.add_child(cards_row)

	_last_label = make_label("", 15, INK)
	content.add_child(_last_label)

	_bet_row = make_row(12)
	content.add_child(_bet_row)
	_bet_row.add_child(make_label("걸 칩", 16, INK, false))
	_bet_spin = SpinBox.new()
	_bet_spin.min_value = 1
	_bet_spin.max_value = 20
	_bet_spin.rounded = true
	_bet_spin.update_on_text_changed = true
	_bet_spin.custom_minimum_size = Vector2(110, 44)
	_bet_row.add_child(_bet_spin)
	_submit = make_button("걸기", 140)
	_submit.pressed.connect(_on_submit_pressed)
	_bet_row.add_child(_submit)


func _on_submit_pressed() -> void:
	_bet_spin.apply()
	_submit.disabled = true
	send_action({"bet": int(_bet_spin.value)})


func _on_action_error(_code: String) -> void:
	_submit.disabled = false


func _render_state(data: Dictionary) -> void:
	var my_chips := int(data.get("my_chips", 0))
	score_label.text = "칩  나 %d : %d 상대" % [my_chips, int(data.get("opp_chips", 0))]

	var last: Variant = data.get("last_result", null)
	_last_label.text = _result_line(last, "지난 라운드") if typeof(last) == TYPE_DICTIONARY else ""

	clear_children(cards_row)
	var cards: Variant = data.get("cards", null)
	if typeof(cards) == TYPE_DICTIONARY:
		_render_cards(cards)

	var max_rounds := int(data.get("max_rounds", 10))
	var round_text := "라운드 %d / %d" % [mini(int(data.get("round_index", 0)) + 1, max_rounds), max_rounds]

	if bool(data.get("is_over", false)):
		_bet_row.visible = false
		prompt_label.text = "게임 종료"
		return

	if bool(data.get("my_submitted", false)):
		_bet_row.visible = false
		prompt_label.text = "%s — %d칩을 걸었습니다. 상대를 기다리는 중…" % [
			round_text, int(data.get("my_pending_bet", 0))
		]
		return

	_bet_row.visible = true
	_bet_spin.max_value = my_chips
	_bet_spin.value = clampi(int(_bet_spin.value), 1, my_chips)
	_submit.disabled = false
	var opp_done := " 상대는 이미 걸었습니다." if bool(data.get("opp_submitted", false)) else ""
	prompt_label.text = "%s — 걸 칩을 정하세요.%s" % [round_text, opp_done]


func _result_line(record: Dictionary, prefix: String) -> String:
	var cards: Array = record.get("cards", [null, null])
	var bets: Array = record.get("bets", [0, 0])
	var me := clampi(my_index, 0, 1)
	return "%s: 나 %s(%d칩) vs %s(%d칩) 상대 → %s" % [
		prefix,
		_card_text(cards[me]), int(bets[me]),
		_card_text(cards[1 - me]), int(bets[1 - me]),
		outcome_for_me(int(record.get("winner", -1))),
	]


func _end_lines(data: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"최종 칩  나 %d : %d 상대" % [int(data.get("my_chips", 0)), int(data.get("opp_chips", 0))]
	])


func _history_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for record: Dictionary in data.get("history", []):
		lines.append(_result_line(record, "R%d" % (int(record.get("round", 0)) + 1)))
	return lines
