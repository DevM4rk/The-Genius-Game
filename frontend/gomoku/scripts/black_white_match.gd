# black_white_match.gd — 흑과백 데스매치 세그먼트 엔진 (9라운드 단위 승부)
#
# 규칙 요약:
#   - 각 플레이어는 0~8 숫자 타일 9장씩 보유 (0,2,4,6,8=흑 / 1,3,5,7=백).
#   - 매 라운드 선(先)이 타일을 낸 뒤 후(後)가 타일을 낸다.
#   - 더 높은 숫자를 낸 쪽이 승점 획득, 동일하면 무승부(승점 없음).
#   - 승자가 다음 라운드 선이 되고, 무승부면 선이 유지된다.
#   - 9라운드 후 승점이 높은 쪽이 세그먼트 승리. 동점이면 호출자가 새 세그먼트(연장전)를 만든다.
#
# 낸 타일 값은 UI가 라운드 결과 이외에는 노출하지 않는다 — 엔진은 history에
# 전체 기록을 보관하지만, 공개 시점은 UI(black_white_board.gd)가 결정한다.
class_name BlackWhiteMatch
extends RefCounted

const TILE_COUNT := 9

var hands: Array = [[], []]  # Array[Array[int]] — 플레이어별 남은 타일
var scores: Array = [0, 0]
var round_index: int = 0
var starter: int = 0  # 이번 라운드 선 플레이어 (0 또는 1)
var history: Array = []  # Array[Dictionary] — 라운드별 전체 기록 (매치 종료 후 공개용)


func _init(p_starter: int) -> void:
	hands[0] = range(TILE_COUNT)
	hands[1] = range(TILE_COUNT)
	starter = p_starter


static func is_black(value: int) -> bool:
	return value % 2 == 0


func other(player: int) -> int:
	return 1 - player


func remaining_count(player: int) -> int:
	return hands[player].size()


func is_over() -> bool:
	return round_index >= TILE_COUNT


## first_value/second_value는 항상 "선/후" 순서 (starter가 낸 값이 first_value).
func play_round(first_value: int, second_value: int) -> Dictionary:
	assert(not is_over(), "이미 종료된 매치입니다.")
	var second_player := other(starter)
	assert(hands[starter].has(first_value), "선 플레이어가 갖고 있지 않은 타일입니다.")
	assert(hands[second_player].has(second_value), "후 플레이어가 갖고 있지 않은 타일입니다.")

	hands[starter].erase(first_value)
	hands[second_player].erase(second_value)

	var winner := -1
	if first_value > second_value:
		winner = starter
	elif second_value > first_value:
		winner = second_player
	# 값이 같으면 무승부(winner = -1), 승점 없음.

	if winner >= 0:
		scores[winner] += 1

	var record := {
		"round": round_index,
		"starter": starter,
		"starter_tile": first_value,
		"second_tile": second_value,
		"winner": winner,
	}
	history.append(record)

	round_index += 1
	if winner >= 0:
		starter = winner
	# 무승부면 선 유지 (starter 변경 없음).

	return record


func is_tie() -> bool:
	return is_over() and scores[0] == scores[1]


## 세그먼트(9라운드) 승자. 동점이면 -1.
func segment_winner() -> int:
	if scores[0] == scores[1]:
		return -1
	return 0 if scores[0] > scores[1] else 1
