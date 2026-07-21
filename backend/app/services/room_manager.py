"""In-memory room registry for Phase 0/2 scaffolding.

Phase 3 will dual-write room metadata to Redis and persist match results to Postgres.
"""

from __future__ import annotations

import secrets
import string
from typing import Optional

from app.models.room import Room, RoomStatus


def _short_code(length: int = 5) -> str:
    alphabet = string.ascii_lowercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


class RoomManager:
    def __init__(self) -> None:
        self._rooms: dict[str, Room] = {}

    async def create_room(
        self,
        *,
        game: str,
        mode: str,
        ruleset: str = "freestyle",
        room_id: Optional[str] = None,
    ) -> Room:
        code = room_id or _short_code()
        while code in self._rooms:
            code = _short_code()
        room = Room(room_id=code, game=game, mode=mode, ruleset=ruleset)
        self._rooms[code] = room
        return room

    def get_room(self, room_id: str) -> Optional[Room]:
        return self._rooms.get(room_id)

    def remove_room(self, room_id: str) -> None:
        self._rooms.pop(room_id, None)

    def list_rooms(self) -> list[Room]:
        return list(self._rooms.values())

    def mark_playing(self, room_id: str) -> None:
        room = self._rooms.get(room_id)
        if room:
            room.status = RoomStatus.PLAYING


room_manager = RoomManager()
