"""WebSocket gateway.

Protocol: see `shared/protocol/ws-message.schema.json`.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.config import settings
from app.core.security import decode_access_token
from app.services.matchmaking import MatchTicket, match_queue
from app.services.omok_rules import can_place, is_five, place
from app.services.room_manager import room_manager

logger = logging.getLogger(__name__)
websocket_router = APIRouter()


def _msg(msg_type: str, payload: Optional[dict[str, Any]] = None, request_id: Optional[str] = None) -> dict:
    out: dict[str, Any] = {"type": msg_type, "payload": payload or {}}
    if request_id:
        out["request_id"] = request_id
    return out


class ConnectionContext:
    def __init__(self, websocket: WebSocket) -> None:
        self.websocket = websocket
        self.user_id: Optional[str] = None
        self.display_name: Optional[str] = None
        self.elo: int = 1000
        self.room_id: Optional[str] = None
        self.role: Optional[str] = None  # player | spectator


@websocket_router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    ctx = ConnectionContext(websocket)
    try:
        while True:
            data = await websocket.receive_json()
            await _dispatch(ctx, data)
    except WebSocketDisconnect:
        await _on_disconnect(ctx)
    except Exception:
        logger.exception("websocket error user=%s", ctx.user_id)
        await websocket.close(code=1011)


async def _dispatch(ctx: ConnectionContext, data: dict[str, Any]) -> None:
    msg_type = data.get("type")
    payload = data.get("payload") or {}
    request_id = data.get("request_id")

    if msg_type == "ping":
        await ctx.websocket.send_json(_msg("pong", {}, request_id))
        return

    if msg_type == "auth.hello":
        await _handle_auth(ctx, payload, request_id)
        return

    if ctx.user_id is None:
        await ctx.websocket.send_json(_msg("auth.error", {"detail": "authenticate first"}, request_id))
        return

    handlers = {
        "match.enqueue": _handle_match_enqueue,
        "match.dequeue": _handle_match_dequeue,
        "room.create": _handle_room_create,
        "room.join": _handle_room_join,
        "spectator.join": _handle_spectator_join,
        "game.move": _handle_game_move,
        "game.resign": _handle_game_resign,
    }
    handler = handlers.get(msg_type)
    if handler is None:
        await ctx.websocket.send_json(
            _msg("room.error", {"detail": f"unknown type: {msg_type}"}, request_id)
        )
        return
    await handler(ctx, payload, request_id)


async def _handle_auth(ctx: ConnectionContext, payload: dict, request_id: Optional[str]) -> None:
    token = payload.get("token")
    claims = decode_access_token(token) if token else None
    if not claims:
        await ctx.websocket.send_json(_msg("auth.error", {"detail": "invalid token"}, request_id))
        return
    ctx.user_id = str(claims["sub"])
    ctx.display_name = str(claims.get("name") or ctx.user_id)
    ctx.elo = int(claims.get("elo") or 1000)
    await ctx.websocket.send_json(
        _msg(
            "auth.ok",
            {"user_id": ctx.user_id, "display_name": ctx.display_name, "elo": ctx.elo},
            request_id,
        )
    )


async def _handle_match_enqueue(ctx: ConnectionContext, payload: dict, request_id: Optional[str]) -> None:
    game = payload.get("game", "omok")
    match_queue.enqueue(
        MatchTicket(
            user_id=ctx.user_id or "",
            display_name=ctx.display_name or "",
            elo=ctx.elo,
            game=game,
        )
    )
    pair = match_queue.try_match(settings.match_elo_window)
    if pair is None:
        await ctx.websocket.send_json(
            _msg("match.status", {"queued": True, "queue_size": match_queue.size()}, request_id)
        )
        return

    a, b = pair
    room = await room_manager.create_room(game=game, mode="rank")
    # Seat assignment is completed when both clients call room.join.
    await ctx.websocket.send_json(
        _msg(
            "match.found",
            {
                "room_id": room.room_id,
                "join_path": f"/play/{room.room_id}",
                "players": [
                    {"user_id": a.user_id, "elo": a.elo},
                    {"user_id": b.user_id, "elo": b.elo},
                ],
            },
            request_id,
        )
    )
    # TODO Phase 3: push match.found to the other matched connection via connection hub.


async def _handle_match_dequeue(ctx: ConnectionContext, _payload: dict, request_id: Optional[str]) -> None:
    match_queue.dequeue(ctx.user_id or "")
    await ctx.websocket.send_json(_msg("match.status", {"queued": False}, request_id))


async def _handle_room_create(ctx: ConnectionContext, payload: dict, request_id: Optional[str]) -> None:
    game = payload.get("game", "omok")
    ruleset = payload.get("ruleset", "freestyle")
    room = await room_manager.create_room(game=game, mode="private", ruleset=ruleset)
    await ctx.websocket.send_json(
        _msg(
            "room.created",
            {"room_id": room.room_id, "join_path": f"/play/{room.room_id}", "game": game},
            request_id,
        )
    )


async def _handle_room_join(ctx: ConnectionContext, payload: dict, request_id: Optional[str]) -> None:
    room_id = payload.get("room_id")
    room = room_manager.get_room(room_id) if room_id else None
    if room is None:
        await ctx.websocket.send_json(_msg("room.error", {"detail": "room not found"}, request_id))
        return
    if len(room.players) >= 2 and ctx.user_id not in room.players:
        await ctx.websocket.send_json(
            _msg("room.error", {"detail": "room full — use spectator.join"}, request_id)
        )
        return

    from app.models.room import PlayerSeat

    stone = 1 if len(room.players) == 0 else 2
    if ctx.user_id not in room.players:
        room.players[ctx.user_id or ""] = PlayerSeat(
            user_id=ctx.user_id or "",
            display_name=ctx.display_name or "",
            stone=stone,
            elo=ctx.elo,
        )
    ctx.room_id = room.room_id
    ctx.role = "player"
    if len(room.players) == 2:
        room_manager.mark_playing(room.room_id)

    await ctx.websocket.send_json(
        _msg(
            "room.joined",
            {
                "room_id": room.room_id,
                "role": "player",
                "stone": room.players[ctx.user_id or ""].stone,
                "status": room.status.value,
                "players": [
                    {"user_id": p.user_id, "name": p.display_name, "stone": p.stone}
                    for p in room.players.values()
                ],
            },
            request_id,
        )
    )


async def _handle_spectator_join(ctx: ConnectionContext, payload: dict, request_id: Optional[str]) -> None:
    room_id = payload.get("room_id")
    room = room_manager.get_room(room_id) if room_id else None
    if room is None:
        await ctx.websocket.send_json(_msg("room.error", {"detail": "room not found"}, request_id))
        return
    room.spectators.add(ctx.user_id or "")
    ctx.room_id = room.room_id
    ctx.role = "spectator"
    await ctx.websocket.send_json(
        _msg(
            "spectator.joined",
            {"room_id": room.room_id, "role": "spectator", "board": room.board, "turn": room.turn},
            request_id,
        )
    )


async def _handle_game_move(ctx: ConnectionContext, payload: dict, request_id: Optional[str]) -> None:
    if ctx.role != "player" or not ctx.room_id:
        await ctx.websocket.send_json(_msg("room.error", {"detail": "not a player in a room"}, request_id))
        return
    room = room_manager.get_room(ctx.room_id)
    if room is None:
        await ctx.websocket.send_json(_msg("room.error", {"detail": "room missing"}, request_id))
        return

    seat = room.players.get(ctx.user_id or "")
    if seat is None or seat.stone != room.turn:
        await ctx.websocket.send_json(_msg("room.error", {"detail": "not your turn"}, request_id))
        return

    x, y = int(payload.get("x", -1)), int(payload.get("y", -1))
    if not can_place(room.board, x, y):
        await ctx.websocket.send_json(_msg("room.error", {"detail": "illegal move"}, request_id))
        return

    place(room.board, x, y, seat.stone)
    await ctx.websocket.send_json(
        _msg(
            "game.moved",
            {"x": x, "y": y, "stone": seat.stone, "turn_seconds": settings.turn_seconds},
            request_id,
        )
    )
    # TODO Phase 2: broadcast to opponent + spectators via connection hub; start 30s timer.

    if is_five(room.board, x, y, seat.stone):
        from app.models.room import RoomStatus

        room.status = RoomStatus.FINISHED
        await ctx.websocket.send_json(
            _msg(
                "game.over",
                {"game": "omok", "reason": "five_in_a_row", "winner": seat.stone},
                request_id,
            )
        )
        return

    room.turn = 2 if room.turn == 1 else 1


async def _handle_game_resign(ctx: ConnectionContext, _payload: dict, request_id: Optional[str]) -> None:
    if ctx.role != "player" or not ctx.room_id:
        return
    room = room_manager.get_room(ctx.room_id)
    if room is None:
        return
    seat = room.players.get(ctx.user_id or "")
    if seat is None:
        return
    from app.models.room import RoomStatus

    room.status = RoomStatus.FINISHED
    winner = 2 if seat.stone == 1 else 1
    await ctx.websocket.send_json(
        _msg("game.over", {"game": "omok", "reason": "resign", "winner": winner}, request_id)
    )


async def _on_disconnect(ctx: ConnectionContext) -> None:
    if ctx.user_id:
        match_queue.dequeue(ctx.user_id)
    logger.info("disconnect user=%s room=%s", ctx.user_id, ctx.room_id)
