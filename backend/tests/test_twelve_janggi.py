"""십이장기 — 이동, 포로, 내려놓기, 승급, 승리 조건."""

from __future__ import annotations

import random

from app.twelve_janggi import (
    COLS,
    ROWS,
    Piece,
    TwelveJanggiRules,
    TwelveState,
    legal_actions,
)


def _empty(to_act: int = 0) -> TwelveState:
    st = TwelveState(to_act=to_act)
    st.board = [[None] * COLS for _ in range(ROWS)]
    return st


def _move(rules, st, idx, frm, to):
    return rules.apply(st, idx, {"kind": "move", "from": list(frm), "to": list(to)})


def test_initial_moves() -> None:
    rules = TwelveJanggiRules()
    st = rules.new_state(random.Random(0))
    st.to_act = 0
    moves = legal_actions(st, 0)
    # 자는 앞(1,1)의 상대 자를 잡을 수 있다.
    assert {"kind": "move", "from": [1, 2], "to": [1, 1]} in moves
    # 상은 대각선만: (2,3) → (1,2)는 내 자가 있어 불가, 뒤쪽은 판 밖.
    assert not any(m["from"] == [2, 3] and m["to"] == [1, 2] for m in moves)
    assert all(m["kind"] == "move" for m in moves)


def test_capture_goes_to_hand_and_can_be_dropped() -> None:
    rules = TwelveJanggiRules()
    st = rules.new_state(random.Random(0))
    st.to_act = 0
    assert _move(rules, st, 0, (1, 2), (1, 1)) is None
    assert st.hands[0]["pawn"] == 1
    assert st.to_act == 1

    assert _move(rules, st, 1, (0, 0), (1, 1)) is None  # 상이 자를 잡는다
    assert st.hands[1]["pawn"] == 1

    drop = {"kind": "drop", "piece": "pawn", "to": [0, 2]}
    assert rules.apply(st, 0, drop) is None
    assert st.at(0, 2).kind == "pawn" and st.hands[0]["pawn"] == 0


def test_cannot_drop_in_enemy_row() -> None:
    st = _empty()
    st.board[3][1] = Piece(0, "king")
    st.board[0][0] = Piece(1, "king")
    st.hands[0]["rook"] = 1
    drops = [a for a in legal_actions(st, 0) if a["kind"] == "drop"]
    assert drops and all(a["to"][1] != 0 for a in drops)


def test_pawn_promotes_on_enemy_row_and_demotes_when_captured() -> None:
    rules = TwelveJanggiRules()
    st = _empty()
    st.board[3][0] = Piece(0, "king")
    st.board[0][2] = Piece(1, "king")
    st.board[1][1] = Piece(0, "pawn")
    assert _move(rules, st, 0, (1, 1), (1, 0)) is None
    assert st.at(1, 0).kind == "gold"
    assert st.last_move["promoted"] is True

    assert _move(rules, st, 1, (2, 0), (1, 0)) is None
    assert st.hands[1]["pawn"] == 1


def test_capturing_king_wins() -> None:
    rules = TwelveJanggiRules()
    st = _empty()
    st.board[3][0] = Piece(0, "king")
    st.board[2][1] = Piece(0, "rook")
    st.board[1][1] = Piece(1, "king")
    assert _move(rules, st, 0, (1, 2), (1, 1)) is None
    assert st.over and st.winner == 0 and st.reason == "king_captured"
    assert _move(rules, st, 1, (0, 0), (0, 1)) == "game_already_over"


def test_king_surviving_in_enemy_row_wins() -> None:
    rules = TwelveJanggiRules()
    st = _empty()
    st.board[1][0] = Piece(0, "king")
    st.board[2][2] = Piece(1, "king")
    assert _move(rules, st, 0, (0, 1), (0, 0)) is None
    assert not st.over
    assert _move(rules, st, 1, (2, 2), (2, 1)) is None
    assert st.over and st.winner == 0 and st.reason == "king_reached"


def test_illegal_and_out_of_turn_rejected() -> None:
    rules = TwelveJanggiRules()
    st = rules.new_state(random.Random(0))
    st.to_act = 0
    assert _move(rules, st, 1, (1, 1), (1, 2)) == "not_your_turn"
    assert _move(rules, st, 0, (1, 2), (0, 1)) == "illegal_move"
    assert rules.apply(st, 0, {"kind": "drop", "piece": "rook", "to": [0, 1]}) == "illegal_move"
    assert rules.apply(st, 0, {"kind": "move", "from": "x"}) == "illegal_move"
