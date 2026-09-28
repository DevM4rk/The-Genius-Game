# indian_holdem_board.gd — 인디언 홀덤 (온라인 전용)
#
# 내 카드는 "?"로 가려지고, 상대 카드와 공개 카드 2장이 보인다. 번갈아 체크/콜,
# 레이즈, 다이를 하며 라운드가 끝나면 서버가 두 사람의 카드를 공개한다.
extends "res://scripts/duel_board.gd"

const CARD_SIZE := Vector2(84, 116)
const CARD_BG := Color(0.97, 0.95, 0.90, 1)
const CARD_FG := Color(0.18, 0.14, 0.10, 1)
const HIDDEN_BG := Color(0.30, 0.22, 0.16, 1)
const HIDDEN_FG := Color(0.95, 0.86, 0.70, 1)
const ACTION_NAMES := {"check": "체크", "call": "콜", "raise": "레이즈", "fold": "다이"}
const REASON_NAMES := {"fold": "다이", "showdown": "쇼다운"}

var _cards_row: HBoxContainer
var _pot_label: Label
var _actions_label: Label
var _last_label: Label
var _action_row: HBoxContainer
var _call_button: Button
var _raise_spin: SpinBox
var _raise_button: Button
var _fold_button: Button


func _game_id() -> String:
	return "indian_holdem"


func _build_content() -> void:
	_cards_row = make_row(24)
	_cards_row.custom_minimum_size = Vector2(0, 150)
	content.add_child(_cards_row)

	_pot_label = make_label("", 16, INK)
	content.add_child(_pot_label)
	_actions_label = make_label("", 14, MUTED)
	content.add_child(_actions_label)

	_action_row = make_row(10)
	content.add_child(_action_row)
	_call_button = make_button("체크", 110)
	_call_button.pressed.connect(func() -> void: _send({"kind": "call"}))
	_action_row.add_child(_call_button)
	_raise_spin = SpinBox.new()
	_raise_spin.min_value = 1
	_raise_spin.rounded = true
	_raise_spin.update_on_text_changed = true
	_raise_spin.custom_minimum_size = Vector2(100, 44)
	_action_row.add_child(_raise_spin)
	_raise_button = make_button("레이즈", 110)
	_raise_button.pressed.connect(_on_raise_pressed)
	_action_row.add_child(_raise_button)
	_fold_button = make_button("다이", 100)
	_fold_button.pressed.connect(func() -> void: _send({"kind": "fold"}))
	_action_row.add_child(_fold_button)

	_last_label = make_label("", 14, INK)
	content.add_child(_last_label)


func _send(action: Dictionary) -> void:
	_set_actions_enabled(false)
	send_action(action)


func _on_raise_pressed() -> void:
	_raise_spin.apply()
	_send({"kind": "raise", "amount": int(_raise_spin.value)})


func _on_action_error(_code: String) -> void:
	_render_state(state)


func _set_actions_enabled(enabled: bool) -> void:
	_call_button.disabled = not enabled
	_raise_button.disabled = not enabled
	_fold_button.disabled = not enabled


func _card_column(title: String, text: String, is_hidden: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(make_label(title, 13, MUTED))
	var holder := CenterContainer.new()
	holder.add_child(make_card(
		text, HIDDEN_BG if is_hidden else CARD_BG, HIDDEN_FG if is_hidden else CARD_FG, CARD_SIZE
	))
	col.add_child(holder)
	return col


func _render_state(data: Dictionary) -> void:
	score_label.text = "칩  나 %d : %d 상대" % [int(data.get("my_stack", 0)), int(data.get("opp_stack", 0))]

	clear_children(_cards_row)
	var over := bool(data.get("is_over", false))
	if not over:
		_cards_row.add_child(_card_column("내 카드", "?", true))
		_cards_row.add_child(_card_column("상대 카드", str(int(data.get("opp_card", 0))), false))
		var community: Array = data.get("community", [])
		for i in community.size():
			_cards_row.add_child(_card_column("공개 %d" % (i + 1), str(int(community[i])), false))

	var my_contrib := int(data.get("my_contrib", 0))
	var opp_contrib := int(data.get("opp_contrib", 0))
	_pot_label.text = "" if over else "판돈 %d  (나 %d · 상대 %d)" % [my_contrib + opp_contrib, my_contrib, opp_contrib]
	_actions_label.text = _actions_text(data.get("actions", []))

	var last: Variant = data.get("last_result", null)
	_last_label.text = _result_line(last, "지난 라운드") if typeof(last) == TYPE_DICTIONARY else ""

	var max_rounds := int(data.get("max_rounds", 10))
	var round_text := "라운드 %d / %d" % [mini(int(data.get("round_index", 0)) + 1, max_rounds), max_rounds]

	if over:
		_action_row.visible = false
		prompt_label.text = "게임 종료"
		return

	var my_turn := bool(data.get("my_turn", false))
	_action_row.visible = my_turn
	if not my_turn:
		prompt_label.text = "%s — 상대가 결정하는 중입니다…" % round_text
		return

	var to_call := int(data.get("to_call", 0))
	var max_raise := int(data.get("max_raise", 0))
	_set_actions_enabled(true)
	_call_button.text = "콜 (%d)" % to_call if to_call > 0 else "체크"
	_raise_button.disabled = max_raise < 1
	_raise_spin.editable = max_raise >= 1
	_raise_spin.max_value = maxi(1, max_raise)
	_raise_spin.value = clampi(int(_raise_spin.value), 1, maxi(1, max_raise))
	prompt_label.text = "%s — 내 차례입니다. %s" % [
		round_text, "콜하려면 %d칩이 필요합니다." % to_call if to_call > 0 else "체크하거나 레이즈하세요."
	]


func _actions_text(actions: Array) -> String:
	var parts := PackedStringArray()
	for a: Dictionary in actions:
		var action_text: String = ACTION_NAMES.get(str(a.get("kind", "")), "?")
		if a.has("amount"):
			action_text += " %d" % int(a.get("amount", 0))
		parts.append("%s %s" % [who(int(a.get("by", -1))), action_text])
	return " → ".join(parts)


func _result_line(record: Dictionary, prefix: String) -> String:
	var me := clampi(my_index, 0, 1)
	var private: Array = record.get("private", [0, 0])
	var community: Array = record.get("community", [])
	var contrib: Array = record.get("contrib", [0, 0])
	var reason: String = REASON_NAMES.get(str(record.get("reason", "")), "")
	var hands_v: Variant = record.get("hands", null)
	var hands_text := ""
	if typeof(hands_v) == TYPE_ARRAY:
		hands_text = " (%s vs %s)" % [str(hands_v[me]), str(hands_v[1 - me])]
	return "%s: 나 %d vs %d 상대, 공개 %s — %s%s → %s, 판돈 %d" % [
		prefix,
		int(private[me]),
		int(private[1 - me]),
		"·".join(PackedStringArray(community.map(func(c: Variant) -> String: return str(int(c))))),
		reason,
		hands_text,
		outcome_for_me(int(record.get("winner", -1))),
		int(contrib[0]) + int(contrib[1]),
	]


func _end_lines(data: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"최종 칩  나 %d : %d 상대" % [int(data.get("my_stack", 0)), int(data.get("opp_stack", 0))]
	])


func _history_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for record: Dictionary in data.get("history", []):
		lines.append(_result_line(record, "R%d" % (int(record.get("round", 0)) + 1)))
	return lines
