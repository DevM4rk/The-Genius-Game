"""칩 포커 대결 — 매 라운드 카드 한 장씩 받고 칩을 동시에 거는 1:1 게임.

게임마다 덱 구성, 카드 세기, 라운드 중에 각자 볼 수 있는 면만 다르다.
라운드 중에는 각자 볼 수 있는 정보만 보내고, 라운드가 끝나면 두 카드를 공개한다.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any

from .duel import parse_int

START_CHIPS = 20
MAX_ROUNDS = 10


@dataclass
class PokerState:
    deck: list[Any]
    cards: list[Any] = field(default_factory=lambda: [None, None])
    chips: list[int] = field(default_factory=lambda: [START_CHIPS, START_CHIPS])
    round_index: int = 0
    pending: list[int | None] = field(default_factory=lambda: [None, None])
    last_result: dict[str, Any] | None = None
    history: list[dict[str, Any]] = field(default_factory=list)

    def is_over(self) -> bool:
        return self.round_index >= MAX_ROUNDS or min(self.chips) <= 0

    def winner(self) -> int:
        if self.chips[0] == self.chips[1]:
            return -1
        return 0 if self.chips[0] > self.chips[1] else 1


class ChipPokerRules:
    game_id = ""

    def make_deck(self, rng: random.Random) -> list[Any]:
        raise NotImplementedError

    def strength(self, card: Any) -> int:
        raise NotImplementedError

    def visible(self, state: PokerState, idx: int) -> dict[str, Any]:
        """라운드 중 idx가 볼 수 있는 카드 정보."""
        raise NotImplementedError

    def new_state(self, rng: random.Random) -> PokerState:
        deck = self.make_deck(rng)
        rng.shuffle(deck)
        state = PokerState(deck=deck)
        self._deal(state)
        return state

    @staticmethod
    def _deal(state: PokerState) -> None:
        state.cards = [state.deck.pop(), state.deck.pop()]

    def apply(self, state: PokerState, idx: int, action: dict[str, Any]) -> str | None:
        if state.is_over():
            return "game_already_over"
        if state.pending[idx] is not None:
            return "already_submitted"
        bet = parse_int(action.get("bet"))
        if bet is None or bet < 1 or bet > state.chips[idx]:
            return "invalid_bet"

        state.pending[idx] = bet
        if state.pending[0] is not None and state.pending[1] is not None:
            self._resolve(state)
        return None

    def _resolve(self, state: PokerState) -> None:
        bets = [int(b) for b in state.pending]  # type: ignore[arg-type]
        strengths = [self.strength(c) for c in state.cards]
        winner = -1
        if strengths[0] != strengths[1]:
            winner = 0 if strengths[0] > strengths[1] else 1
        if winner >= 0:
            loser = 1 - winner
            state.chips[winner] += bets[loser]
            state.chips[loser] -= bets[loser]

        record = {
            "round": state.round_index,
            "cards": list(state.cards),
            "strengths": strengths,
            "bets": bets,
            "winner": winner,
            "chips_after": list(state.chips),
        }
        state.history.append(record)
        state.last_result = record
        state.round_index += 1
        state.pending = [None, None]
        if not state.is_over():
            self._deal(state)

    def view(self, state: PokerState, idx: int) -> dict[str, Any]:
        opp = 1 - idx
        over = state.is_over()
        return {
            "round_index": state.round_index,
            "max_rounds": MAX_ROUNDS,
            "my_chips": state.chips[idx],
            "opp_chips": state.chips[opp],
            "my_submitted": state.pending[idx] is not None,
            "opp_submitted": state.pending[opp] is not None,
            "my_pending_bet": state.pending[idx],
            "cards": None if over else self.visible(state, idx),
            "last_result": state.last_result,
            "history": list(state.history),
            "is_over": over,
            "winner": state.winner() if over else -1,
        }


class IndianPokerRules(ChipPokerRules):
    """1~10 두 벌. 상대 카드만 보이고 내 카드는 라운드가 끝나야 보인다."""

    game_id = "indian_poker"

    def make_deck(self, rng: random.Random) -> list[Any]:
        return list(range(1, 11)) * 2

    def strength(self, card: Any) -> int:
        return int(card)

    def visible(self, state: PokerState, idx: int) -> dict[str, Any]:
        return {"opp_card": state.cards[1 - idx]}
