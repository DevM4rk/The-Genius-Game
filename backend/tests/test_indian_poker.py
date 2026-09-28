"""인디언 포커 — 내 카드 비공개, 칩 이동, 종료 조건."""

from __future__ import annotations

import random

from app.poker_duel import MAX_ROUNDS, IndianPokerRules


def _new(seed: int = 1):
    rules = IndianPokerRules()
    return rules, rules.new_state(random.Random(seed))


def test_each_player_sees_only_opponent_card() -> None:
    rules, st = _new()
    st.cards = [3, 8]
    v0 = rules.view(st, 0)
    v1 = rules.view(st, 1)
    assert v0["cards"] == {"opp_card": 8}
    assert v1["cards"] == {"opp_card": 3}


def test_higher_card_takes_loser_bet() -> None:
    rules, st = _new()
    st.cards = [9, 4]
    assert rules.apply(st, 0, {"bet": 2}) is None
    assert rules.view(st, 1)["my_pending_bet"] is None
    assert rules.apply(st, 1, {"bet": 6}) is None
    assert st.chips == [26, 14]
    assert st.last_result["cards"] == [9, 4]
    assert st.round_index == 1


def test_same_card_returns_bets() -> None:
    rules, st = _new()
    st.cards = [5, 5]
    rules.apply(st, 0, {"bet": 7})
    rules.apply(st, 1, {"bet": 3})
    assert st.chips == [20, 20]
    assert st.last_result["winner"] == -1


def test_invalid_bets() -> None:
    rules, st = _new()
    assert rules.apply(st, 0, {"bet": 0}) == "invalid_bet"
    assert rules.apply(st, 0, {"bet": 21}) == "invalid_bet"
    assert rules.apply(st, 0, {"bet": 1}) is None
    assert rules.apply(st, 0, {"bet": 1}) == "already_submitted"


def test_game_ends_after_all_rounds_and_hides_cards() -> None:
    rules, st = _new()
    for _ in range(MAX_ROUNDS):
        rules.apply(st, 0, {"bet": 1})
        rules.apply(st, 1, {"bet": 1})
    view = rules.view(st, 0)
    assert view["is_over"] is True
    assert view["cards"] is None
    assert len(view["history"]) == MAX_ROUNDS
    assert sum(st.chips) == 40
    assert rules.apply(st, 0, {"bet": 1}) == "game_already_over"
