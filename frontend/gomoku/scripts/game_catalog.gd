# game_catalog.gd — 플랫폼 게임 목록 (규칙/혼자하기/매칭 공통 데이터)
class_name GameCatalog
extends RefCounted

const GAMES: Array[Dictionary] = [
	{
		"id": "gomoku",
		"name": "오목",
		"scene_path": "res://board.tscn",
		"supports_local": true,
		"supports_ai": true,
		"supports_turn_choice": true,
		"rules_text":
			"15×15 바둑판에 흑·백이 번갈아 돌을 둡니다.\n\n"
			+ "가로·세로·대각선으로 같은 색 돌 5개를 먼저 이으면 승리합니다.",
	},
	{
		"id": "black_white",
		"name": "흑과백",
		"scene_path": "res://ui/black_white_board.tscn",
		"supports_local": true,
		"supports_ai": false,
		"supports_turn_choice": true,
		"rules_text":
			"두 사람이 0~8 숫자 타일 9장씩(흑: 0·2·4·6·8, 백: 1·3·5·7)을 나눠 갖습니다.\n\n"
			+ "매 라운드 선(先)이 타일 1장을 낸 뒤 후(後)가 타일을 냅니다. "
			+ "더 높은 숫자를 낸 쪽이 승점을 얻고, 같으면 무승부입니다.\n\n"
			+ "이긴 쪽이 다음 라운드 선이 되고, 무승부면 선이 그대로 유지됩니다. "
			+ "상대가 낸 숫자는 공개되지 않으니 남은 타일의 색으로 유추해야 합니다.\n\n"
			+ "9라운드 후 승점이 더 높은 쪽이 승리합니다. 동점이면 타일을 새로 받아 연장전을 진행합니다.",
	},
	{
		"id": "number_janggi",
		"name": "숫자장기",
		"scene_path": "res://ui/number_janggi_board.tscn",
		"supports_local": true,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"가로 6칸 · 세로 9칸 판에 숫자 1~10, 지뢰 3개, 왕 1개(총 14개)를 자기 진영에 뒤집어 배치합니다.\n\n"
			+ "말은 양옆·앞뒤 1칸, 앞으로는 최대 2칸까지 이동합니다(지뢰는 이동 불가). "
			+ "이동 후 상대 말과 전후좌우로 맞닿으면 즉시 대결합니다.\n\n"
			+ "두 숫자를 더해 10 이상이면 큰 수가, 10 미만이면 작은 수가 승리합니다. "
			+ "판에 표시된 마이너스 줄에서 맞닿으면 두 수의 차로 승부를 가르며, 이때는 차가 10 이상이면 큰 수가, "
			+ "10 미만이면 작은 수가 승리합니다. 숫자가 같으면 둘 다 제거됩니다.\n\n"
			+ "지뢰와 부딪히면 두 말 모두 제거되고, 왕은 다른 말과 부딪히면 그 즉시 제거되어 패배합니다 "
			+ "(왕끼리는 아무 일도 없습니다). 상대 진영 끝줄에 도달하면 그 말을 제거하고, 죽은 말 하나를 "
			+ "공개된 채로 부활시킬 수 있습니다.\n\n"
			+ "블라인드(정체 숨기기) · +1 · -1 아이템을 대결마다 한 번씩 쓸 수 있습니다(아이템당 1회, "
			+ "이동한 쪽만 사용 가능). 상대 왕을 잡거나, 왕 외 모든 말을 잡거나, 자신의 왕이 상대 진영 끝줄에 "
			+ "도달하거나, 제한시간(60초) 안에 상대가 두지 못하면 승리합니다.",
	},
]


static func all() -> Array[Dictionary]:
	return GAMES


static func by_id(game_id: String) -> Dictionary:
	for game in GAMES:
		if str(game.get("id", "")) == game_id:
			return game
	return {}


static func display_name(game_id: String) -> String:
	var game := by_id(game_id)
	if game.is_empty():
		return game_id
	return str(game.get("name", game_id))
