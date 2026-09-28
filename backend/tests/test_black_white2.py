"""흑과백2 — 표시등/승패 규칙과 온라인 대전 흐름(시크릿 비공개 포함)."""

from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.testclient import WebSocketTestSession

from app.blackwhite2 import bid_color, decide_winner, lamp_level
from app.main import app


def test_bid_color() -> None:
    assert bid_color(0) == "black"
    assert bid_color(9) == "black"
    assert bid_color(10) == "white"
    assert bid_color(99) == "white"


def test_lamp_level_keeps_current_band_lit() -> None:
    assert lamp_level(99) == 5
    assert lamp_level(80) == 5
    assert lamp_level(79) == 4
    assert lamp_level(59) == 3
    assert lamp_level(40) == 3
    assert lamp_level(20) == 2
    assert lamp_level(19) == 1
    assert lamp_level(0) == 1


def test_decide_winner() -> None:
    assert decide_winner([5, 2], [10, 50]) == (0, "five_points")
    assert decide_winner([4, 3], [0, 90]) == (0, "score")
    assert decide_winner([4, 4], [10, 11]) == (1, "points")
    assert decide_winner([3, 3], [20, 20]) == (-1, "draw")


def _drain_until(ws: WebSocketTestSession, target_type: str) -> list[dict]:
    messages: list[dict] = []
    for _ in range(12):
        m = ws.receive_json()
        messages.append(m)
        if m["type"] == target_type:
            return messages
    raise AssertionError(f"{target_type} not received, got: {messages}")


def _match_pair(client: TestClient):
    ws_a = client.websocket_connect("/ws/quick?game=black_white2").__enter__()
    assert ws_a.receive_json()["type"] == "queued"
    ws_b = client.websocket_connect("/ws/quick?game=black_white2").__enter__()
    state_a = _drain_until(ws_a, "bw2_state")[-1]
    state_b = _drain_until(ws_b, "bw2_state")[-1]
    return ws_a, ws_b, state_a, state_b


def _roles(ws_a, ws_b, state_a, state_b):
    """(선 ws, 후 ws, 선 state, 후 state)."""
    if state_a["turn"] == "first":
        return ws_a, ws_b, state_a, state_b
    assert state_b["turn"] == "first"
    return ws_b, ws_a, state_b, state_a


def _play_round(first_ws, second_ws, first_bid: int, second_bid: int) -> tuple[dict, dict]:
    first_ws.send_json({"type": "bw2_bid", "amount": first_bid})
    first_ws.receive_json()
    second_ws.receive_json()
    second_ws.send_json({"type": "bw2_bid", "amount": second_bid})
    return first_ws.receive_json(), second_ws.receive_json()


def test_first_bid_shows_only_color_and_lamps_to_opponent() -> None:
    client = TestClient(app)
    ws_a, ws_b, state_a, state_b = _match_pair(client)
    try:
        assert state_a["my_points"] == 99 and state_a["opp_lamps"] == 5
        first_ws, second_ws, _, _ = _roles(ws_a, ws_b, state_a, state_b)

        first_ws.send_json({"type": "bw2_bid", "amount": 40})
        mine = first_ws.receive_json()
        theirs = second_ws.receive_json()

        assert mine["my_points"] == 59
        assert mine["my_lamps"] == 3
        assert mine["my_pending_bid"] == 40

        assert theirs["turn"] == "second"
        assert theirs["pending_first_color"] == "white"
        assert theirs["opp_lamps"] == 3
        assert theirs["my_pending_bid"] is None
        assert "40" not in str({k: v for k, v in theirs.items() if k != "you"})
        assert theirs["final_points"] is None
    finally:
        ws_a.close()
        ws_b.close()


def test_invalid_and_out_of_turn_bids_rejected() -> None:
    client = TestClient(app)
    ws_a, ws_b, state_a, state_b = _match_pair(client)
    try:
        first_ws, second_ws, _, _ = _roles(ws_a, ws_b, state_a, state_b)

        second_ws.send_json({"type": "bw2_bid", "amount": 5})
        assert second_ws.receive_json() == {"type": "error", "message": "not_your_turn"}

        first_ws.send_json({"type": "bw2_bid", "amount": 100})
        assert first_ws.receive_json() == {"type": "error", "message": "invalid_bid"}

        first_ws.send_json({"type": "bw2_bid", "amount": -1})
        assert first_ws.receive_json() == {"type": "error", "message": "invalid_bid"}
    finally:
        ws_a.close()
        ws_b.close()


def test_round_result_hides_bids_until_game_over() -> None:
    client = TestClient(app)
    ws_a, ws_b, state_a, state_b = _match_pair(client)
    try:
        first_ws, second_ws, _, _ = _roles(ws_a, ws_b, state_a, state_b)

        first_state, second_state = _play_round(first_ws, second_ws, 12, 7)
        result = second_state["last_result"]
        assert result["winner"] == first_state["you"]
        assert result["starter_color"] == "white"
        assert result["second_color"] == "black"
        assert "starter_bid" not in result and "second_bid" not in result
        assert second_state["reveal"] == []
        assert second_state["my_bids"] == [7]
        assert first_state["my_bids"] == [12]
        assert first_state["turn"] == "first"
    finally:
        ws_a.close()
        ws_b.close()


def test_five_points_ends_game_and_reveals_history() -> None:
    client = TestClient(app)
    ws_a, ws_b, state_a, state_b = _match_pair(client)
    try:
        first_ws, second_ws, _, _ = _roles(ws_a, ws_b, state_a, state_b)

        # 같은 사람이 계속 이기면 계속 선이다.
        for _ in range(5):
            winner_state, loser_state = _play_round(first_ws, second_ws, 1, 0)

        assert winner_state["is_over"] is True
        assert winner_state["round_index"] == 5
        assert winner_state["winner"] == winner_state["you"]
        assert winner_state["win_reason"] == "five_points"
        assert winner_state["turn"] is None
        assert len(loser_state["reveal"]) == 5
        assert loser_state["reveal"][0]["starter_bid"] == 1
        assert sorted(loser_state["final_points"]) == [94, 99]

        first_ws.send_json({"type": "bw2_bid", "amount": 0})
        assert first_ws.receive_json() == {"type": "error", "message": "game_already_over"}
    finally:
        ws_a.close()
        ws_b.close()


def test_tied_score_after_nine_rounds_goes_to_more_points() -> None:
    client = TestClient(app)
    ws_a, ws_b, state_a, state_b = _match_pair(client)
    try:
        first_ws, second_ws, _, _ = _roles(ws_a, ws_b, state_a, state_b)
        first_idx = state_a["you"] if first_ws is ws_a else state_b["you"]

        # 선이 이긴 다음 둘 다 0을 내면 무승부로 선이 유지된다.
        _play_round(first_ws, second_ws, 3, 1)
        _play_round(first_ws, second_ws, 0, 1)  # 후가 이겨 선이 바뀐다
        for _ in range(7):
            s1, s2 = _play_round(second_ws, first_ws, 0, 0)

        assert s1["is_over"] is True
        assert s1["scores"] == [1, 1]
        # 처음 선: 3 + 0 사용 → 96, 처음 후: 1 + 1 사용 → 97
        expected = [0, 0]
        expected[first_idx] = 96
        expected[1 - first_idx] = 97
        assert s1["final_points"] == expected
        assert s1["winner"] == 1 - first_idx
        assert s1["win_reason"] == "points"
    finally:
        ws_a.close()
        ws_b.close()
