# black_white_match.gd — 흑과백 데스매치 세그먼트 엔진 (9라운드 단위 승부)
#
# 규칙 요약:
#   - 각 플레이어는 0~8 숫자 타일 9장씩 보유 (0,2,4,6,8=흑 / 1,3,5,7=백).
#   - 매치 시작 전, 각 플레이어가 자신의 9장을 원하는 위치(슬롯)에 배치한다.
#     이 배치 순서는 매치가 끝날 때까지 고정되며, 상대는 그 슬롯의 "색"만
#     계속 볼 수 있다(뒷면 색은 항상 공개). 타일을 내면 그 슬롯은 비어
#     남는다 — 배치가 밀리지 않아야 상대가 위치로도 유추할 수 있다.
#   - 매 라운드 선(先)이 슬롯 하나를 낸 뒤 후(後)가 슬롯을 낸다.
#   - 더 높은 숫자를 낸 쪽이 승점 획득, 동일하면 무승부(승점 없음).
#   - 승자가 다음 라운드 선이 되고, 무승부면 선이 유지된다.
#   - 9라운드 후 승점이 높은 쪽이 세그먼트 승리. 동점이면 호출자가 새
#     세그먼트(연장전)를 만든다.
class_name BlackWhiteMatch
extends RefCounted

const TILE_COUNT := 9

var arrangement: Array = [[], []]  # arrangement[player][slot] = 그 슬롯의 숫자(0~8 순열)
var used: Array = [[], []]  # used[player][slot] = 그 슬롯의 타일을 이미 냈는지
var scores: Array = [0, 0]
var round_index: int = 0
var starter: int = 0  # 이번 라운드 선 플레이어 (0 또는 1)
var history: Array = []  # Array[Dictionary] — 라운드별 전체 기록 (매치 종료 후 공개용)

var _pending_first_slot: int = -1
var _pending_first_value: int = -1


func _init(p_starter: int, p_arrangement0: Array, p_arrangement1: Array) -> void:
	arrangement[0] = p_arrangement0.duplicate()
	arrangement[1] = p_arrangement1.duplicate()
	used[0] = []
	used[1] = []
	for _i in TILE_COUNT:
		used[0].append(false)
		used[1].append(false)
	starter = p_starter


static func is_black(value: int) -> bool:
	return value % 2 == 0


func other(player: int) -> int:
	return 1 - player


func is_over() -> bool:
	return round_index >= TILE_COUNT


func value_at(player: int, slot: int) -> int:
	return arrangement[player][slot]


func is_used(player: int, slot: int) -> bool:
	return used[player][slot]


func has_pending_first() -> bool:
	return _pending_first_slot >= 0


func staged_first_value() -> int:
	return _pending_first_value


## 선(先)이 슬롯을 낸다. 이 순간 바로 사용 처리되어 양쪽 화면에서
## 해당 슬롯이 빈 칸으로 보인다(승패는 아직 결정되지 않음).
func commit_first(slot: int) -> void:
	assert(not is_over(), "이미 종료된 매치입니다.")
	assert(not has_pending_first(), "이미 선의 타일이 제시되었습니다.")
	assert(not used[starter][slot], "선 플레이어가 이미 사용한 슬롯입니다.")
	used[starter][slot] = true
	_pending_first_slot = slot
	_pending_first_value = arrangement[starter][slot]


## 후(後)가 슬롯을 낸다. 두 타일을 비교해 라운드를 확정한다.
func commit_second(slot: int) -> Dictionary:
	assert(has_pending_first(), "선의 타일이 아직 제시되지 않았습니다.")
	var second_player := other(starter)
	assert(not used[second_player][slot], "후 플레이어가 이미 사용한 슬롯입니다.")

	used[second_player][slot] = true
	var first_value := _pending_first_value
	var first_slot := _pending_first_slot
	var second_value: int = arrangement[second_player][slot]

	var winner := -1
	if first_value > second_value:
		winner = starter
	elif second_value > first_value:
		winner = second_player
	# 같으면 무승부(winner = -1), 승점 없음.

	if winner >= 0:
		scores[winner] += 1

	var record := {
		"round": round_index,
		"starter": starter,
		"starter_slot": first_slot,
		"starter_tile": first_value,
		"second_slot": slot,
		"second_tile": second_value,
		"winner": winner,
	}
	history.append(record)

	round_index += 1
	if winner >= 0:
		starter = winner
	# 무승부면 선 유지 (starter 변경 없음).

	_pending_first_slot = -1
	_pending_first_value = -1

	return record


func is_tie() -> bool:
	return is_over() and scores[0] == scores[1]


## 세그먼트(9라운드) 승자. 동점이면 -1.
func segment_winner() -> int:
	if scores[0] == scores[1]:
		return -1
	return 0 if scores[0] > scores[1] else 1
