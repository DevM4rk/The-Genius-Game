"""게스트 빠른 매칭(대기열) 스모크 테스트."""

from __future__ import annotations

from starlette.testclient import WebSocketTestSession

from fastapi.testclient import TestClient

from app.main import app


def _drain_until(ws: WebSocketTestSession, target_type: str) -> list[dict]:
    """target_type 메시지가 나올 때까지 받은 메시지를 전부 모아서 리턴."""
    messages: list[dict] = []
    for _ in range(10):
        m = ws.receive_json()
        messages.append(m)
        if m["type"] == target_type:
            return messages
    raise AssertionError(f"{target_type} not received, got: {messages}")


def test_quick_match_pairs_two_guests() -> None:
    client = TestClient(app)

    with client.websocket_connect("/ws/quick") as ws_a:
        assert ws_a.receive_json()["type"] == "queued"

        with client.websocket_connect("/ws/quick") as ws_b:
            msgs_a = _drain_until(ws_a, "game_start")
            msgs_b = _drain_until(ws_b, "game_start")

            types_a = [m["type"] for m in msgs_a]
            types_b = [m["type"] for m in msgs_b]
            assert "matched" in types_a and "joined" in types_a
            assert "matched" in types_b and "joined" in types_b

            matched_a = next(m for m in msgs_a if m["type"] == "matched")
            matched_b = next(m for m in msgs_b if m["type"] == "matched")
            assert matched_a["room_id"] == matched_b["room_id"]

            start_a = next(m for m in msgs_a if m["type"] == "game_start")
            start_b = next(m for m in msgs_b if m["type"] == "game_start")
            assert {start_a["your_color"], start_b["your_color"]} == {
                "black",
                "white",
            }

            black_ws = ws_a if start_a["your_color"] == "black" else ws_b
            black_ws.send_json({"type": "place", "x": 3, "y": 3})
            move_a = ws_a.receive_json()
            move_b = ws_b.receive_json()
            assert move_a["type"] == "move" and move_a["x"] == 3
            assert move_b["type"] == "move" and move_b["x"] == 3
