"""오목 보드 단위 테스트 — C++ 테스트와 동일한 시나리오 일부."""

from app.board import GameState, GomokuBoard, MoveResult, Stone


def test_place_and_turn() -> None:
    b = GomokuBoard()
    assert b.current_turn == Stone.BLACK
    assert b.place_stone(7, 7) == MoveResult.OK
    assert b.get_stone(7, 7) == Stone.BLACK
    assert b.current_turn == Stone.WHITE


def test_occupied() -> None:
    b = GomokuBoard()
    assert b.place_stone(0, 0) == MoveResult.OK
    assert b.place_stone(0, 0) == MoveResult.CELL_OCCUPIED


def test_five_in_a_row_horizontal() -> None:
    b = GomokuBoard()
    # 흑: (0,0)(1,0)(2,0)(3,0)(4,0) — 사이에 백이 딴 데 둠
    coords_black = [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)]
    coords_white = [(0, 1), (1, 1), (2, 1), (3, 1)]
    for i, (bx, by) in enumerate(coords_black):
        assert b.place_stone(bx, by) == MoveResult.OK
        if i < 4:
            wx, wy = coords_white[i]
            assert b.place_stone(wx, wy) == MoveResult.OK
    assert b.state == GameState.BLACK_WIN


def test_out_of_bounds() -> None:
    b = GomokuBoard()
    assert b.place_stone(-1, 0) == MoveResult.OUT_OF_BOUNDS
    assert b.place_stone(15, 0) == MoveResult.OUT_OF_BOUNDS
