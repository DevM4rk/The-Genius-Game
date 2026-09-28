"""1:1 온라인 소형 게임 공용 방 — 게임마다 규칙 객체만 갈아 끼운다.

규칙 객체는 상태 생성, 행동 적용, 플레이어별 화면 상태만 책임진다.
숨겨야 하는 정보는 view()에서 수신자 기준으로 걸러야 한다.
"""

from __future__ import annotations

import asyncio
import random
import secrets
import string
from dataclasses import dataclass, field
from typing import Any, Protocol

from fastapi import WebSocket

from .protocol import msg

ROOM_ID_ALPHABET = string.ascii_lowercase + string.digits
ROOM_ID_LENGTH = 5


def parse_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


class DuelRules(Protocol):
    game_id: str

    def new_state(self, rng: random.Random) -> Any: ...

    def apply(self, state: Any, idx: int, action: dict[str, Any]) -> str | None:
        """행동을 적용한다. 거절하면 에러 코드를 돌려준다."""
        ...

    def view(self, state: Any, idx: int) -> dict[str, Any]: ...


@dataclass
class DuelPlayer:
    ws: WebSocket
    index: int


@dataclass
class DuelRoom:
    room_id: str
    players: list[DuelPlayer] = field(default_factory=list)
    state: Any = None
    segment: int = 0

    @property
    def is_full(self) -> bool:
        return len(self.players) >= 2

    @property
    def started(self) -> bool:
        return len(self.players) == 2 and self.state is not None

    def player_by_ws(self, ws: WebSocket) -> DuelPlayer | None:
        for p in self.players:
            if p.ws is ws:
                return p
        return None


class DuelRoomManager:
    def __init__(self, rules: DuelRules, rng: random.Random | None = None) -> None:
        self.rules = rules
        self._rng = rng or random.Random()
        self._rooms: dict[str, DuelRoom] = {}
        self._lock = asyncio.Lock()

    def create_room(self) -> str:
        while True:
            room_id = "".join(
                secrets.choice(ROOM_ID_ALPHABET) for _ in range(ROOM_ID_LENGTH)
            )
            if room_id not in self._rooms:
                self._rooms[room_id] = DuelRoom(room_id=room_id)
                return room_id

    def get(self, room_id: str) -> DuelRoom | None:
        return self._rooms.get(room_id)

    async def connect(self, room_id: str, ws: WebSocket) -> DuelRoom | None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                room = DuelRoom(room_id=room_id)
                self._rooms[room_id] = room
            if room.is_full:
                return None
            idx = 0 if len(room.players) == 0 else 1
            room.players.append(DuelPlayer(ws=ws, index=idx))
            return room

    async def disconnect(self, room_id: str, ws: WebSocket) -> None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                return

            leaving = room.player_by_ws(ws)
            room.players = [p for p in room.players if p.ws is not ws]
            room.state = None

            if leaving is not None and room.players:
                await self._send(room.players[0].ws, msg("duel_opponent_left"))

            if not room.players:
                self._rooms.pop(room_id, None)
            else:
                room.players[0].index = 0

    async def on_joined(self, room: DuelRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        assert player is not None

        await self._send(
            ws,
            msg(
                "duel_joined",
                game_id=self.rules.game_id,
                room_id=room.room_id,
                you=player.index,
                players=len(room.players),
            ),
        )

        if len(room.players) == 2:
            room.state = self.rules.new_state(self._rng)
            await self._broadcast_state(room)
        else:
            await self._send(ws, msg("duel_waiting"))

    async def handle_action(self, room: DuelRoom, ws: WebSocket, action: dict[str, Any]) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return

        error = self.rules.apply(room.state, player.index, action)
        if error is not None:
            await self._send(ws, msg("error", message=error))
            return
        await self._broadcast_state(room)

    async def handle_rematch(self, room: DuelRoom, ws: WebSocket) -> None:
        if room.player_by_ws(ws) is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if len(room.players) < 2:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return

        room.segment += 1
        room.state = self.rules.new_state(self._rng)
        await self._broadcast_state(room)

    def _state_for(self, room: DuelRoom, idx: int) -> dict[str, Any]:
        return msg(
            "duel_state",
            game_id=self.rules.game_id,
            you=idx,
            segment=room.segment,
            **self.rules.view(room.state, idx),
        )

    async def _broadcast_state(self, room: DuelRoom) -> None:
        dead: list[WebSocket] = []
        for p in room.players:
            try:
                await p.ws.send_json(self._state_for(room, p.index))
            except Exception:
                dead.append(p.ws)
        for ws in dead:
            await self.disconnect(room.room_id, ws)

    @staticmethod
    async def _send(ws: WebSocket, payload: dict[str, Any]) -> None:
        await ws.send_json(payload)
