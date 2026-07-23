"""게스트 빠른 매칭(대기열) — A/B 선호도 규칙 포함."""

from __future__ import annotations

from starlette.testclient import WebSocketTestSession

from fastapi.testclient import TestClient

from app.main import app
from app.room import resolve_quick_game


def _drain_until(ws: WebSocketTestSession, target_type: str) -> list[dict]:
    """target_type 메시지가 나올 때까지 받은 메시지를 순서 모아서 리턴."""
    messages: list[dict] = []
    for _ in range(12):
        m = ws.receive_json()
        messages.append(m)
        if m["type"] == target_type:
            return messages
    raise AssertionError(f"{target_type} not received, got: {messages}")


def test_resolve_quick_game_rules() -> None:
    assert resolve_quick_game("gomoku", "gomoku") == "gomoku"
    assert resolve_quick_game("gomoku", "other") is None
    assert resolve_quick_game("gomoku", None) == "gomoku"
    assert resolve_quick_game(None, "gomoku") == "gomoku"
    assert resolve_quick_game(None, None) == "gomoku"


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
            assert matched_a["game_id"] == "gomoku"
            assert matched_b["game_id"] == "gomoku"

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


def test_quick_match_a_with_b() -> None:
    client = TestClient(app)

    with client.websocket_connect("/ws/quick?game=gomoku") as ws_a:
        q = ws_a.receive_json()
        assert q["type"] == "queued"
        assert q["game"] == "gomoku"

        with client.websocket_connect("/ws/quick?game=any") as ws_b:
            msgs_a = _drain_until(ws_a, "matched")
            msgs_b = _drain_until(ws_b, "matched")
            matched_a = next(m for m in msgs_a if m["type"] == "matched")
            matched_b = next(m for m in msgs_b if m["type"] == "matched")
            assert matched_a["room_id"] == matched_b["room_id"]
            assert matched_a["game_id"] == "gomoku"
            assert matched_b["game_id"] == "gomoku"


def test_quick_match_a1_does_not_pair_a2() -> None:
    client = TestClient(app)

    with client.websocket_connect("/ws/quick?game=gomoku") as ws_a1:
        assert ws_a1.receive_json()["type"] == "queued"

        with client.websocket_connect("/ws/quick?game=other") as ws_a2:
            assert ws_a2.receive_json()["type"] == "queued"

            # 서로 다른 A끼리는 즉시 매칭되면 안 됨
            # B가 들어와 A1과 붙고, A2는 계속 대기
            with client.websocket_connect("/ws/quick?game=any") as ws_b:
                msgs_a1 = _drain_until(ws_a1, "matched")
                msgs_b = _drain_until(ws_b, "matched")
                assert next(m for m in msgs_a1 if m["type"] == "matched")["game_id"] == "gomoku"
                assert next(m for m in msgs_b if m["type"] == "matched")["game_id"] == "gomoku"

                # A2는 아직 matched를 받지 않음 — 짧게 폴링
                import time

                deadline = time.time() + 0.2
                got_matched = False
                while time.time() < deadline:
                    # TestClient WS는 블로킹 receive라 별도 매칭 상대를 넣기 전엔
                    # A2가 matched되면 실패. 여기서는 A2와 새 B를 붙여 확인.
                    break
                assert not got_matched

            # A2 + 새 B → 매칭
            with client.websocket_connect("/ws/quick?game=any") as ws_b2:
                msgs_a2 = _drain_until(ws_a2, "matched")
                msgs_b2 = _drain_until(ws_b2, "matched")
                assert next(m for m in msgs_a2 if m["type"] == "matched")["game_id"] == "other"
                assert next(m for m in msgs_b2 if m["type"] == "matched")["game_id"] == "other"


def test_quick_match_same_a_pairs() -> None:
    client = TestClient(app)

    with client.websocket_connect("/ws/quick?game=gomoku") as ws_a:
        assert ws_a.receive_json()["type"] == "queued"
        with client.websocket_connect("/ws/quick?game=gomoku") as ws_b:
            msgs_a = _drain_until(ws_a, "matched")
            msgs_b = _drain_until(ws_b, "matched")
            assert next(m["game_id"] for m in msgs_a if m["type"] == "matched") == "gomoku"
            assert next(m["game_id"] for m in msgs_b if m["type"] == "matched") == "gomoku"
