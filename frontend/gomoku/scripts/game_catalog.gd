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
		"supports_turn_choice": false,
		"rules_text":
			"두 사람이 0~8 숫자 타일 9장씩(흑: 0·2·4·6·8, 백: 1·3·5·7)을 나눠 갖습니다.\n\n"
			+ "매 라운드 선(先)이 타일 1장을 낸 뒤 후(後)가 타일을 냅니다. "
			+ "더 높은 숫자를 낸 쪽이 승점을 얻고, 같으면 무승부입니다.\n\n"
			+ "이긴 쪽이 다음 라운드 선이 되고, 무승부면 선이 그대로 유지됩니다. "
			+ "상대가 낸 숫자는 공개되지 않으니 남은 타일의 색으로 유추해야 합니다.\n\n"
			+ "9라운드 후 승점이 더 높은 쪽이 승리합니다. 동점이면 타일을 새로 받아 연장전을 진행합니다.",
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
