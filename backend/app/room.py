"""사설 방 관리 — 최대 2인, 서버 권위 보드."""

from __future__ import annotations

import asyncio
import secrets
import string
from dataclasses import dataclass, field
from typing import Any, Callable

from fastapi import WebSocket

from .board import GameState, GomokuBoard, MoveResult, Stone
from .protocol import msg, move_result_name, state_name, stone_name

TURN_SECONDS = 30
ROOM_ID_ALPHABET = string.ascii_lowercase + string.digits
ROOM_ID_LENGTH = 5


@dataclass
class Player:
    ws: WebSocket
    color: Stone


@dataclass
class Room:
    room_id: str
    board: GomokuBoard = field(default_factory=GomokuBoard)
    players: list[Player] = field(default_factory=list)
    turn_deadline: float | None = None
    _timer_task: asyncio.Task | None = field(default=None, repr=False)

    @property
    def is_full(self) -> bool:
        return len(self.players) >= 2

    @property
    def started(self) -> bool:
        return len(self.players) == 2

    def player_by_ws(self, ws: WebSocket) -> Player | None:
        for p in self.players:
            if p.ws is ws:
                return p
        return None

    def opponent(self, ws: WebSocket) -> Player | None:
        for p in self.players:
            if p.ws is not ws:
                return p
        return None


class RoomManager:
    def __init__(self) -> None:
        self._rooms: dict[str, Room] = {}
        self._lock = asyncio.Lock()

    def create_room(self) -> str:
        while True:
            room_id = "".join(
                secrets.choice(ROOM_ID_ALPHABET) for _ in range(ROOM_ID_LENGTH)
            )
            if room_id not in self._rooms:
                self._rooms[room_id] = Room(room_id=room_id)
                return room_id

    def get(self, room_id: str) -> Room | None:
        return self._rooms.get(room_id)

    def room_public(self, room: Room) -> dict[str, Any]:
        return {
            "room_id": room.room_id,
            "players": len(room.players),
            "started": room.started,
            "state": state_name(room.board.state),
            "current_turn": stone_name(room.board.current_turn),
        }

    async def connect(self, room_id: str, ws: WebSocket) -> Room | None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                # URL로 직접 접속해도 방이 있으면 조인, 없으면 생성
                room = Room(room_id=room_id)
                self._rooms[room_id] = room
            if room.is_full:
                return None

            color = Stone.BLACK if len(room.players) == 0 else Stone.WHITE
            room.players.append(Player(ws=ws, color=color))
            return room

    async def disconnect(self, room_id: str, ws: WebSocket) -> None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                return

            self._cancel_timer(room)
            leaving = room.player_by_ws(ws)
            room.players = [p for p in room.players if p.ws is not ws]

            if leaving is not None and room.players:
                await self._send(
                    room.players[0].ws,
                    msg("opponent_left", color=stone_name(leaving.color)),
                )

            if not room.players:
                self._rooms.pop(room_id, None)
            else:
                # 한 명만 남으면 대기 상태로 리셋
                room.board.reset()
                room.players[0].color = Stone.BLACK
                room.turn_deadline = None

    async def handle_place(self, room: Room, ws: WebSocket, x: int, y: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return
        if room.board.state != GameState.PLAYING:
            await self._send(ws, msg("error", message="game_already_over"))
            return
        if room.board.current_turn != player.color:
            await self._send(ws, msg("error", message="not_your_turn"))
            return

        result = room.board.place_stone(x, y)
        if result != MoveResult.OK:
            await self._send(
                ws,
                msg("error", message=move_result_name(result), x=x, y=y),
            )
            return

        self._cancel_timer(room)
        placed_color = player.color
        payload = msg(
            "move",
            x=x,
            y=y,
            color=stone_name(placed_color),
            current_turn=stone_name(room.board.current_turn),
            state=state_name(room.board.state),
            board=room.board.snapshot(),
            turn_seconds=TURN_SECONDS if room.board.state == GameState.PLAYING else None,
        )
        await self._broadcast(room, payload)

        if room.board.state == GameState.PLAYING:
            self._arm_timer(room)

    async def handle_restart(self, room: Room, ws: WebSocket) -> None:
        if room.player_by_ws(ws) is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return

        self._cancel_timer(room)
        room.board.reset()
        await self._broadcast(
            room,
            msg(
                "game_start",
                current_turn=stone_name(room.board.current_turn),
                board=room.board.snapshot(),
                state=state_name(room.board.state),
                turn_seconds=TURN_SECONDS,
            ),
        )
        self._arm_timer(room)

    async def on_joined(self, room: Room, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        assert player is not None

        await self._send(
            ws,
            msg(
                "joined",
                room_id=room.room_id,
                color=stone_name(player.color),
                players=len(room.players),
                board=room.board.snapshot(),
                current_turn=stone_name(room.board.current_turn),
                state=state_name(room.board.state),
            ),
        )

        if room.started:
            self._cancel_timer(room)
            room.board.reset()
            # 흑/백 재할당: 먼저 들어온 사람 = 흑
            room.players[0].color = Stone.BLACK
            room.players[1].color = Stone.WHITE
            for p in room.players:
                await self._send(
                    p.ws,
                    msg(
                        "game_start",
                        your_color=stone_name(p.color),
                        current_turn=stone_name(room.board.current_turn),
                        board=room.board.snapshot(),
                        state=state_name(room.board.state),
                        turn_seconds=TURN_SECONDS,
                    ),
                )
            self._arm_timer(room)
        else:
            await self._send(ws, msg("waiting", message="waiting_for_opponent"))

    def _arm_timer(self, room: Room) -> None:
        self._cancel_timer(room)
        loop = asyncio.get_running_loop()
        room.turn_deadline = loop.time() + TURN_SECONDS
        room._timer_task = asyncio.create_task(self._turn_timeout(room))

    def _cancel_timer(self, room: Room) -> None:
        if room._timer_task is not None and not room._timer_task.done():
            room._timer_task.cancel()
        room._timer_task = None
        room.turn_deadline = None

    async def _turn_timeout(self, room: Room) -> None:
        try:
            await asyncio.sleep(TURN_SECONDS)
        except asyncio.CancelledError:
            return

        async with self._lock:
            if room.room_id not in self._rooms:
                return
            if room.board.state != GameState.PLAYING or not room.started:
                return

            # 시간 초과한 쪽 패배
            loser = room.board.current_turn
            room.board.state = (
                GameState.WHITE_WIN if loser == Stone.BLACK else GameState.BLACK_WIN
            )
            await self._broadcast(
                room,
                msg(
                    "timeout",
                    loser=stone_name(loser),
                    state=state_name(room.board.state),
                    board=room.board.snapshot(),
                    current_turn=stone_name(room.board.current_turn),
                ),
            )
            room.turn_deadline = None
            room._timer_task = None

    async def _broadcast(self, room: Room, payload: dict[str, Any]) -> None:
        dead: list[WebSocket] = []
        for p in room.players:
            try:
                await p.ws.send_json(payload)
            except Exception:
                dead.append(p.ws)
        for ws in dead:
            await self.disconnect(room.room_id, ws)

    @staticmethod
    async def _send(ws: WebSocket, payload: dict[str, Any]) -> None:
        await ws.send_json(payload)


manager = RoomManager()

DEFAULT_QUICK_GAME = "gomoku"


def resolve_quick_game(pref_a: str | None, pref_b: str | None) -> str | None:
    """A/B 매칭 규칙.

    - A1-A1 → game1
    - A1-A2 → 불가
    - A1-B / B-A1 → game1
    - B-B → 기본 게임
    """
    if pref_a and pref_b:
        return pref_a if pref_a == pref_b else None
    if pref_a:
        return pref_a
    if pref_b:
        return pref_b
    return DEFAULT_QUICK_GAME


class QueueEntry:
    __slots__ = ("ws", "preferred_game", "future")

    def __init__(
        self,
        ws: WebSocket,
        preferred_game: str | None,
        future: asyncio.Future,
    ) -> None:
        self.ws = ws
        self.preferred_game = preferred_game
        self.future = future


class MatchQueue:
    """게스트 빠른 매칭 — preferred_game(A) / None=any(B) 규칙으로 짝지음.

    게임마다 방 생성 방식(및 상태 저장소)이 다르므로, 매칭이 성사된
    게임 id에 맞는 방 생성 함수를 `room_factories`에서 찾는다. 목록에
    없는 game_id(향후 추가될 게임 등)는 `default_factory`(오목 방)로
    처리해 기존 동작을 그대로 유지한다.
    """

    def __init__(
        self,
        room_factories: dict[str, Callable[[], str]],
        default_factory: Callable[[], str],
    ) -> None:
        self._room_factories = room_factories
        self._default_factory = default_factory
        self._lock = asyncio.Lock()
        self._waiting: list[QueueEntry] = []

    async def enqueue(
        self, ws: WebSocket, preferred_game: str | None
    ) -> tuple[str, str]:
        """대기열에 들어가고, 상대가 잡히면 (room_id, game_id)를 리턴."""
        async with self._lock:
            for i, other in enumerate(self._waiting):
                if other.ws is ws:
                    continue
                game_id = resolve_quick_game(preferred_game, other.preferred_game)
                if game_id is None:
                    continue
                self._waiting.pop(i)
                factory = self._room_factories.get(game_id, self._default_factory)
                room_id = factory()
                result = (room_id, game_id)
                if not other.future.done():
                    other.future.set_result(result)
                return result

            fut: asyncio.Future = asyncio.get_running_loop().create_future()
            self._waiting.append(QueueEntry(ws, preferred_game, fut))

        return await fut

    async def cancel(self, ws: WebSocket) -> None:
        async with self._lock:
            kept: list[QueueEntry] = []
            for entry in self._waiting:
                if entry.ws is ws:
                    if not entry.future.done():
                        entry.future.cancel()
                else:
                    kept.append(entry)
            self._waiting = kept
