# betting_rps_board.gd — 베팅 가위바위보 (온라인 전용)
#
# 두 사람이 손과 걸 칩을 동시에 낸다. 서버는 둘 다 낼 때까지 상대 손과 칩을
# 보내지 않고, 라운드가 끝나면 그 라운드의 손과 칩을 공개한다.
extends "res://scripts/duel_board.gd"

const HAND_ORDER := ["scissors", "rock", "paper"]
const HAND_NAMES := {"rock": "바위", "paper": "보", "scissors": "가위"}

var _last_label: Label
var _input_box: VBoxContainer
var _hand_group := ButtonGroup.new()
var _hand_buttons: Dictionary = {}
var _selected_hand: String = ""
var _bet_spin: SpinBox
var _submit: Button


func _game_id() -> String:
	return "betting_rps"


func _build_content() -> void:
	_last_label = make_label("", 16, INK)
	content.add_child(_last_label)

	_input_box = VBoxContainer.new()
	_input_box.add_theme_constant_override("separation", 12)
	content.add_child(_input_box)

	var hands := make_row(12)
	_input_box.add_child(hands)
	for hand: String in HAND_ORDER:
		var btn := make_button(HAND_NAMES[hand], 110)
		btn.custom_minimum_size = Vector2(110, 72)
		btn.add_theme_font_size_override("font_size", 22)
		btn.toggle_mode = true
		btn.button_group = _hand_group
		btn.pressed.connect(_on_hand_pressed.bind(hand))
		hands.add_child(btn)
		_hand_buttons[hand] = btn

	var bet_row := make_row(12)
	_input_box.add_child(bet_row)
	bet_row.add_child(make_label("걸 칩", 16, INK, false))
	_bet_spin = SpinBox.new()
	_bet_spin.min_value = 1
	_bet_spin.max_value = 10
	_bet_spin.rounded = true
	_bet_spin.update_on_text_changed = true
	_bet_spin.custom_minimum_size = Vector2(110, 44)
	bet_row.add_child(_bet_spin)
	_submit = make_button("내기", 140)
	_submit.disabled = true
	_submit.pressed.connect(_on_submit_pressed)
	bet_row.add_child(_submit)


func _on_hand_pressed(hand: String) -> void:
	_selected_hand = hand
	_submit.disabled = false


func _on_submit_pressed() -> void:
	if _selected_hand.is_empty():
		return
	_bet_spin.apply()
	_submit.disabled = true
	send_action({"hand": _selected_hand, "bet": int(_bet_spin.value)})


func _on_action_error(_code: String) -> void:
	_submit.disabled = _selected_hand.is_empty()


func _render_state(data: Dictionary) -> void:
	var my_chips := int(data.get("my_chips", 0))
	score_label.text = "칩  나 %d : %d 상대" % [my_chips, int(data.get("opp_chips", 0))]

	var last: Variant = data.get("last_result", null)
	_last_label.text = _result_line(last, "지난 라운드") if typeof(last) == TYPE_DICTIONARY else ""

	var round_no := mini(int(data.get("round_index", 0)) + 1, int(data.get("max_rounds", 10)))
	var round_text := "라운드 %d / %d" % [round_no, int(data.get("max_rounds", 10))]

	if bool(data.get("is_over", false)):
		_input_box.visible = false
		prompt_label.text = "게임 종료"
		return

	if bool(data.get("my_submitted", false)):
		_input_box.visible = false
		var mine: Dictionary = data.get("my_pending", {})
		prompt_label.text = "%s — %s, %d칩을 냈습니다. 상대를 기다리는 중…" % [
			round_text, HAND_NAMES.get(str(mine.get("hand", "")), "?"), int(mine.get("bet", 0))
		]
		return

	_input_box.visible = true
	_bet_spin.max_value = my_chips
	_bet_spin.value = clampi(int(_bet_spin.value), 1, my_chips)
	_submit.disabled = _selected_hand.is_empty()
	var opp_done := " 상대는 이미 냈습니다." if bool(data.get("opp_submitted", false)) else ""
	prompt_label.text = "%s — 낼 손과 걸 칩을 정하세요.%s" % [round_text, opp_done]


func _result_line(record: Dictionary, prefix: String) -> String:
	var hands: Array = record.get("hands", ["", ""])
	var bets: Array = record.get("bets", [0, 0])
	var me := clampi(my_index, 0, 1)
	return "%s: 나 %s(%d) vs %s(%d) 상대 → %s" % [
		prefix,
		HAND_NAMES.get(str(hands[me]), "?"), int(bets[me]),
		HAND_NAMES.get(str(hands[1 - me]), "?"), int(bets[1 - me]),
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
