from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class RoomStatus(str, Enum):
    WAITING = "waiting"
    PLAYING = "playing"
    FINISHED = "finished"


@dataclass
class PlayerSeat:
    user_id: str
    display_name: str
    stone: int  # 1=black, 2=white
    elo: int = 1000


@dataclass
class Room:
    room_id: str
    game: str
    mode: str  # private | rank
    ruleset: str = "freestyle"
    status: RoomStatus = RoomStatus.WAITING
    players: dict[str, PlayerSeat] = field(default_factory=dict)
    spectators: set[str] = field(default_factory=set)
    # Flat 15x15 board; 0 empty / 1 black / 2 white. Filled in Phase 2.
    board: list[int] = field(default_factory=lambda: [0] * 225)
    turn: int = 1
    turn_deadline_ts: Optional[float] = None
