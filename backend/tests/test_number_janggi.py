"""숫자장기 서버 엔진 + 온라인 방(숨김정보) 테스트."""

from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.testclient import WebSocketTestSession

from app import number_janggi_match as M
from app import number_janggi_rules as R
from app.main import app
from app.number_janggi import _board_for, _graveyard_for, _redact_duel_event


def _drain_until(ws: WebSocketTestSession, target_type: str, limit: int = 20) -> list[dict]:
    messages: list[dict] = []
    for _ in range(limit):
        m = ws.receive_json()
        messages.append(m)
        if m["type"] == target_type:
            return messages
    raise AssertionError(f"{target_type} not received, got: {messages}")


# ── 순수 엔진 로직 ────────────────────────────────────────────────
def _fresh_ready_match() -> M.NumberJanggiMatch:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    match.apply_default_arrangement(0)
    match.apply_default_arrangement(1)
    assert match.mark_ready(0)["ok"]
    assert match.mark_ready(1)["ok"]
    assert match.both_ready()
    assert match.start_move_phase(0)["ok"]
    return match


def test_default_arrangement_places_all_14_pieces() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    match.apply_default_arrangement(0)
    match.apply_default_arrangement(1)
    assert match.is_arrangement_complete(0)
    assert match.is_arrangement_complete(1)
    for side in (0, 1):
        for pid in match.side_piece_ids(side):
            p = match.pieces[pid]
            assert R.is_own_camp(p["col"], p["row"], side)


def test_swap_pieces_keeps_positions_consistent() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    match.apply_default_arrangement(0)
    a = match.find_piece_id(0, R.NUMBER, 1)
    b = match.find_piece_id(0, R.NUMBER, 2)
    a_pos = (match.pieces[a]["col"], match.pieces[a]["row"])
    b_pos = (match.pieces[b]["col"], match.pieces[b]["row"])
    assert match.swap_pieces(0, a, b)["ok"]
    assert (match.pieces[a]["col"], match.pieces[a]["row"]) == b_pos
    assert (match.pieces[b]["col"], match.pieces[b]["row"]) == a_pos


def test_plus_duel_higher_wins_over_10() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 9)
    b = match.find_piece_id(1, R.NUMBER, 2)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    result = match._begin_combat_or_finish(0, a)
    assert result["ok"] and result["pending_duels"]
    assert match.decline_item(0)["ok"]
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["kind"] == "number"
    assert resolved["duels"][0]["score"] == 11
    # 9+2=11 >= 10 -> 더 높은 숫자(9)가 승리
    assert match.pieces[a]["alive"]
    assert not match.pieces[b]["alive"]


def test_minus_duel_lower_wins_under_10() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 9)
    b = match.find_piece_id(1, R.NUMBER, 2)
    # col 1<->2 경계가 마이너스 줄
    match.pieces[a].update(col=1, row=5)
    match.board[5][1] = a
    match.pieces[b].update(col=2, row=5)
    match.board[5][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    result = match._begin_combat_or_finish(0, a)
    assert result["pending_duels"][0]["is_minus"]
    assert match.decline_item(0)["ok"]
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["score"] == 7  # |9-2|
    # 9-2=7 < 10 -> 작은 수(2)가 이김 -> a(9) 제거
    assert not match.pieces[a]["alive"]
    assert match.pieces[b]["alive"]


def test_tie_removes_both() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 5)
    b = match.find_piece_id(1, R.NUMBER, 5)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    match.decline_item(0)
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["kind"] == "tie"
    assert not match.pieces[a]["alive"] and not match.pieces[b]["alive"]


def test_mine_destroys_both() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 3)
    b = match.find_piece_id(1, R.MINE)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    match.decline_item(0)
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["kind"] == "mine"
    assert not match.pieces[a]["alive"] and not match.pieces[b]["alive"]


def test_king_vs_nonking_removes_only_king() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.KING)
    b = match.find_piece_id(1, R.NUMBER, 1)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    match.decline_item(0)
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["kind"] == "king"
    assert not match.pieces[a]["alive"]
    assert match.pieces[b]["alive"]
    assert resolved.get("game_over")
    assert resolved["winner"] == 1


def test_king_vs_king_is_noop() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.KING)
    b = match.find_piece_id(1, R.KING)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    match.decline_item(0)
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["kind"] == "king_vs_king"
    assert match.pieces[a]["alive"] and match.pieces[b]["alive"]


def test_blind_item_hides_value_and_masks_score_for_opponent() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 9)
    b = match.find_piece_id(1, R.NUMBER, 2)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    assert match.declare_item(0, M.BLIND)["ok"]
    resolved = match.resolve_duels()

    event = {"seq": 1, "reports": resolved["duels"], "hidden_ids": resolved["hidden_ids"], "mover_side": 0}
    assert resolved["hidden_ids"] == [a]

    # 이긴 쪽(측)의 시점 — mover(0)은 자기 말이니 항상 값이 보임
    mover_view = _redact_duel_event(match, event, 0)
    assert mover_view["reports"][0]["a"]["masked"] is False
    assert mover_view["reports"][0]["a"]["value"] == 9

    # 상대(1) 시점 — 블라인드 걸린 mover 쪽 말(a)의 정체/값/합 점수가 가려져야 함
    opp_view = _redact_duel_event(match, event, 1)
    a_entry = opp_view["reports"][0]["a"]
    assert a_entry["masked"] is True
    assert "value" not in a_entry and "type" not in a_entry and "id" not in a_entry
    assert opp_view["reports"][0]["score"] is None
    # 결과(제거 여부)는 "결과만 공개" 규칙에 따라 여전히 보여야 한다.
    # 9+2=11 >= 10 -> 더 높은 숫자(블라인드 걸린 9)가 승리 -> 상대(2)가 제거됨
    assert opp_view["reports"][0]["a"]["removed"] is False
    assert opp_view["reports"][0]["b"]["removed"] is True


def test_plus_one_and_minus_one_change_effective_value() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 4)
    b = match.find_piece_id(1, R.NUMBER, 5)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    assert match.declare_item(0, M.PLUS_ONE)["ok"]  # 4 -> 5, 5+5=10 -> 큰 수(동점? no 같음) tie 아님, 4->5 이제 동점(5,5) -> tie
    resolved = match.resolve_duels()
    assert resolved["duels"][0]["kind"] == "tie"
    assert not match.pieces[a]["alive"] and not match.pieces[b]["alive"]


def test_win_by_capturing_all_non_king() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    for pid in list(match.pieces.keys()):
        p = match.pieces[pid]
        if p["side"] == 1 and p["type"] != R.KING:
            p["alive"] = False
    win = match.check_win()
    assert win["over"] and win["winner"] == 0 and win["reason"] == "all_non_king_captured"


def test_revive_from_graveyard_places_on_back_row() -> None:
    match = _fresh_ready_match()
    dead = match.find_piece_id(0, R.NUMBER, 1)
    match._remove_piece(dead)
    assert dead in match.graveyard_of(0)

    arrived = match.find_piece_id(0, R.NUMBER, 2)
    match.pending_reward = {}
    match.phase = M.AWAITING_REWARD
    match.pending_reward = {"side": 0, "piece_id": arrived}
    # 도착한 말은 이번 도달로 보드에서 사라질 예정이므로 임시로 보드에 둔 상태를 유지
    result = match.perform_revive(0, dead)
    assert result["ok"]
    assert match.pieces[dead]["alive"]
    assert match.pieces[dead]["revealed"]
    assert match.pieces[dead]["row"] == R.own_back_row(0)


def test_force_move_timeout_ends_game() -> None:
    match = _fresh_ready_match()
    result = match.force_move_timeout()
    assert result["ok"]
    assert match.phase == M.GAME_OVER
    assert match.winner == 1  # current_turn(0)이 시간초과 -> 상대(1) 승


def test_force_arrange_timeout_ends_game() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    result = match.force_arrange_timeout(0)
    assert result["ok"]
    assert match.winner == 1


# ── 뷰어별 정보 가림(board/graveyard) ────────────────────────────
def test_board_for_hides_opponent_identity_but_shows_own() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    match.apply_default_arrangement(0)
    match.apply_default_arrangement(1)

    board0 = _board_for(match, 0)
    board1 = _board_for(match, 1)

    for row_cells in board0:
        for cell in row_cells:
            if cell is None:
                continue
            if cell["side"] == 0:
                assert "type" in cell and "value" in cell
            else:
                assert "type" not in cell and "value" not in cell and "id" not in cell

    for row_cells in board1:
        for cell in row_cells:
            if cell is None:
                continue
            if cell["side"] == 1:
                assert "type" in cell and "value" in cell
            else:
                assert "type" not in cell and "value" not in cell and "id" not in cell


def test_graveyard_for_hides_unrevealed_opponent_pieces() -> None:
    match = M.NumberJanggiMatch()
    match.start_new_match()
    dead = match.find_piece_id(1, R.NUMBER, 7)
    match.pieces[dead]["revealed"] = False
    match.graveyard[1].append(dead)

    grave_as_opponent = _graveyard_for(match, 1, 0)  # side1 무덤을, side0 시점으로
    assert grave_as_opponent[0].get("type") is None and "value" not in grave_as_opponent[0]

    grave_as_owner = _graveyard_for(match, 1, 1)  # side1 무덤을, side1(본인) 시점으로
    assert grave_as_owner[0]["type"] == R.NUMBER and grave_as_owner[0]["value"] == 7


def test_duel_event_reveals_survivor_that_board_snapshot_still_hides() -> None:
    """대결에서 살아남은 상대 말은 로그에는 정체가 뜨지만 판에서는 계속 뒤집혀 있다.

    로컬 규칙과 같다 — 한 번 본 말을 기억하는 것이 게임의 일부라서, 판 위의 말은
    다시 덮인다. 즉 대결 로그의 id가 보드 스냅샷에는 없을 수 있고, 클라이언트는
    그 id를 보드에서 찾을 수 있다고 가정하면 안 된다.
    """
    match = M.NumberJanggiMatch()
    match.start_new_match()
    a = match.find_piece_id(0, R.NUMBER, 9)
    b = match.find_piece_id(1, R.NUMBER, 2)
    match.pieces[a].update(col=2, row=5)
    match.board[5][2] = a
    match.pieces[b].update(col=2, row=4)
    match.board[4][2] = b
    match.phase = M.MOVE
    match.current_turn = 0
    match._begin_combat_or_finish(0, a)
    assert match.decline_item(0)["ok"]
    resolved = match.resolve_duels()

    # 9+2=11 >= 10 -> 9(side0)가 이기고 살아남는다.
    assert match.pieces[a]["alive"] and not match.pieces[b]["alive"]
    assert match.pieces[a]["revealed"] is False

    event = {"seq": 1, "reports": resolved["duels"], "hidden_ids": [], "mover_side": 0}
    defender_view = _redact_duel_event(match, event, 1)
    a_entry = defender_view["reports"][0]["a"]
    # 블라인드가 없었으니 대결 로그에는 정체가 공개된다.
    assert a_entry["masked"] is False
    assert a_entry["id"] == a and a_entry["base_value"] == 9

    # 그런데 같은 말이 보드 스냅샷에서는 여전히 가려져 있다(id 없음).
    board_cell = _board_for(match, 1)[5][2]
    assert board_cell is not None
    assert "id" not in board_cell and "value" not in board_cell


# ── 온라인(빠른매칭) 통합 흐름 ─────────────────────────────────────
def test_quick_match_number_janggi_full_arrange_and_move_flow() -> None:
    client = TestClient(app)

    with client.websocket_connect("/ws/quick?game=number_janggi") as ws_a:
        assert ws_a.receive_json()["type"] == "queued"

        with client.websocket_connect("/ws/quick?game=number_janggi") as ws_b:
            msgs_a = _drain_until(ws_a, "nj_state")
            msgs_b = _drain_until(ws_b, "nj_state")

            matched_a = next(m for m in msgs_a if m["type"] == "matched")
            matched_b = next(m for m in msgs_b if m["type"] == "matched")
            assert matched_a["room_id"] == matched_b["room_id"]
            assert matched_a["game_id"] == "number_janggi"

            joined_a = next(m for m in msgs_a if m["type"] == "nj_joined")
            joined_b = next(m for m in msgs_b if m["type"] == "nj_joined")
            you_a, you_b = joined_a["you"], joined_b["you"]
            assert {you_a, you_b} == {0, 1}

            state_a = next(m for m in msgs_a if m["type"] == "nj_state")
            state_b = next(m for m in msgs_b if m["type"] == "nj_state")
            assert state_a["phase"] == "arrange"
            assert state_b["phase"] == "arrange"

            # 배치 단계: 상대 칸은 정체가 가려져 있어야 함
            for row_cells in state_a["board"]:
                for cell in row_cells:
                    if cell is not None and cell["side"] != you_a:
                        assert "type" not in cell

            side0_ws = ws_a if you_a == 0 else ws_b
            side1_ws = ws_b if you_a == 0 else ws_a

            side0_ws.send_json({"type": "nj_ready"})
            side0_ws.receive_json()  # 내 준비완료 반영된 상태
            side1_ws.receive_json()  # 상대 준비완료 알림
            side1_ws.send_json({"type": "nj_ready"})

            state_after_ready_0 = side0_ws.receive_json()
            state_after_ready_1 = side1_ws.receive_json()
            assert state_after_ready_0["phase"] == "move"
            assert state_after_ready_1["phase"] == "move"
            assert state_after_ready_0["current_turn"] == 0

            # side0 선(先) 차례 — 앞줄 숫자말 하나를 한 칸 전진시켜본다 (합법수)
            front_row = R.own_back_row(0) + 2 * R.forward_dir(0)
            mover_piece = None
            for row_cells in state_after_ready_0["board"]:
                pass
            # 보드 상 (col, front_row)에서 side0 소유의 말 id를 찾는다
            board0 = state_after_ready_0["board"]
            for c in range(R.BOARD_COLS):
                cell = board0[front_row][c]
                if cell is not None and cell["side"] == 0:
                    mover_piece = cell["id"]
                    mover_col = c
                    break
            assert mover_piece is not None

            side0_ws.send_json(
                {
                    "type": "nj_move",
                    "piece_id": mover_piece,
                    "col": mover_col,
                    "row": front_row + R.forward_dir(0),
                }
            )
            moved_state_0 = side0_ws.receive_json()
            moved_state_1 = side1_ws.receive_json()
            assert moved_state_0["type"] == "nj_state"
            assert moved_state_1["type"] == "nj_state"
            assert moved_state_0["current_turn"] == 1
            assert moved_state_1["current_turn"] == 1
