"""흑과백2 — 포인트 입찰 데스매치, 서버 권위 방.

두 사람이 99포인트씩 들고 최대 9라운드를 진행한다. 매 라운드 선이 먼저,
후가 나중에 포인트를 내고 더 많이 낸 쪽이 승점 1점을 얻는다.

상대에게는 낸 포인트의 색(한 자릿수=흑, 두 자릿수=백)과 남은 포인트의
5단계 표시등만 보낸다. 실제로 낸 포인트와 잔액은 게임이 끝난 뒤에만 공개한다.
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
START_POINTS = 99
MAX_ROUNDS = 9
WIN_SCORE = 5
LAMP_COUNT = 5
LAMP_STEP = 20


def bid_color(amount: int) -> str:
    return "black" if amount < 10 else "white"


def lamp_level(points: int) -> int:
    """켜진 표시등 개수. 0~19=1, 20~39=2, 40~59=3, 60~79=4, 80~99=5."""
    return min(LAMP_COUNT, points // LAMP_STEP + 1)


def decide_winner(scores: list[int], points: list[int]) -> tuple[int, str]:
    """(승자 index, 사유). 승자가 없으면 -1."""
    for idx in (0, 1):
        if scores[idx] >= WIN_SCORE:
            return idx, "five_points"
    if scores[0] != scores[1]:
        return (0 if scores[0] > scores[1] else 1), "score"
    if points[0] != points[1]:
        return (0 if points[0] > points[1] else 1), "points"
    return -1, "draw"


@dataclass
class BW2Player:
    ws: WebSocket
    index: int


@dataclass
class BW2Room:
    room_id: str
    players: list[BW2Player] = field(default_factory=list)
    scores: list[int] = field(default_factory=lambda: [0, 0])
    points: list[int] = field(default_factory=lambda: [START_POINTS, START_POINTS])
    round_index: int = 0
    starter: int = 0
    segment: int = 0
    pending_first_bid: int = -1
    last_result: dict[str, Any] | None = None
    history: list[dict[str, Any]] = field(default_factory=list)

    @property
    def is_full(self) -> bool:
        return len(self.players) >= 2

    @property
    def started(self) -> bool:
        return len(self.players) == 2

    def player_by_ws(self, ws: WebSocket) -> BW2Player | None:
        for p in self.players:
            if p.ws is ws:
                return p
        return None

    def is_over(self) -> bool:
        return max(self.scores) >= WIN_SCORE or self.round_index >= MAX_ROUNDS


class BW2RoomManager:
    def __init__(self) -> None:
        self._rooms: dict[str, BW2Room] = {}
        self._lock = asyncio.Lock()

    def create_room(self) -> str:
        while True:
            room_id = "".join(
                secrets.choice(ROOM_ID_ALPHABET) for _ in range(ROOM_ID_LENGTH)
            )
            if room_id not in self._rooms:
                self._rooms[room_id] = BW2Room(room_id=room_id)
                return room_id

    def get(self, room_id: str) -> BW2Room | None:
        return self._rooms.get(room_id)

    async def connect(self, room_id: str, ws: WebSocket) -> BW2Room | None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                room = BW2Room(room_id=room_id)
                self._rooms[room_id] = room
            if room.is_full:
                return None

            idx = 0 if len(room.players) == 0 else 1
            room.players.append(BW2Player(ws=ws, index=idx))
            return room

    async def disconnect(self, room_id: str, ws: WebSocket) -> None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                return

            leaving = room.player_by_ws(ws)
            room.players = [p for p in room.players if p.ws is not ws]

            if leaving is not None and room.players:
                await self._send(room.players[0].ws, msg("bw2_opponent_left"))

            if not room.players:
                self._rooms.pop(room_id, None)
            else:
                room.players[0].index = 0
                self._start_segment(room)

    async def on_joined(self, room: BW2Room, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        assert player is not None

        await self._send(
            ws,
            msg("bw2_joined", room_id=room.room_id, you=player.index, players=len(room.players)),
        )

        if room.started:
            self._start_segment(room)
            await self._broadcast_state(room)
        else:
            await self._send(ws, msg("bw2_waiting"))

    def _start_segment(self, room: BW2Room) -> None:
        room.scores = [0, 0]
        room.points = [START_POINTS, START_POINTS]
        room.round_index = 0
        room.starter = random.randint(0, 1)
        room.pending_first_bid = -1
        room.last_result = None
        room.history = []

    async def handle_bid(self, room: BW2Room, ws: WebSocket, amount: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return
        if room.is_over():
            await self._send(ws, msg("error", message="game_already_over"))
            return

        idx = player.index
        is_first = room.pending_first_bid < 0
        expected = room.starter if is_first else 1 - room.starter
        if idx != expected:
            await self._send(ws, msg("error", message="not_your_turn"))
            return
        if amount < 0 or amount > room.points[idx]:
            await self._send(ws, msg("error", message="invalid_bid"))
            return

        # 낸 즉시 잔액에서 빠지므로, 후는 선의 표시등 변화를 보고 결정하게 된다.
        room.points[idx] -= amount

        if is_first:
            room.pending_first_bid = amount
            await self._broadcast_state(room)
            return

        first_bid = room.pending_first_bid
        winner = -1
        if first_bid > amount:
            winner = room.starter
        elif amount > first_bid:
            winner = idx
        if winner >= 0:
            room.scores[winner] += 1

        room.last_result = {
            "round": room.round_index,
            "starter": room.starter,
            "starter_color": bid_color(first_bid),
            "second_color": bid_color(amount),
            "winner": winner,
        }
        room.history.append(
            {
                "round": room.round_index,
                "starter": room.starter,
                "starter_bid": first_bid,
                "second_bid": amount,
                "winner": winner,
            }
        )
        room.round_index += 1
        if winner >= 0:
            room.starter = winner
        room.pending_first_bid = -1

        await self._broadcast_state(room)

    async def handle_rematch(self, room: BW2Room, ws: WebSocket) -> None:
        if room.player_by_ws(ws) is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return

        room.segment += 1
        self._start_segment(room)
        await self._broadcast_state(room)

    def _state_for(self, room: BW2Room, idx: int) -> dict[str, Any]:
        opp_idx = 1 - idx
        over = room.is_over()
        pending = room.pending_first_bid

        turn: str | None = None
        if room.started and not over:
            if pending < 0:
                turn = "first" if room.starter == idx else "wait"
            else:
                turn = "second" if room.starter != idx else "wait"

        my_bids = [
            h["starter_bid"] if h["starter"] == idx else h["second_bid"] for h in room.history
        ]

        winner, win_reason = decide_winner(room.scores, room.points) if over else (-1, "")

        return msg(
            "bw2_state",
            you=idx,
            segment=room.segment,
            round_index=room.round_index,
            max_rounds=MAX_ROUNDS,
            win_score=WIN_SCORE,
            starter=room.starter,
            scores=list(room.scores),
            turn=turn,
            my_points=room.points[idx],
            my_lamps=lamp_level(room.points[idx]),
            opp_lamps=lamp_level(room.points[opp_idx]),
            my_bids=my_bids,
            pending_first_color=bid_color(pending) if pending >= 0 else None,
            my_pending_bid=pending if pending >= 0 and room.starter == idx else None,
            last_result=room.last_result,
            is_over=over,
            winner=winner,
            win_reason=win_reason,
            final_points=list(room.points) if over else None,
            reveal=list(room.history) if over else [],
        )

    async def _broadcast_state(self, room: BW2Room) -> None:
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


bw2_manager = BW2RoomManager()
