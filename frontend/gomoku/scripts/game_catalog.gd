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
		"id": "black_white2",
		"name": "흑과백2",
		"scene_path": "res://ui/black_white2_board.tscn",
		"supports_local": false,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"두 사람이 99포인트씩 받고 최대 9라운드를 진행합니다. 1라운드 선(先)은 무작위로 정해집니다.\n\n"
			+ "매 라운드 선이 먼저 포인트를 내고, 후(後)가 이어서 냅니다. 0포인트부터 남은 포인트 전부까지 낼 수 있습니다. "
			+ "낸 포인트가 한 자릿수(0~9)면 검은색, 두 자릿수(10~99)면 흰색으로 상대에게 표시됩니다.\n\n"
			+ "더 많이 낸 쪽이 승점 1점을 얻고 다음 라운드 선이 됩니다. 같으면 승점 변동 없이 선이 유지됩니다. "
			+ "라운드마다 승패만 알려 주고, 낸 포인트는 게임이 끝난 뒤 기록으로 공개됩니다.\n\n"
			+ "낸 포인트는 사라지고, 남은 포인트는 5단계 표시등(0~19 / 20~39 / 40~59 / 60~79 / 80~99)으로 공개됩니다. "
			+ "포인트를 내는 순간 표시등이 바뀌므로, 후는 선의 표시등 변화를 보고 결정할 수 있습니다.\n\n"
			+ "승점 5점을 먼저 얻으면 즉시 승리합니다. 9라운드가 끝나면 승점이 높은 쪽이 이기고, "
			+ "승점이 같으면 남은 포인트가 많은 쪽이 이깁니다. 남은 포인트까지 같으면 무승부입니다.\n\n"
			+ "온라인 전용 게임입니다(랜덤매치).",
	},
	{
		"id": "betting_rps",
		"name": "베팅 가위바위보",
		"scene_path": "res://ui/betting_rps_board.tscn",
		"supports_local": false,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"두 사람이 칩 10개씩 받고 최대 10라운드를 진행합니다.\n\n"
			+ "매 라운드 두 사람이 동시에 가위·바위·보 중 하나와 걸 칩(1개 이상, 가진 칩 이하)을 냅니다. "
			+ "둘 다 낼 때까지 상대의 손과 칩은 보이지 않습니다.\n\n"
			+ "이긴 쪽은 상대가 건 칩만큼 상대에게서 가져옵니다. 비기면 칩 변동이 없습니다. "
			+ "라운드가 끝나면 두 사람의 손과 칩이 공개됩니다.\n\n"
			+ "한 사람의 칩이 0이 되거나 10라운드가 끝나면 칩이 많은 쪽이 승리합니다. 같으면 무승부입니다.\n\n"
			+ "온라인 전용 게임입니다(랜덤매치).",
	},
	{
		"id": "indian_poker",
		"name": "인디언 포커",
		"scene_path": "res://ui/indian_poker_board.tscn",
		"supports_local": false,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"1~10 카드 두 벌(20장)을 섞어 매 라운드 한 장씩 받습니다. 두 사람은 칩 20개씩으로 시작하고 최대 10라운드를 진행합니다.\n\n"
			+ "내 카드는 보이지 않고, 상대 카드만 보입니다.\n\n"
			+ "두 사람이 동시에 걸 칩(1개 이상, 가진 칩 이하)을 정합니다. 둘 다 걸면 카드를 공개하고, "
			+ "숫자가 큰 쪽이 상대가 건 칩만큼 가져옵니다. 숫자가 같으면 칩 변동이 없습니다.\n\n"
			+ "한 사람의 칩이 0이 되거나 10라운드가 끝나면 칩이 많은 쪽이 승리합니다. 같으면 무승부입니다.\n\n"
			+ "온라인 전용 게임입니다(랜덤매치).",
	},
	{
		"id": "two_sided_poker",
		"name": "양면포커",
		"scene_path": "res://ui/two_sided_poker_board.tscn",
		"supports_local": false,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"카드마다 앞면과 뒷면에 1~10 숫자가 하나씩 적혀 있습니다. 매 라운드 한 장씩 받고, "
			+ "두 사람은 칩 20개씩으로 시작해 최대 10라운드를 진행합니다.\n\n"
			+ "카드를 두 사람 사이에 세워 든다고 생각하면 됩니다. 내 카드는 앞면만, 상대 카드는 뒷면만 보입니다. "
			+ "내 카드 뒷면은 상대만, 상대 카드 앞면은 상대만 압니다.\n\n"
			+ "두 사람이 동시에 걸 칩(1개 이상, 가진 칩 이하)을 정합니다. 둘 다 걸면 양면을 모두 공개하고, "
			+ "앞면과 뒷면의 합이 큰 쪽이 상대가 건 칩만큼 가져옵니다. 합이 같으면 칩 변동이 없습니다.\n\n"
			+ "한 사람의 칩이 0이 되거나 10라운드가 끝나면 칩이 많은 쪽이 승리합니다. 같으면 무승부입니다.\n\n"
			+ "온라인 전용 게임입니다(랜덤매치).",
	},
	{
		"id": "hap_game",
		"name": "결! 합!",
		"scene_path": "res://ui/hap_game_board.tscn",
		"supports_local": false,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"그림 9장이 공개됩니다. 그림마다 도형(●▲■), 도형 색(빨강·파랑·노랑), 배경색(검정·회색·흰색)이 있습니다.\n\n"
			+ "세 장이 도형, 도형 색, 배경색 각각에서 모두 같거나 모두 다르면 \"합\"입니다.\n\n"
			+ "합!: 세 장을 골라 부릅니다. 아직 나오지 않은 합이면 +1점, 합이 아니거나 이미 나온 합이면 -1점입니다.\n\n"
			+ "결!: 더 이상 남은 합이 없다고 생각할 때 부릅니다. 맞으면 +3점이고 게임이 끝납니다. "
			+ "남은 합이 있으면 -1점입니다.\n\n"
			+ "두 사람 모두 언제든 부를 수 있고, 먼저 부른 사람부터 판정합니다. 게임이 끝났을 때 점수가 높은 쪽이 승리합니다.\n\n"
			+ "온라인 전용 게임입니다(랜덤매치).",
	},
	{
		"id": "indian_holdem",
		"name": "인디언 홀덤",
		"scene_path": "res://ui/indian_holdem_board.tscn",
		"supports_local": false,
		"supports_ai": false,
		"supports_turn_choice": false,
		"rules_text":
			"1~10 카드 네 벌(40장)을 씁니다. 두 사람은 칩 30개씩으로 시작하고 최대 10라운드를 진행합니다.\n\n"
			+ "매 라운드 각자 카드 1장을 받고, 공개 카드 2장이 펼쳐집니다. 내 카드는 보이지 않고 상대 카드만 보입니다. "
			+ "라운드마다 참가비로 1칩씩 냅니다.\n\n"
			+ "내 카드와 공개 카드 2장으로 족보를 만듭니다. 트리플(세 수 같음) > 스트레이트(연속 세 수) > 페어 > 하이카드 순이고, "
			+ "같은 족보면 높은 수가 이깁니다.\n\n"
			+ "선부터 번갈아 체크/콜, 레이즈, 다이 중 하나를 합니다. 둘 다 체크하거나 레이즈에 콜하면 카드를 공개해 승부를 봅니다. "
			+ "다이하면 그때까지 건 칩을 모두 잃습니다. 족보와 수가 완전히 같으면 건 칩을 돌려받습니다. "
			+ "선은 라운드마다 번갈아 가며, 상대가 콜할 수 있는 만큼까지만 레이즈할 수 있습니다.\n\n"
			+ "10라운드가 끝나거나 한 사람이 참가비를 낼 수 없으면 칩이 많은 쪽이 승리합니다.\n\n"
			+ "온라인 전용 게임입니다(랜덤매치).",
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
