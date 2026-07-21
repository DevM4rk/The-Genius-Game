import sys
from pathlib import Path

# Allow importing shared protocol models in tests without install.
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "shared" / "protocol"))

from fastapi.testclient import TestClient

from app.main import app


def test_health():
    client = TestClient(app)
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"
    assert "omok" in body["games"]


def test_dev_login_and_create_room():
    client = TestClient(app)
    login = client.post("/auth/dev/login", json={"display_name": "Alice", "user_id": "u1"})
    assert login.status_code == 200
    token = login.json()["access_token"]
    assert token

    room = client.post("/rooms", json={"game": "omok"})
    assert room.status_code == 200
    data = room.json()
    assert data["join_path"].startswith("/play/")
    info = client.get(f"/rooms/{data['room_id']}")
    assert info.status_code == 200
    assert info.json()["status"] == "waiting"


def test_omok_five_detection():
    from app.services.omok_rules import BLACK, is_five, place

    board = [0] * 225
    for x in range(5):
        place(board, x, 7, BLACK)
    assert is_five(board, 4, 7, BLACK)
