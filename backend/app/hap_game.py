"""결! 합! — 공개된 그림 9장에서 "합"을 먼저 찾는 1:1 경쟁.

그림은 도형, 도형 색, 배경색 세 가지 속성을 갖고, 각 속성은 세 종류다.
세 장이 모든 속성에서 "전부 같거나 전부 다르면" 합이다.

- 합!: 아직 불리지 않은 합 3장을 부르면 +1, 틀리거나 이미 불린 합이면 -1.
- 결!: 남은 합이 없을 때 부르면 +3이고 게임이 끝난다. 남은 합이 있으면 -1.

모든 정보가 공개된 게임이라 숨길 정보는 없다. 남은 합의 개수만 보내지 않는다.
"""

from __future__ import annotations

import itertools
import random
from dataclasses import dataclass, field
from typing import Any

from .duel import parse_int

SHAPES = ("circle", "triangle", "square")
SHAPE_COLORS = ("red", "blue", "yellow")
BACKGROUNDS = ("black", "gray", "white")
BOARD_SIZE = 9
MIN_HAPS = 3
HAP_POINTS = 1
GYEOL_POINTS = 3
WRONG_PENALTY = 1

Card = tuple[int, int, int]


def is_hap(cards: list[Card]) -> bool:
    return all(len({c[attr] for c in cards}) in (1, 3) for attr in range(3))


def all_haps(board: list[Card]) -> set[tuple[int, int, int]]:
    return {
        combo
        for combo in itertools.combinations(range(len(board)), 3)
        if is_hap([board[i] for i in combo])
    }


def make_board(rng: random.Random) -> list[Card]:
    deck: list[Card] = list(itertools.product(range(3), range(3), range(3)))
    while True:
        board = rng.sample(deck, BOARD_SIZE)
        if len(all_haps(board)) >= MIN_HAPS:
            return board


@dataclass
class HapState:
    board: list[Card]
    scores: list[int] = field(default_factory=lambda: [0, 0])
    found: list[dict[str, Any]] = field(default_factory=list)
    over: bool = False
    last_event: dict[str, Any] | None = None
    event_seq: int = 0

    def found_combos(self) -> set[tuple[int, ...]]:
        return {tuple(f["cards"]) for f in self.found}

    def winner(self) -> int:
        if self.scores[0] == self.scores[1]:
            return -1
        return 0 if self.scores[0] > self.scores[1] else 1


class HapRules:
    game_id = "hap_game"

    def new_state(self, rng: random.Random) -> HapState:
        return HapState(board=make_board(rng))

    def apply(self, state: HapState, idx: int, action: dict[str, Any]) -> str | None:
        if state.over:
            return "game_already_over"
        kind = action.get("kind")
        if kind == "hap":
            return self._call_hap(state, idx, action.get("cards"))
        if kind == "gyeol":
            self._call_gyeol(state, idx)
            return None
        return "invalid_action"

    def _call_hap(self, state: HapState, idx: int, raw: Any) -> str | None:
        if not isinstance(raw, list) or len(raw) != 3:
            return "invalid_cards"
        picks = [parse_int(v) for v in raw]
        if any(p is None or p < 0 or p >= BOARD_SIZE for p in picks) or len(set(picks)) != 3:
            return "invalid_cards"
        combo = tuple(sorted(int(p) for p in picks))  # type: ignore[arg-type]

        if combo in state.found_combos():
            ok, reason = False, "already_found"
        elif not is_hap([state.board[i] for i in combo]):
            ok, reason = False, "not_hap"
        else:
            ok, reason = True, ""

        if ok:
            state.scores[idx] += HAP_POINTS
            state.found.append({"cards": list(combo), "by": idx})
        else:
            state.scores[idx] -= WRONG_PENALTY
        self._event(state, {"kind": "hap", "by": idx, "cards": list(combo), "ok": ok, "reason": reason})
        return None

    def _call_gyeol(self, state: HapState, idx: int) -> None:
        remaining = all_haps(state.board) - state.found_combos()
        ok = not remaining
        if ok:
            state.scores[idx] += GYEOL_POINTS
            state.over = True
        else:
            state.scores[idx] -= WRONG_PENALTY
        self._event(state, {"kind": "gyeol", "by": idx, "ok": ok})

    @staticmethod
    def _event(state: HapState, event: dict[str, Any]) -> None:
        state.event_seq += 1
        state.last_event = event

    def view(self, state: HapState, idx: int) -> dict[str, Any]:
        opp = 1 - idx
        return {
            "board": [
                {"shape": SHAPES[s], "color": SHAPE_COLORS[c], "bg": BACKGROUNDS[b]}
                for s, c, b in state.board
            ],
            "my_score": state.scores[idx],
            "opp_score": state.scores[opp],
            "found": list(state.found),
            "last_event": state.last_event,
            "event_seq": state.event_seq,
            "is_over": state.over,
            "winner": state.winner() if state.over else -1,
        }
