"""인디언 홀덤 — 이마 카드 1장 + 공개 카드 2장으로 족보를 만드는 1:1 베팅.

각자 받은 카드는 상대에게만 보이고, 공개 카드 2장은 둘 다 본다. 내 카드는
라운드가 끝나야 공개된다. 베팅은 번갈아 체크/콜, 레이즈, 다이 중 하나를 한다.

족보(높은 순): 트리플 > 스트레이트(연속 세 수) > 페어 > 하이카드.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any

from .duel import parse_int

START_CHIPS = 30
ANTE = 1
MAX_ROUNDS = 10
DECK = list(range(1, 11)) * 4
HAND_NAMES = {3: "트리플", 2: "스트레이트", 1: "페어", 0: "하이카드"}


def hand_rank(cards: list[int]) -> tuple[int, ...]:
    s = sorted(cards, reverse=True)
    if s[0] == s[2]:
        return (3, s[0])
    if s[0] - s[1] == 1 and s[1] - s[2] == 1:
        return (2, s[0])
    if s[0] == s[1]:
        return (1, s[0], s[2])
    if s[1] == s[2]:
        return (1, s[1], s[0])
    return (0, *s)


@dataclass
class HoldemState:
    deck: list[int]
    stacks: list[int] = field(default_factory=lambda: [START_CHIPS, START_CHIPS])
    contrib: list[int] = field(default_factory=lambda: [0, 0])
    private: list[int] = field(default_factory=lambda: [0, 0])
    community: list[int] = field(default_factory=list)
    round_index: int = 0
    starter: int = 0
    to_act: int = 0
    checked: bool = False
    over: bool = False
    actions: list[dict[str, Any]] = field(default_factory=list)
    last_result: dict[str, Any] | None = None
    history: list[dict[str, Any]] = field(default_factory=list)

    def total(self, idx: int) -> int:
        return self.stacks[idx] + self.contrib[idx]

    def winner(self) -> int:
        if self.stacks[0] == self.stacks[1]:
            return -1
        return 0 if self.stacks[0] > self.stacks[1] else 1


class IndianHoldemRules:
    game_id = "indian_holdem"

    def new_state(self, rng: random.Random) -> HoldemState:
        deck = list(DECK)
        rng.shuffle(deck)
        state = HoldemState(deck=deck, starter=rng.randint(0, 1))
        self._start_round(state)
        return state

    def _start_round(self, state: HoldemState) -> None:
        if state.round_index >= MAX_ROUNDS or min(state.stacks) < ANTE or len(state.deck) < 4:
            state.over = True
            return
        state.private = [state.deck.pop(), state.deck.pop()]
        state.community = [state.deck.pop(), state.deck.pop()]
        state.stacks = [s - ANTE for s in state.stacks]
        state.contrib = [ANTE, ANTE]
        state.to_act = state.starter
        state.checked = False
        state.actions = []

    def max_raise(self, state: HoldemState, idx: int) -> int:
        opp = 1 - idx
        to_call = state.contrib[opp] - state.contrib[idx]
        return max(0, min(state.stacks[idx] - to_call, state.stacks[opp]))

    def apply(self, state: HoldemState, idx: int, action: dict[str, Any]) -> str | None:
        if state.over:
            return "game_already_over"
        if idx != state.to_act:
            return "not_your_turn"

        opp = 1 - idx
        kind = action.get("kind")
        to_call = state.contrib[opp] - state.contrib[idx]

        if kind == "fold":
            state.actions.append({"by": idx, "kind": "fold"})
            self._finish(state, winner=opp, reason="fold")
            return None

        if kind == "call":
            if to_call > 0:
                state.stacks[idx] -= to_call
                state.contrib[idx] += to_call
                state.actions.append({"by": idx, "kind": "call", "amount": to_call})
                self._showdown(state)
                return None
            state.actions.append({"by": idx, "kind": "check"})
            if state.checked:
                self._showdown(state)
            else:
                state.checked = True
                state.to_act = opp
            return None

        if kind == "raise":
            amount = parse_int(action.get("amount"))
            if amount is None or amount < 1 or amount > self.max_raise(state, idx):
                return "invalid_bet"
            pay = to_call + amount
            state.stacks[idx] -= pay
            state.contrib[idx] += pay
            state.actions.append({"by": idx, "kind": "raise", "amount": amount})
            state.checked = False
            state.to_act = opp
            return None

        return "invalid_action"

    def _showdown(self, state: HoldemState) -> None:
        ranks = [hand_rank([state.private[i], *state.community]) for i in (0, 1)]
        if ranks[0] == ranks[1]:
            self._finish(state, winner=-1, reason="showdown", ranks=ranks)
        else:
            self._finish(state, winner=0 if ranks[0] > ranks[1] else 1, reason="showdown", ranks=ranks)

    def _finish(
        self,
        state: HoldemState,
        winner: int,
        reason: str,
        ranks: list[tuple[int, ...]] | None = None,
    ) -> None:
        pot = sum(state.contrib)
        if winner < 0:
            for i in (0, 1):
                state.stacks[i] += state.contrib[i]
        else:
            state.stacks[winner] += pot

        record = {
            "round": state.round_index,
            "private": list(state.private),
            "community": list(state.community),
            "contrib": list(state.contrib),
            "winner": winner,
            "reason": reason,
            "hands": [HAND_NAMES[r[0]] for r in ranks] if ranks else None,
            "actions": list(state.actions),
            "stacks_after": list(state.stacks),
        }
        state.history.append(record)
        state.last_result = record
        state.contrib = [0, 0]
        state.round_index += 1
        state.starter = 1 - state.starter
        self._start_round(state)

    def view(self, state: HoldemState, idx: int) -> dict[str, Any]:
        opp = 1 - idx
        my_turn = not state.over and state.to_act == idx
        to_call = state.contrib[opp] - state.contrib[idx]
        return {
            "round_index": state.round_index,
            "max_rounds": MAX_ROUNDS,
            "my_stack": state.stacks[idx],
            "opp_stack": state.stacks[opp],
            "my_contrib": state.contrib[idx],
            "opp_contrib": state.contrib[opp],
            "opp_card": None if state.over else state.private[opp],
            "community": [] if state.over else list(state.community),
            "starter": state.starter,
            "my_turn": my_turn,
            "to_call": max(0, to_call) if my_turn else 0,
            "max_raise": self.max_raise(state, idx) if my_turn else 0,
            "actions": list(state.actions),
            "last_result": state.last_result,
            "history": list(state.history),
            "is_over": state.over,
            "winner": state.winner() if state.over else -1,
        }
