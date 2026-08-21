# number_janggi_rules_test.gd — 1단계 검증용 임시 테스트 씬 스크립트.
# 이 씬을 열고 F6(현재 씬 실행)을 누르면 하단 Output 패널에 결과가 찍힌다.
extends Node

const Rules := preload("res://scripts/number_janggi_rules.gd")

var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	print("── 숫자장기 1단계 규칙 테스트 시작 ──")

	_check("좌상단 (0,0)은 판 안", Rules.is_in_bounds(0, 0))
	_check("우하단 (5,8)은 판 안", Rules.is_in_bounds(5, 8))
	_check("col=6은 판 밖", not Rules.is_in_bounds(6, 0))
	_check("row=-1은 판 밖", not Rules.is_in_bounds(0, -1))

	_check("bottom 진영은 row 6~8", Rules.is_own_camp(3, 6, 0) and Rules.is_own_camp(3, 8, 0))
	_check("bottom 진영 아님(row 5)", not Rules.is_own_camp(3, 5, 0))
	_check("top 진영은 row 0~2", Rules.is_own_camp(3, 0, 1) and Rules.is_own_camp(3, 2, 1))
	_check("top 진영 아님(row 3)", not Rules.is_own_camp(3, 3, 1))

	_check("bottom 전진 방향은 -1(위로)", Rules.forward_dir(0) == -1)
	_check("top 전진 방향은 +1(아래로)", Rules.forward_dir(1) == 1)

	_check("bottom 기준 상대 맨끝줄은 row 0", Rules.enemy_back_row(0) == 0)
	_check("top 기준 상대 맨끝줄은 row 8", Rules.enemy_back_row(1) == 8)
	_check("bottom 기준 내 맨끝줄은 row 8", Rules.own_back_row(0) == 8)
	_check("top 기준 내 맨끝줄은 row 0", Rules.own_back_row(1) == 0)
	_check("bottom 맨끝줄 앞줄은 row 7", Rules.own_back_row_plus_one(0) == 7)

	_check("(2,4)-(2,5) 전후 인접", Rules.is_orthogonal_adjacent(2, 4, 2, 5))
	_check("(2,4)-(3,4) 좌우 인접", Rules.is_orthogonal_adjacent(2, 4, 3, 4))
	_check("(2,4)-(3,5) 대각선은 인접 아님", not Rules.is_orthogonal_adjacent(2, 4, 3, 5))
	_check("(2,4)-(2,4) 같은칸은 인접 아님", not Rules.is_orthogonal_adjacent(2, 4, 2, 4))

	var corner_neighbors: Array = Rules.orthogonal_neighbors(0, 0)
	_check("모서리 (0,0)은 인접칸 2개", corner_neighbors.size() == 2)
	var center_neighbors: Array = Rules.orthogonal_neighbors(2, 4)
	_check("중앙 (2,4)은 인접칸 4개", center_neighbors.size() == 4)

	# 마이너스 줄: col 1-2, col 3-4 경계만 마이너스. 나머지 좌우 경계는 일반.
	_check("col1-2 좌우 인접은 마이너스", Rules.is_minus_boundary(1, 4, 2, 4))
	_check("col3-4 좌우 인접은 마이너스", Rules.is_minus_boundary(3, 4, 4, 4))
	_check("col0-1 좌우 인접은 일반(플러스)", not Rules.is_minus_boundary(0, 4, 1, 4))
	_check("col2-3 좌우 인접은 일반(플러스)", not Rules.is_minus_boundary(2, 4, 3, 4))
	_check("col4-5 좌우 인접은 일반(플러스)", not Rules.is_minus_boundary(4, 4, 5, 4))
	_check(
		"col1-2라도 row가 다르면(전후 인접) 마이너스 아님",
		not Rules.is_minus_boundary(1, 4, 2, 5)
	)
	_check(
		"같은 col, 다른 row(전후 인접)는 항상 일반(플러스)",
		not Rules.is_minus_boundary(2, 3, 2, 4)
	)

	print("── 결과: PASS %d / FAIL %d ──" % [_pass_count, _fail_count])


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)
