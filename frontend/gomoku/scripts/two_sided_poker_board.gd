# two_sided_poker_board.gd — 양면포커 (온라인 전용)
#
# 내 카드는 앞면만, 상대 카드는 내 쪽을 향한 뒷면만 보인다. 나머지 면은 "?".
# 라운드가 끝나면 서버가 두 카드의 양면을 모두 공개한다.
extends "res://scripts/chip_poker_board.gd"


func _game_id() -> String:
	return "two_sided_poker"


func _card_text(card: Variant) -> String:
	if typeof(card) != TYPE_ARRAY or card.size() < 2:
		return "?"
	return "%d+%d" % [int(card[0]), int(card[1])]


func _render_cards(cards: Dictionary) -> void:
	cards_row.add_child(_two_face_column(
		"내 카드", str(int(cards.get("my_front", 0))), "?"
	))
	cards_row.add_child(_two_face_column(
		"상대 카드", "?", str(int(cards.get("opp_back", 0)))
	))


func _two_face_column(title: String, front_text: String, back_text: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.add_child(make_label(title, 13, MUTED))
	var faces := make_row(6)
	faces.add_child(_face("앞", front_text))
	faces.add_child(_face("뒤", back_text))
	col.add_child(faces)
	return col


func _face(caption: String, text: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var is_hidden := text == "?"
	var face_size := Vector2(72, 100)
	var card := make_card(
		text, HIDDEN_BG if is_hidden else CARD_BG, HIDDEN_FG if is_hidden else CARD_FG, face_size
	)
	var holder := CenterContainer.new()
	holder.add_child(card)
	v.add_child(holder)
	v.add_child(make_label(caption, 12, MUTED))
	return v
