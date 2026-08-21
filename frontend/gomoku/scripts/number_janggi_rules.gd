# number_janggi_rules.gd — 숫자장기 보드 좌표 · 말 데이터 · 마이너스 줄 판정
#
# 좌표계: col은 0~5 (가로 6칸), row는 0~8 (세로 9칸).
# "아래(row가 큰 쪽)" = 화면에서 항상 나(로컬 관전자) 쪽, "위(row가 작은 쪽)" = 상대 쪽.
# 즉 row 6,7,8 = 아래쪽 플레이어(bottom)의 진영, row 0,1,2 = 위쪽 플레이어(top)의 진영.
# bottom 플레이어의 "앞"은 row가 작아지는 방향(위로 진격), top 플레이어의 "앞"은 row가 커지는 방향.
#
# 마이너스 줄: 스크린샷 기준 세로 레드라인 2줄이 (col 1↔2) 경계와 (col 3↔4) 경계를
# 9칸 전부에 걸쳐 지나간다 → 2 × 9 = 18개. 즉, 같은 row에서 좌우로 붙은 두 말의
# col이 {1,2} 또는 {3,4} 조합일 때만 마이너스 대결이 된다. 전후(세로) 인접은 항상 일반(플러스) 대결.
class_name NumberJanggiRules
extends RefCounted

const BOARD_COLS := 6
const BOARD_ROWS := 9
const CAMP_ROWS := 3

## 마이너스 줄이 지나가는 좌우 col 경계쌍.
const MINUS_COLUMN_GAPS := [[1, 2], [3, 4]]

enum PieceType { NUMBER, MINE, KING }

## 결승진출자 1인당 지급되는 말 구성: 숫자 1~10, 지뢰 3개, 왕 1개 = 총 14개.
const NUMBER_COUNT := 10
const MINE_COUNT := 3
const TOTAL_PIECE_COUNT := NUMBER_COUNT + MINE_COUNT + 1  # 14

## side: 0 = bottom(아래, 로컬 관전자 기준 나), 1 = top(위, 상대)


static func is_in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < BOARD_COLS and row >= 0 and row < BOARD_ROWS


## side 진영(자기 앞줄 3칸)에 속하는 칸인지.
static func is_own_camp(col: int, row: int, side: int) -> bool:
	if not is_in_bounds(col, row):
		return false
	if side == 0:
		return row >= BOARD_ROWS - CAMP_ROWS  # row 6,7,8
	return row < CAMP_ROWS  # row 0,1,2


## side가 전진할 때 row가 변하는 방향 (-1 또는 +1).
static func forward_dir(side: int) -> int:
	return -1 if side == 0 else 1


## side 기준 "상대방 진영 맨 끝 줄" row 인덱스 (승급/부활 판정용).
static func enemy_back_row(side: int) -> int:
	return 0 if side == 0 else BOARD_ROWS - 1


## side 기준 "자기 진영 맨 끝 줄" row 인덱스 (부활 배치 기준).
static func own_back_row(side: int) -> int:
	return BOARD_ROWS - 1 if side == 0 else 0


## side 기준으로 own_back_row에서 한 칸 앞(적 쪽)으로 이동한 row.
static func own_back_row_plus_one(side: int) -> int:
	return own_back_row(side) + forward_dir(side)


## 두 칸이 전후좌우로 맞닿아 있는지 (대각선 제외).
static func is_orthogonal_adjacent(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
	var dc: int = abs(col_a - col_b)
	var dr: int = abs(row_a - row_b)
	return (dc == 1 and dr == 0) or (dc == 0 and dr == 1)


## (col, row) 기준 판 안의 전후좌우 인접 칸 좌표 목록.
static func orthogonal_neighbors(col: int, row: int) -> Array:
	var out: Array = []
	for delta in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
		var nc: int = col + delta[0]
		var nr: int = row + delta[1]
		if is_in_bounds(nc, nr):
			out.append([nc, nr])
	return out


## 두 칸이 좌우로 붙어 있고, 그 경계가 마이너스 줄 경계인지.
static func is_minus_boundary(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
	if row_a != row_b:
		return false
	if abs(col_a - col_b) != 1:
		return false
	var lo: int = min(col_a, col_b)
	var hi: int = max(col_a, col_b)
	for gap in MINUS_COLUMN_GAPS:
		if gap[0] == lo and gap[1] == hi:
			return true
	return false


## 맞닿은 두 말 사이 대결이 "마이너스 대결"인지 "플러스 대결"인지.
static func is_minus_duel(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
	return is_minus_boundary(col_a, row_a, col_b, row_b)
