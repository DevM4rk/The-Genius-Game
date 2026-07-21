"""Rank matchmaking queue stub.

Phase 3: replace in-memory deque with Redis ZSET keyed by Elo.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from typing import Optional


@dataclass
class MatchTicket:
    user_id: str
    display_name: str
    elo: int
    game: str = "omok"


class MatchQueue:
    def __init__(self) -> None:
        self._queue: deque[MatchTicket] = deque()

    def enqueue(self, ticket: MatchTicket) -> None:
        self._queue = deque(t for t in self._queue if t.user_id != ticket.user_id)
        self._queue.append(ticket)

    def dequeue(self, user_id: str) -> None:
        self._queue = deque(t for t in self._queue if t.user_id != user_id)

    def try_match(self, elo_window: int = 150) -> Optional[tuple[MatchTicket, MatchTicket]]:
        if len(self._queue) < 2:
            return None
        for i, a in enumerate(self._queue):
            for j in range(i + 1, len(self._queue)):
                b = self._queue[j]
                if a.game != b.game:
                    continue
                if abs(a.elo - b.elo) <= elo_window:
                    # remove both
                    self._queue = deque(
                        t for k, t in enumerate(self._queue) if k not in (i, j)
                    )
                    return a, b
        return None

    def size(self) -> int:
        return len(self._queue)


match_queue = MatchQueue()
