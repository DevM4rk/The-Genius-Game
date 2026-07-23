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
		"rules_text":
			"15×15 바둑판에 흑·백이 번갈아 돌을 둡니다.\n\n"
			+ "가로·세로·대각선으로 같은 색 돌 5개를 먼저 이으면 승리합니다.",
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
