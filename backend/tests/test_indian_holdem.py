"""인디언 홀덤 — 족보, 베팅 순서, 다이/쇼다운, 내 카드 비공개."""

from __future__ import annotations

import random

from app.indian_holdem import ANTE, START_CHIPS, IndianHoldemRules, hand_rank


def _new(seed: int = 4):
    rules = IndianHoldemRules()
    st = rules.new_state(random.Random(seed))
    return rules, st


def _set_cards(st, p0: int, p1: int, community: list[int]) -> None:
    st.private = [p0, p1]
    st.community = list(community)


def test_hand_rank_order() -> None:
    triple = hand_rank([5, 5, 5])
    straight = hand_rank([4, 6, 5])
    pair = hand_rank([9, 9, 2])
    high = hand_rank([10, 7, 2])
    assert triple > straight > pair > high
    assert hand_rank([9, 9, 3]) > hand_rank([9, 9, 2])
    assert hand_rank([8, 8, 1]) > hand_rank([7, 7, 10])


def test_ante_taken_and_my_card_hidden() -> None:
    rules, st = _new()
    assert st.stacks == [START_CHIPS - ANTE] * 2
    v = rules.view(st, 0)
    assert v["opp_card"] == st.private[1]
    assert "my_card" not in v and "private" not in v


def test_check_check_goes_to_showdown() -> None:
    rules, st = _new()
    st.starter = st.to_act = 0
    _set_cards(st, 5, 2, [5, 9])  # 페어 vs 하이카드
    assert rules.apply(st, 1, {"kind": "call"}) == "not_your_turn"
    assert rules.apply(st, 0, {"kind": "call"}) is None
    assert rules.apply(st, 1, {"kind": "call"}) is None
    assert st.last_result["reason"] == "showdown"
    assert st.last_result["winner"] == 0
    assert st.last_result["hands"] == ["페어", "하이카드"]
    assert st.stacks == [START_CHIPS + 1 - ANTE, START_CHIPS - 1 - ANTE]


def test_raise_call_moves_pot_to_winner() -> None:
    rules, st = _new()
    st.starter = st.to_act = 0
    _set_cards(st, 3, 7, [8, 9])  # 하이카드 vs 스트레이트
    assert rules.apply(st, 0, {"kind": "raise", "amount": 4}) is None
    assert rules.apply(st, 1, {"kind": "raise", "amount": 2}) is None
    assert rules.apply(st, 0, {"kind": "call"}) is None
    assert st.last_result["contrib"] == [7, 7]
    assert st.last_result["winner"] == 1
    assert st.last_result["stacks_after"] == [START_CHIPS - 7, START_CHIPS + 7]


def test_fold_gives_pot_without_showdown() -> None:
    rules, st = _new()
    st.starter = st.to_act = 1
    _set_cards(st, 10, 1, [2, 3])
    rules.apply(st, 1, {"kind": "raise", "amount": 3})
    rules.apply(st, 0, {"kind": "fold"})
    assert st.last_result["reason"] == "fold"
    assert st.last_result["winner"] == 1
    assert st.last_result["hands"] is None
    assert st.last_result["stacks_after"] == [START_CHIPS - 1, START_CHIPS + 1]


def test_raise_limited_so_opponent_can_call() -> None:
    rules, st = _new()
    st.starter = st.to_act = 0
    st.stacks = [20, 5]
    assert rules.max_raise(st, 0) == 5
    assert rules.apply(st, 0, {"kind": "raise", "amount": 6}) == "invalid_bet"
    assert rules.apply(st, 0, {"kind": "raise", "amount": 5}) is None
    assert rules.max_raise(st, 1) == 0


def test_starter_alternates_and_game_ends() -> None:
    rules, st = _new()
    first = st.starter
    rules.apply(st, st.to_act, {"kind": "fold"})
    assert st.starter == 1 - first
    while not st.over:
        rules.apply(st, st.to_act, {"kind": "fold"})
    v = rules.view(st, 0)
    assert v["is_over"] is True
    assert v["opp_card"] is None
    assert sum(st.stacks) == START_CHIPS * 2
