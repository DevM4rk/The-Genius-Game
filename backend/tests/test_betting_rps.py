"""베팅 가위바위보 — 규칙과 공용 1:1 방(duel_*) 온라인 흐름."""

from __future__ import annotations

import random

from fastapi.testclient import TestClient

from app.betting_rps import BettingRPSRules, rps_winner
from app.main import app


def _new():
    rules = BettingRPSRules()
    return rules, rules.new_state(random.Random(0))


def test_rps_winner() -> None:
    assert rps_winner("rock", "scissors") == 0
    assert rps_winner("rock", "paper") == 1
    assert rps_winner("paper", "paper") == -1


def test_winner_takes_loser_bet_only() -> None:
    rules, st = _new()
    assert rules.apply(st, 0, {"hand": "rock", "bet": 2}) is None
    assert rules.apply(st, 1, {"hand": "scissors", "bet": 5}) is None
    assert st.chips == [15, 5]
    assert st.round_index == 1
    assert st.last_result["winner"] == 0


def test_draw_keeps_chips() -> None:
    rules, st = _new()
    rules.apply(st, 0, {"hand": "paper", "bet": 3})
    rules.apply(st, 1, {"hand": "paper", "bet": 9})
    assert st.chips == [10, 10]


def test_invalid_actions() -> None:
    rules, st = _new()
    assert rules.apply(st, 0, {"hand": "lizard", "bet": 1}) == "invalid_hand"
    assert rules.apply(st, 0, {"hand": "rock", "bet": 0}) == "invalid_bet"
    assert rules.apply(st, 0, {"hand": "rock", "bet": 11}) == "invalid_bet"
    assert rules.apply(st, 0, {"hand": "rock", "bet": "x"}) == "invalid_bet"
    assert rules.apply(st, 0, {"hand": "rock", "bet": 1}) is None
    assert rules.apply(st, 0, {"hand": "rock", "bet": 1}) == "already_submitted"


def test_pending_hand_hidden_from_opponent() -> None:
    rules, st = _new()
    rules.apply(st, 0, {"hand": "rock", "bet": 4})
    opp_view = rules.view(st, 1)
    assert opp_view["opp_submitted"] is True
    assert opp_view["my_pending"] is None
    assert "rock" not in str(opp_view)


def test_zero_chips_ends_game() -> None:
    rules, st = _new()
    rules.apply(st, 0, {"hand": "rock", "bet": 1})
    rules.apply(st, 1, {"hand": "paper", "bet": 10})
    rules.apply(st, 0, {"hand": "rock", "bet": 9})
    rules.apply(st, 1, {"hand": "paper", "bet": 1})
    assert st.chips == [0, 20]
    view = rules.view(st, 0)
    assert view["is_over"] is True and view["winner"] == 1
    assert rules.apply(st, 0, {"hand": "rock", "bet": 1}) == "game_already_over"


def test_online_round_through_duel_room() -> None:
    client = TestClient(app)
    with client.websocket_connect("/ws/quick?game=betting_rps") as ws_a:
        assert ws_a.receive_json()["type"] == "queued"
        with client.websocket_connect("/ws/quick?game=betting_rps") as ws_b:
            for ws in (ws_a, ws_b):
                types = []
                while not types or types[-1] != "duel_state":
                    types.append(ws.receive_json()["type"])
                assert "matched" in types and "duel_joined" in types

            ws_a.send_json({"type": "duel_action", "hand": "rock", "bet": 3})
            a1 = ws_a.receive_json()
            b1 = ws_b.receive_json()
            assert a1["my_submitted"] is True
            assert b1["opp_submitted"] is True and "rock" not in str(b1)

            ws_b.send_json({"type": "duel_action", "hand": "paper", "bet": 2})
            a2 = ws_a.receive_json()
            b2 = ws_b.receive_json()
            assert a2["my_chips"] == 7 and b2["my_chips"] == 13
            assert b2["last_result"]["hands"][a2["you"]] == "rock"

            ws_a.send_json({"type": "duel_rematch"})
            a3 = ws_a.receive_json()
            assert a3["segment"] == 1 and a3["my_chips"] == 10
            ws_b.receive_json()
