"""WebSocket 사설 방 스모크 테스트."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_health_and_create_room() -> None:
    client = TestClient(app)
    assert client.get("/health").json()["status"] == "ok"
    room = client.post("/api/rooms").json()
    assert "room_id" in room
    assert len(room["room_id"]) == 5


def test_ws_two_players_place() -> None:
    client = TestClient(app)
    room_id = client.post("/api/rooms").json()["room_id"]

    with client.websocket_connect(f"/ws/{room_id}") as ws_a:
        joined_a = ws_a.receive_json()
        assert joined_a["type"] == "joined"
        assert joined_a["color"] == "black"
        assert ws_a.receive_json()["type"] == "waiting"

        with client.websocket_connect(f"/ws/{room_id}") as ws_b:
            start_a = ws_a.receive_json()
            assert start_a["type"] == "game_start"

            msgs_b = [ws_b.receive_json(), ws_b.receive_json()]
            types_b = {m["type"] for m in msgs_b}
            assert "joined" in types_b
            assert "game_start" in types_b

            ws_a.send_json({"type": "place", "x": 7, "y": 7})
            move_a = ws_a.receive_json()
            move_b = ws_b.receive_json()
            assert move_a["type"] == "move"
            assert move_b["type"] == "move"
            assert move_a["x"] == 7 and move_a["color"] == "black"
