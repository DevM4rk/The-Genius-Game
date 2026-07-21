"""Shared WebSocket protocol models.

These mirror `shared/protocol/*.schema.json` so backend and (later) codegen
clients stay aligned. Godot will serialize the same JSON shapes.
"""

from __future__ import annotations

from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class MessageType(str, Enum):
    AUTH_HELLO = "auth.hello"
    AUTH_OK = "auth.ok"
    AUTH_ERROR = "auth.error"
    MATCH_ENQUEUE = "match.enqueue"
    MATCH_DEQUEUE = "match.dequeue"
    MATCH_FOUND = "match.found"
    MATCH_STATUS = "match.status"
    ROOM_CREATE = "room.create"
    ROOM_CREATED = "room.created"
    ROOM_JOIN = "room.join"
    ROOM_JOINED = "room.joined"
    ROOM_LEAVE = "room.leave"
    ROOM_STATE = "room.state"
    ROOM_ERROR = "room.error"
    GAME_MOVE = "game.move"
    GAME_MOVED = "game.moved"
    GAME_RESIGN = "game.resign"
    GAME_TIMEOUT = "game.timeout"
    GAME_OVER = "game.over"
    SPECTATOR_JOIN = "spectator.join"
    SPECTATOR_JOINED = "spectator.joined"
    PING = "ping"
    PONG = "pong"


class WsEnvelope(BaseModel):
    type: MessageType
    request_id: Optional[str] = None
    payload: dict[str, Any] = Field(default_factory=dict)


class GameId(str, Enum):
    OMOK = "omok"


class PlayMode(str, Enum):
    PRIVATE = "private"
    RANK = "rank"
    AI = "ai"  # client-only; never sent to server


class Stone(int, Enum):
    EMPTY = 0
    BLACK = 1
    WHITE = 2


class OmokMovePayload(BaseModel):
    game: Literal["omok"] = "omok"
    x: int = Field(ge=0, le=14)
    y: int = Field(ge=0, le=14)


class OmokRoomCreatePayload(BaseModel):
    game: Literal["omok"] = "omok"
    mode: PlayMode
    ruleset: Literal["freestyle", "renju"] = "freestyle"


class OmokGameOverPayload(BaseModel):
    game: Literal["omok"] = "omok"
    reason: Literal["five_in_a_row", "resign", "timeout", "draw", "illegal"]
    winner: Optional[Stone] = None


TURN_SECONDS = 30
BOARD_SIZE = 15
