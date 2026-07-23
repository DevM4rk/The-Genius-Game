"""흑과백 데스매치 — 서버 권위 방 (숨겨진 타일 값은 절대 상대에게 전달하지 않음).

클라이언트는 자신의 9장 배치(순서)만 서버로 보내고, 서버는 그 배치를
저장한 뒤 상대에게는 "그 슬롯의 색"과 "사용 여부"만 알려준다. 라운드
결과도 승/무만 알려주고 실제 숫자는 매치가 끝난 뒤에도 공개하지 않는다.
"""

from __future__ import annotations

import asyncio
import random
import secrets
import string
from dataclasses import dataclass, field
from typing import Any

from fastapi import WebSocket

from .protocol import msg

ROOM_ID_ALPHABET = string.ascii_lowercase + string.digits
ROOM_ID_LENGTH = 5
TILE_COUNT = 9


def is_black(value: int) -> bool:
    return value % 2 == 0


@dataclass
class BWPlayer:
    ws: WebSocket
    index: int
    arrangement: list[int] | None = None


@dataclass
class BWRoom:
    room_id: str
    players: list[BWPlayer] = field(default_factory=list)
    scores: list[int] = field(default_factory=lambda: [0, 0])
    used: list[list[bool]] = field(
        default_factory=lambda: [[False] * TILE_COUNT, [False] * TILE_COUNT]
    )
    round_index: int = 0
    starter: int = 0
    segment: int = 0
    pending_first_slot: int = -1
    pending_first_value: int = -1
    last_result: dict[str, Any] | None = None
    history: list[dict[str, Any]] = field(default_factory=list)

    @property
    def is_full(self) -> bool:
        return len(self.players) >= 2

    @property
    def started(self) -> bool:
        return len(self.players) == 2

    def player_by_ws(self, ws: WebSocket) -> BWPlayer | None:
        for p in self.players:
            if p.ws is ws:
                return p
        return None

    def other_index(self, idx: int) -> int:
        return 1 - idx

    def both_arranged(self) -> bool:
        return len(self.players) == 2 and all(p.arrangement is not None for p in self.players)

    def is_over(self) -> bool:
        return self.round_index >= TILE_COUNT

    def is_tie(self) -> bool:
        return self.is_over() and self.scores[0] == self.scores[1]


class BWRoomManager:
    def __init__(self) -> None:
        self._rooms: dict[str, BWRoom] = {}
        self._lock = asyncio.Lock()

    def create_room(self) -> str:
        while True:
            room_id = "".join(
                secrets.choice(ROOM_ID_ALPHABET) for _ in range(ROOM_ID_LENGTH)
            )
            if room_id not in self._rooms:
                self._rooms[room_id] = BWRoom(room_id=room_id)
                return room_id

    def get(self, room_id: str) -> BWRoom | None:
        return self._rooms.get(room_id)

    async def connect(self, room_id: str, ws: WebSocket) -> BWRoom | None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                room = BWRoom(room_id=room_id)
                self._rooms[room_id] = room
            if room.is_full:
                return None

            idx = 0 if len(room.players) == 0 else 1
            room.players.append(BWPlayer(ws=ws, index=idx))
            return room

    async def disconnect(self, room_id: str, ws: WebSocket) -> None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                return

            leaving = room.player_by_ws(ws)
            room.players = [p for p in room.players if p.ws is not ws]

            if leaving is not None and room.players:
                await self._send(room.players[0].ws, msg("bw_opponent_left"))

            if not room.players:
                self._rooms.pop(room_id, None)
            else:
                room.players[0].index = 0
                self._start_segment(room)

    async def on_joined(self, room: BWRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        assert player is not None

        await self._send(
            ws,
            msg("bw_joined", room_id=room.room_id, you=player.index, players=len(room.players)),
        )

        if room.started:
            self._start_segment(room)
            await self._broadcast_state(room)
        else:
            await self._send(ws, msg("bw_waiting"))

    def _start_segment(self, room: BWRoom) -> None:
        room.scores = [0, 0]
        room.used = [[False] * TILE_COUNT, [False] * TILE_COUNT]
        room.round_index = 0
        room.starter = random.randint(0, 1)
        room.pending_first_slot = -1
        room.pending_first_value = -1
        room.last_result = None
        room.history = []
        for p in room.players:
            p.arrangement = None

    async def handle_arrange(self, room: BWRoom, ws: WebSocket, arrangement: list[int]) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if sorted(arrangement) != list(range(TILE_COUNT)):
            await self._send(ws, msg("error", message="invalid_arrangement"))
            return

        player.arrangement = list(arrangement)
        if room.both_arranged():
            await self._broadcast_state(room)
        else:
            await self._send(ws, msg("bw_wait_arrange"))

    async def handle_play(self, room: BWRoom, ws: WebSocket, slot: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started or not room.both_arranged():
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return
        if room.is_over():
            await self._send(ws, msg("error", message="game_already_over"))
            return
        if slot < 0 or slot >= TILE_COUNT:
            await self._send(ws, msg("error", message="invalid_slot"))
            return

        idx = player.index
        assert player.arrangement is not None

        if room.pending_first_slot < 0:
            if idx != room.starter:
                await self._send(ws, msg("error", message="not_your_turn"))
                return
            if room.used[idx][slot]:
                await self._send(ws, msg("error", message="slot_used"))
                return
            room.used[idx][slot] = True
            room.pending_first_slot = slot
            room.pending_first_value = player.arrangement[slot]
            await self._broadcast_state(room)
            return

        second_idx = room.other_index(room.starter)
        if idx != second_idx:
            await self._send(ws, msg("error", message="not_your_turn"))
            return
        if room.used[idx][slot]:
            await self._send(ws, msg("error", message="slot_used"))
            return

        room.used[idx][slot] = True
        second_value = player.arrangement[slot]
        first_value = room.pending_first_value
        first_slot = room.pending_first_slot

        winner = -1
        if first_value > second_value:
            winner = room.starter
        elif second_value > first_value:
            winner = second_idx
        if winner >= 0:
            room.scores[winner] += 1

        room.last_result = {
            "round": room.round_index,
            "starter": room.starter,
            "starter_slot": first_slot,
            "second_slot": slot,
            "winner": winner,
        }
        room.history.append(
            {
                "round": room.round_index,
                "starter": room.starter,
                "starter_slot": first_slot,
                "starter_tile": first_value,
                "second_slot": slot,
                "second_tile": second_value,
                "winner": winner,
            }
        )
        room.round_index += 1
        if winner >= 0:
            room.starter = winner
        room.pending_first_slot = -1
        room.pending_first_value = -1

        await self._broadcast_state(room)

    async def handle_rematch(self, room: BWRoom, ws: WebSocket) -> None:
        if room.player_by_ws(ws) is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return

        room.segment += 1
        self._start_segment(room)
        await self._broadcast_state(room)

    def _state_for(self, room: BWRoom, idx: int) -> dict[str, Any]:
        me = next((p for p in room.players if p.index == idx), None)
        opp_idx = room.other_index(idx)
        opp = next((p for p in room.players if p.index == opp_idx), None)

        my_hand: list[dict[str, Any]] = []
        if me is not None and me.arrangement is not None:
            for slot in range(TILE_COUNT):
                used = room.used[idx][slot]
                my_hand.append({"slot": slot, "value": me.arrangement[slot], "used": used})

        opp_hand: list[dict[str, Any]] = []
        if opp is not None and opp.arrangement is not None:
            for slot in range(TILE_COUNT):
                used = room.used[opp_idx][slot]
                value = opp.arrangement[slot]
                opp_hand.append(
                    {"slot": slot, "color": "black" if is_black(value) else "white", "used": used}
                )

        turn: str | None = None
        if room.both_arranged() and not room.is_over():
            if room.pending_first_slot < 0:
                turn = "first" if room.starter == idx else "wait"
            else:
                turn = "second" if room.other_index(room.starter) == idx else "wait"

        # 매치 종료 후에만 라운드별 숫자 공개. 진행 중에는 상대 숫자를 보내지 않는다.
        reveal: list[dict[str, Any]] = []
        if room.is_over():
            reveal = list(room.history)

        return msg(
            "bw_state",
            you=idx,
            segment=room.segment,
            round_index=room.round_index,
            starter=room.starter,
            scores=list(room.scores),
            turn=turn,
            arranged=me is not None and me.arrangement is not None,
            opp_arranged=opp is not None and opp.arrangement is not None,
            my_hand=my_hand,
            opp_hand=opp_hand,
            pending_first_slot=room.pending_first_slot,
            last_result=room.last_result,
            is_over=room.is_over(),
            is_tie=room.is_tie(),
            reveal=reveal,
        )

    async def _broadcast_state(self, room: BWRoom) -> None:
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


bw_manager = BWRoomManager()
