"""결! 합! — 합 판정, 점수, 결 종료."""

from __future__ import annotations

import random

from app.hap_game import MIN_HAPS, HapRules, all_haps, is_hap, make_board


def _new(seed: int = 3):
    rules = HapRules()
    return rules, rules.new_state(random.Random(seed))


def test_is_hap() -> None:
    assert is_hap([(0, 0, 0), (0, 0, 1), (0, 0, 2)])
    assert is_hap([(0, 1, 2), (1, 2, 0), (2, 0, 1)])
    assert not is_hap([(0, 0, 0), (0, 0, 1), (0, 1, 2)])


def test_board_is_nine_distinct_cards_with_enough_haps() -> None:
    for seed in range(20):
        board = make_board(random.Random(seed))
        assert len(board) == 9 and len(set(board)) == 9
        assert len(all_haps(board)) >= MIN_HAPS


def test_correct_hap_scores_and_cannot_repeat() -> None:
    rules, st = _new()
    combo = sorted(all_haps(st.board))[0]
    assert rules.apply(st, 0, {"kind": "hap", "cards": list(combo)}) is None
    assert st.scores == [1, 0]
    assert st.last_event["ok"] is True

    rules.apply(st, 1, {"kind": "hap", "cards": list(reversed(combo))})
    assert st.scores == [1, -1]
    assert st.last_event["reason"] == "already_found"


def test_wrong_hap_loses_point() -> None:
    rules, st = _new()
    haps = all_haps(st.board)
    import itertools

    wrong = next(c for c in itertools.combinations(range(9), 3) if c not in haps)
    rules.apply(st, 0, {"kind": "hap", "cards": list(wrong)})
    assert st.scores == [-1, 0]
    assert st.last_event["reason"] == "not_hap"


def test_invalid_card_picks_rejected() -> None:
    rules, st = _new()
    assert rules.apply(st, 0, {"kind": "hap", "cards": [0, 0, 1]}) == "invalid_cards"
    assert rules.apply(st, 0, {"kind": "hap", "cards": [0, 1, 9]}) == "invalid_cards"
    assert rules.apply(st, 0, {"kind": "hap", "cards": [0, 1]}) == "invalid_cards"
    assert rules.apply(st, 0, {"kind": "nope"}) == "invalid_action"
    assert st.scores == [0, 0]


def test_gyeol_only_succeeds_when_no_haps_left() -> None:
    rules, st = _new()
    rules.apply(st, 1, {"kind": "gyeol"})
    assert st.scores == [0, -1] and not st.over

    for combo in sorted(all_haps(st.board)):
        rules.apply(st, 0, {"kind": "hap", "cards": list(combo)})
    rules.apply(st, 1, {"kind": "gyeol"})
    assert st.over
    assert st.scores[1] == 2
    view = rules.view(st, 0)
    assert view["is_over"] is True
    assert rules.apply(st, 0, {"kind": "gyeol"}) == "game_already_over"
