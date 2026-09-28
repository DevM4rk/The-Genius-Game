"""베팅 가위바위보 — 손과 걸 칩을 동시에 내는 1:1 대결.

둘 다 낼 때까지 상대의 손과 칩은 보내지 않는다. 라운드가 끝나면 그 라운드의
손과 칩은 양쪽에 공개한다.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any

from .duel import parse_int

START_CHIPS = 10
MAX_ROUNDS = 10
HANDS = ("rock", "paper", "scissors")
BEATS = {"rock": "scissors", "paper": "rock", "scissors": "paper"}


@dataclass
class BettingRPSState:
    chips: list[int] = field(default_factory=lambda: [START_CHIPS, START_CHIPS])
    round_index: int = 0
    pending: list[dict[str, Any] | None] = field(default_factory=lambda: [None, None])
    last_result: dict[str, Any] | None = None
    history: list[dict[str, Any]] = field(default_factory=list)

    def is_over(self) -> bool:
        return self.round_index >= MAX_ROUNDS or min(self.chips) <= 0

    def winner(self) -> int:
        if self.chips[0] == self.chips[1]:
            return -1
        return 0 if self.chips[0] > self.chips[1] else 1


def rps_winner(hand0: str, hand1: str) -> int:
    if hand0 == hand1:
        return -1
    return 0 if BEATS[hand0] == hand1 else 1


class BettingRPSRules:
    game_id = "betting_rps"

    def new_state(self, rng: random.Random) -> BettingRPSState:
        return BettingRPSState()

    def apply(self, state: BettingRPSState, idx: int, action: dict[str, Any]) -> str | None:
        if state.is_over():
            return "game_already_over"
        if state.pending[idx] is not None:
            return "already_submitted"
        hand = action.get("hand")
        if hand not in HANDS:
            return "invalid_hand"
        bet = parse_int(action.get("bet"))
        if bet is None or bet < 1 or bet > state.chips[idx]:
            return "invalid_bet"

        state.pending[idx] = {"hand": hand, "bet": bet}
        if state.pending[0] is not None and state.pending[1] is not None:
            self._resolve(state)
        return None

    def _resolve(self, state: BettingRPSState) -> None:
        p0, p1 = state.pending
        assert p0 is not None and p1 is not None
        winner = rps_winner(p0["hand"], p1["hand"])
        if winner >= 0:
            loser = 1 - winner
            gain = (p0, p1)[loser]["bet"]
            state.chips[winner] += gain
            state.chips[loser] -= gain

        record = {
            "round": state.round_index,
            "hands": [p0["hand"], p1["hand"]],
            "bets": [p0["bet"], p1["bet"]],
            "winner": winner,
            "chips_after": list(state.chips),
        }
        state.history.append(record)
        state.last_result = record
        state.round_index += 1
        state.pending = [None, None]

    def view(self, state: BettingRPSState, idx: int) -> dict[str, Any]:
        opp = 1 - idx
        over = state.is_over()
        return {
            "round_index": state.round_index,
            "max_rounds": MAX_ROUNDS,
            "my_chips": state.chips[idx],
            "opp_chips": state.chips[opp],
            "my_submitted": state.pending[idx] is not None,
            "opp_submitted": state.pending[opp] is not None,
            "my_pending": state.pending[idx],
            "last_result": state.last_result,
            "history": list(state.history),
            "is_over": over,
            "winner": state.winner() if over else -1,
        }
