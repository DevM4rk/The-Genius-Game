"""숫자장기 온라인(랜덤매칭) 방 관리자 — 서버가 유일한 권위자.

클라이언트에는 뷰어(내 시점)별로 정보를 가려서 내려보낸다:
  - 상대의 말은 뒤집혀 있어 종류/숫자를 알 수 없다(공개(revealed)되지
    않은 이상). 보드 스냅샷은 매 상태 전송마다 뷰어별로 새로 만든다.
  - 블라인드 아이템이 걸린 대결은 "결과만" 공개하고 정체·계산값(합/차)은
    감춘다 — 대결에 실제로 참여한 두 말은 원래 서로 공개되지만(대결의
    본질), 블라인드가 걸린 쪽만 예외로 가려진다.
"""

from __future__ import annotations

import asyncio
import secrets
import string
from dataclasses import dataclass, field
from typing import Any

from fastapi import WebSocket

from .number_janggi_match import ARRANGE, AWAITING_ITEMS, AWAITING_REWARD, MOVE, NumberJanggiMatch
from .protocol import msg

ROOM_ID_ALPHABET = string.ascii_lowercase + string.digits
ROOM_ID_LENGTH = 5
ARRANGE_SECONDS = 60
MOVE_SECONDS = 60


@dataclass
class NJPlayer:
    ws: WebSocket
    index: int


@dataclass
class NJRoom:
    room_id: str
    players: list[NJPlayer] = field(default_factory=list)
    match: NumberJanggiMatch = field(default_factory=NumberJanggiMatch)
    segment: int = 0
    started_match: bool = False
    event_seq: int = 0
    last_event: dict[str, Any] | None = None
    arrange_deadline: float | None = None
    move_deadline: float | None = None
    _arrange_task: asyncio.Task | None = field(default=None, repr=False)
    _move_task: asyncio.Task | None = field(default=None, repr=False)

    @property
    def is_full(self) -> bool:
        return len(self.players) >= 2

    @property
    def started(self) -> bool:
        return len(self.players) == 2

    def player_by_ws(self, ws: WebSocket) -> NJPlayer | None:
        for p in self.players:
            if p.ws is ws:
                return p
        return None


# ── 뷰어별 정보 가림 ─────────────────────────────────────────────
def _piece_public(p: dict[str, Any], viewer_side: int) -> dict[str, Any]:
    visible = p["side"] == viewer_side or p["revealed"]
    if visible:
        return {
            "id": p["id"],
            "side": p["side"],
            "type": p["type"],
            "value": p["value"],
            "revealed": p["revealed"],
        }
    return {"side": p["side"], "revealed": False}


def _board_for(match: NumberJanggiMatch, viewer_side: int) -> list[list[dict[str, Any] | None]]:
    out: list[list[dict[str, Any] | None]] = []
    for row_cells in match.board:
        out.append(
            [None if cell == -1 else _piece_public(match.pieces[cell], viewer_side) for cell in row_cells]
        )
    return out


def _graveyard_for(match: NumberJanggiMatch, side: int, viewer_side: int) -> list[dict[str, Any]]:
    return [_piece_public(match.pieces[pid], viewer_side) for pid in match.graveyard_of(side)]


def _redact_duel_event(match: NumberJanggiMatch, event: dict[str, Any], viewer_side: int) -> dict[str, Any]:
    hidden_ids: set[int] = set(event.get("hidden_ids", []))

    def side_entry(pid: int, value: int, base_value: int, removed: bool) -> dict[str, Any]:
        p = match.pieces[pid]
        owner = p["side"]
        is_hidden = pid in hidden_ids
        visible = owner == viewer_side or not is_hidden
        if visible:
            return {
                "id": pid,
                "side": owner,
                "type": p["type"],
                "value": value,
                "base_value": base_value,
                "removed": removed,
                "masked": False,
            }
        return {"side": owner, "removed": removed, "masked": True}

    reports_out: list[dict[str, Any]] = []
    for r in event["reports"]:
        a_entry = side_entry(r["a_id"], r["a_value"], r["a_base_value"], r["a_removed"])
        b_entry = side_entry(r["b_id"], r["b_value"], r["b_base_value"], r["b_removed"])
        masked_any = a_entry["masked"] or b_entry["masked"]
        score = r["score"] if (r["kind"] == "number" and not masked_any) else None
        winner_side = match.pieces[r["winner_id"]]["side"] if r["winner_id"] != -1 else None
        reports_out.append(
            {
                "kind": r["kind"],
                "is_minus": r["is_minus"],
                "score": score,
                "winner_side": winner_side,
                "a": a_entry,
                "b": b_entry,
            }
        )
    return {
        "seq": event["seq"],
        "type": "duel",
        "mover_side": event["mover_side"],
        "reports": reports_out,
    }


class NJRoomManager:
    def __init__(self) -> None:
        self._rooms: dict[str, NJRoom] = {}
        self._lock = asyncio.Lock()

    def create_room(self) -> str:
        while True:
            room_id = "".join(secrets.choice(ROOM_ID_ALPHABET) for _ in range(ROOM_ID_LENGTH))
            if room_id not in self._rooms:
                self._rooms[room_id] = NJRoom(room_id=room_id)
                return room_id

    def get(self, room_id: str) -> NJRoom | None:
        return self._rooms.get(room_id)

    async def connect(self, room_id: str, ws: WebSocket) -> NJRoom | None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                room = NJRoom(room_id=room_id)
                self._rooms[room_id] = room
            if room.is_full:
                return None
            idx = 0 if len(room.players) == 0 else 1
            room.players.append(NJPlayer(ws=ws, index=idx))
            return room

    async def disconnect(self, room_id: str, ws: WebSocket) -> None:
        async with self._lock:
            room = self._rooms.get(room_id)
            if room is None:
                return

            self._cancel_timers(room)
            leaving = room.player_by_ws(ws)
            room.players = [p for p in room.players if p.ws is not ws]

            if leaving is not None and room.players:
                await self._send(room.players[0].ws, msg("nj_opponent_left"))

            if not room.players:
                self._rooms.pop(room_id, None)
            else:
                room.players[0].index = 0
                self._reset_room(room)

    def _reset_room(self, room: NJRoom) -> None:
        room.match = NumberJanggiMatch()
        room.started_match = False
        room.event_seq = 0
        room.last_event = None
        room.arrange_deadline = None
        room.move_deadline = None

    async def on_joined(self, room: NJRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        assert player is not None

        await self._send(
            ws, msg("nj_joined", room_id=room.room_id, you=player.index, players=len(room.players))
        )

        if not room.started:
            await self._send(ws, msg("nj_waiting"))
            return

        if not room.started_match:
            self._start_match(room)
        await self._broadcast_state(room)

    def _start_match(self, room: NJRoom) -> None:
        room.match.start_new_match()
        room.match.apply_default_arrangement(0)
        room.match.apply_default_arrangement(1)
        room.started_match = True
        room.event_seq = 0
        room.last_event = None
        self._arm_arrange_timer(room)

    # ── 배치 단계 메시지 ─────────────────────────────────────────
    async def handle_arrange_move(self, room: NJRoom, ws: WebSocket, piece_id: int, col: int, row: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            side = player.index
            p = room.match.pieces.get(piece_id)
            if p is None or p["side"] != side or room.match.phase != ARRANGE:
                await self._send(ws, msg("error", message="invalid_arrange"))
                return
            prev = (p["col"], p["row"]) if p["col"] != -1 else None
            room.match.unplace_piece(side, piece_id)
            result = room.match.place_piece(side, piece_id, col, row)
            if not result["ok"] and prev is not None:
                room.match.place_piece(side, piece_id, prev[0], prev[1])
            if result["ok"] and room.match.ready_flags[side]:
                room.match.unmark_ready(side)
            await self._broadcast_state(room)

    async def handle_arrange_swap(self, room: NJRoom, ws: WebSocket, piece_id_a: int, piece_id_b: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            side = player.index
            result = room.match.swap_pieces(side, piece_id_a, piece_id_b)
            if result["ok"] and room.match.ready_flags[side]:
                room.match.unmark_ready(side)
            await self._broadcast_state(room)

    async def handle_arrange_reset(self, room: NJRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            side = player.index
            if room.match.phase == ARRANGE:
                room.match.apply_default_arrangement(side)
                if room.match.ready_flags[side]:
                    room.match.unmark_ready(side)
            await self._broadcast_state(room)

    async def handle_ready(self, room: NJRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            side = player.index
            result = room.match.mark_ready(side)
            if not result["ok"]:
                await self._send(ws, msg("error", message=result["error"]))
                return
            if room.match.both_ready():
                self._cancel_arrange_timer(room)
                room.match.start_move_phase(0)
                self._arm_move_timer(room)
            await self._broadcast_state(room)

    # ── 이동/대결/부활 메시지 ─────────────────────────────────────
    async def handle_move(self, room: NJRoom, ws: WebSocket, piece_id: int, col: int, row: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            result = room.match.move_piece(player.index, piece_id, col, row)
            if not result["ok"]:
                await self._send(ws, msg("error", message=result["error"]))
                return
            self._cancel_move_timer(room)
            self._after_action(room, result)
            await self._broadcast_state(room)

    async def handle_item(self, room: NJRoom, ws: WebSocket, item_type: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            declare = room.match.declare_item(player.index, item_type)
            if not declare["ok"]:
                await self._send(ws, msg("error", message=declare["error"]))
                return
            result = room.match.resolve_duels()
            self._register_event(room, result)
            self._after_action(room, result)
            await self._broadcast_state(room)

    async def handle_item_decline(self, room: NJRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            decline = room.match.decline_item(player.index)
            if not decline["ok"]:
                await self._send(ws, msg("error", message=decline["error"]))
                return
            result = room.match.resolve_duels()
            self._register_event(room, result)
            self._after_action(room, result)
            await self._broadcast_state(room)

    async def handle_revive(self, room: NJRoom, ws: WebSocket, revive_piece_id: int) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            result = room.match.perform_revive(player.index, revive_piece_id)
            if not result["ok"]:
                await self._send(ws, msg("error", message=result["error"]))
                return
            self._register_event(room, result)
            self._after_action(room, result)
            await self._broadcast_state(room)

    async def handle_decline_reward(self, room: NJRoom, ws: WebSocket) -> None:
        player = room.player_by_ws(ws)
        if player is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        async with self._lock:
            result = room.match.decline_reward(player.index)
            if not result["ok"]:
                await self._send(ws, msg("error", message=result["error"]))
                return
            self._after_action(room, result)
            await self._broadcast_state(room)

    async def handle_rematch(self, room: NJRoom, ws: WebSocket) -> None:
        if room.player_by_ws(ws) is None:
            await self._send(ws, msg("error", message="not_in_room"))
            return
        if not room.started:
            await self._send(ws, msg("error", message="waiting_for_opponent"))
            return
        async with self._lock:
            self._cancel_timers(room)
            room.segment += 1
            self._start_match(room)
            await self._broadcast_state(room)

    # ── 내부 헬퍼 ────────────────────────────────────────────────
    def _register_event(self, room: NJRoom, result: dict[str, Any]) -> None:
        if "duels" not in result:
            return
        room.event_seq += 1
        room.last_event = {
            "seq": room.event_seq,
            "reports": result["duels"],
            "hidden_ids": result.get("hidden_ids", []),
            "mover_side": result.get("mover_side", -1),
        }

    def _after_action(self, room: NJRoom, result: dict[str, Any]) -> None:
        """행동(이동/아이템/부활) 이후 다음 타이머를 정리한다."""
        if result.get("game_over"):
            self._cancel_timers(room)
            return
        if room.match.phase == MOVE:
            self._arm_move_timer(room)
        # AWAITING_ITEMS / AWAITING_REWARD 동안에는 타이머를 세우지 않는다
        # (로컬 모드도 해당 화면에서는 60초 카운트를 멈춘다).

    def _arm_arrange_timer(self, room: NJRoom) -> None:
        self._cancel_arrange_timer(room)
        loop = asyncio.get_running_loop()
        room.arrange_deadline = loop.time() + ARRANGE_SECONDS
        room._arrange_task = asyncio.create_task(self._arrange_timeout(room))

    def _cancel_arrange_timer(self, room: NJRoom) -> None:
        if room._arrange_task is not None and not room._arrange_task.done():
            room._arrange_task.cancel()
        room._arrange_task = None
        room.arrange_deadline = None

    def _arm_move_timer(self, room: NJRoom) -> None:
        self._cancel_move_timer(room)
        loop = asyncio.get_running_loop()
        room.move_deadline = loop.time() + MOVE_SECONDS
        room._move_task = asyncio.create_task(self._move_timeout(room))

    def _cancel_move_timer(self, room: NJRoom) -> None:
        if room._move_task is not None and not room._move_task.done():
            room._move_task.cancel()
        room._move_task = None
        room.move_deadline = None

    def _cancel_timers(self, room: NJRoom) -> None:
        self._cancel_arrange_timer(room)
        self._cancel_move_timer(room)

    async def _arrange_timeout(self, room: NJRoom) -> None:
        try:
            await asyncio.sleep(ARRANGE_SECONDS)
        except asyncio.CancelledError:
            return
        async with self._lock:
            if room.room_id not in self._rooms or room.match.phase != ARRANGE:
                return
            loser = 0 if not room.match.ready_flags[0] else 1
            room.match.force_arrange_timeout(loser)
            room.arrange_deadline = None
            room._arrange_task = None
            await self._broadcast_state(room)

    async def _move_timeout(self, room: NJRoom) -> None:
        try:
            await asyncio.sleep(MOVE_SECONDS)
        except asyncio.CancelledError:
            return
        async with self._lock:
            if room.room_id not in self._rooms or room.match.phase != MOVE:
                return
            room.match.force_move_timeout()
            room.move_deadline = None
            room._move_task = None
            await self._broadcast_state(room)

    def _state_for(self, room: NJRoom, idx: int) -> dict[str, Any]:
        match = room.match
        loop = asyncio.get_event_loop()
        now = loop.time()

        arrange_left = None
        if room.arrange_deadline is not None:
            arrange_left = max(0, int(room.arrange_deadline - now + 0.999))
        move_left = None
        if room.move_deadline is not None:
            move_left = max(0, int(room.move_deadline - now + 0.999))

        pending_item_side = match._pending_mover_side if match.phase == AWAITING_ITEMS else -1
        pending_reward_side = (
            match.pending_reward.get("side", -1) if match.phase == AWAITING_REWARD else -1
        )
        # 도달한 말은 항상 그 소유자(pending_reward_side) 본인의 말이므로,
        # 소유자 본인에게만 id를 공개해도 안전하다(상대에게는 -1).
        pending_reward_piece_id = (
            match.pending_reward.get("piece_id", -1) if pending_reward_side == idx else -1
        )

        event = None
        if room.last_event is not None:
            event = _redact_duel_event(match, room.last_event, idx)

        return msg(
            "nj_state",
            you=idx,
            segment=room.segment,
            phase=match.phase,
            current_turn=match.current_turn,
            my_ready=match.ready_flags[idx],
            opp_ready=match.ready_flags[1 - idx],
            winner=match.winner,
            win_reason=match.win_reason,
            pending_item_side=pending_item_side,
            pending_reward_side=pending_reward_side,
            pending_reward_piece_id=pending_reward_piece_id,
            arrange_seconds_left=arrange_left,
            move_seconds_left=move_left,
            board=_board_for(match, idx),
            graveyard_mine=_graveyard_for(match, idx, idx),
            graveyard_opp=_graveyard_for(match, 1 - idx, idx),
            used_items_mine=match.used_items[idx],
            event=event,
        )

    async def _broadcast_state(self, room: NJRoom) -> None:
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


nj_manager = NJRoomManager()
