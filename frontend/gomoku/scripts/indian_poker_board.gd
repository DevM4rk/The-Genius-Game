# indian_poker_board.gd — 인디언 포커 (온라인 전용)
#
# 상대 카드는 보이고 내 카드는 "?"로 가려진다. 서버는 라운드 중 내 카드를 보내지 않는다.
extends "res://scripts/chip_poker_board.gd"


func _game_id() -> String:
	return "indian_poker"


func _render_cards(cards: Dictionary) -> void:
	cards_row.add_child(card_column("내 카드", make_card("?", HIDDEN_BG, HIDDEN_FG, CARD_SIZE)))
	cards_row.add_child(card_column(
		"상대 카드", make_card(str(int(cards.get("opp_card", 0))), CARD_BG, CARD_FG, CARD_SIZE)
	))
