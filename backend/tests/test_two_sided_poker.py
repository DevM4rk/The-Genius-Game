"""양면포커 — 각 면은 한 사람만 보고, 두 면의 합으로 겨룬다."""

from __future__ import annotations

import random

from app.poker_duel import TwoSidedPokerRules


def _new(seed: int = 2):
    rules = TwoSidedPokerRules()
    return rules, rules.new_state(random.Random(seed))


def test_deck_has_every_number_twice_on_each_side() -> None:
    rules = TwoSidedPokerRules()
    deck = rules.make_deck(random.Random(0))
    assert sorted(c[0] for c in deck) == sorted(list(range(1, 11)) * 2)
    assert sorted(c[1] for c in deck) == sorted(list(range(1, 11)) * 2)


def test_each_side_is_seen_by_exactly_one_player() -> None:
    rules, st = _new()
    st.cards = [[3, 7], [9, 2]]
    assert rules.view(st, 0)["cards"] == {"my_front": 3, "opp_back": 2}
    assert rules.view(st, 1)["cards"] == {"my_front": 9, "opp_back": 7}


def test_sum_of_both_sides_decides_round() -> None:
    rules, st = _new()
    st.cards = [[3, 7], [9, 2]]  # 10 vs 11
    rules.apply(st, 0, {"bet": 5})
    rules.apply(st, 1, {"bet": 4})
    assert st.last_result["strengths"] == [10, 11]
    assert st.chips == [15, 25]
    assert st.last_result["cards"] == [[3, 7], [9, 2]]


def test_equal_sum_is_draw() -> None:
    rules, st = _new()
    st.cards = [[1, 9], [6, 4]]
    rules.apply(st, 0, {"bet": 5})
    rules.apply(st, 1, {"bet": 4})
    assert st.chips == [20, 20]
