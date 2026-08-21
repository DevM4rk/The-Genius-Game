# number_janggi_match_test.gd — 2~7단계(배치/이동/대결/승리/부활/아이템/타임아웃) 검증용 테스트 씬.
# 이 씬을 열고 F6을 누르면 하단 Output 패널에 결과가 찍힌다.
extends Node

const Rules := preload("res://scripts/number_janggi_rules.gd")
const Match := preload("res://scripts/number_janggi_match.gd")

var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	print("── 숫자장기 2~7단계 규칙 테스트 시작 ──")
	_test_stage2_arrangement()
	_test_stage3_movement()
	_test_stage4_combat()
	_test_stage5_win_and_revive()
	_test_stage6_items()
	_test_stage7_timeout()
	print("── 결과: PASS %d / FAIL %d ──" % [_pass_count, _fail_count])


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)


# ── 강제 배치 헬퍼: 대결/부활 시나리오를 임의 위치에서 바로 만들기 위한 테스트 전용 함수 ──
func _force_place(m: NumberJanggiMatch, piece_id: int, col: int, row: int) -> void:
	m.board[row][col] = piece_id
	m.pieces[piece_id].col = col
	m.pieces[piece_id].row = row


# ── 2단계: 배치 ─────────────────────────────────────────────
func _test_stage2_arrangement() -> void:
	var m := Match.new()
	m.start_new_match()

	_check("양쪽 다 14개씩 생성됨", m.side_piece_ids(0).size() == 14 and m.side_piece_ids(1).size() == 14)
	_check("처음엔 14개 다 미배치", m.unplaced_piece_ids(0).size() == 14)

	var king0 := m.find_piece_id(0, Rules.PieceType.KING)
	_check("진영 밖 배치는 거부됨", not m.place_piece(0, king0, 2, 4).ok)
	_check("진영 안 배치는 성공", m.place_piece(0, king0, 2, 8).ok)
	_check("미배치 개수가 13으로 줄어듦", m.unplaced_piece_ids(0).size() == 13)

	var n1 := m.find_piece_id(0, Rules.PieceType.NUMBER, 1)
	_check("이미 왕이 놓인 칸엔 배치 불가", not m.place_piece(0, n1, 2, 8).ok)
	_check("아직 다 안 놓았으면 준비완료 거부", not m.mark_ready(0).ok)

	m.auto_arrange(0)
	m.auto_arrange(1)
	_check("auto_arrange 후 양쪽 다 배치 완료", m.is_arrangement_complete(0) and m.is_arrangement_complete(1))
	_check("준비완료 처리됨", m.mark_ready(0).ok and m.mark_ready(1).ok)
	_check("양쪽 다 준비완료", m.both_ready())
	_check("이동 단계 시작 성공", m.start_move_phase(0).ok)
	_check("선 플레이어는 0번", m.current_turn == 0)


# ── 3단계: 이동 규칙 ─────────────────────────────────────────
func _test_stage3_movement() -> void:
	var m := Match.new()
	m.start_new_match()
	m.auto_arrange(0)
	m.auto_arrange(1)
	m.mark_ready(0)
	m.mark_ready(1)
	m.start_move_phase(0)

	# auto_arrange(0): row6·row7 전부 채워짐, row8은 col0~1만 채워짐(14개라서 4칸 빔).
	var front_piece: int = m.board[6][2]
	var moves := m.legal_moves(front_piece)
	_check("앞줄 가운데 말은 좌우 막히고 앞1/앞2/대각 2개 = 4개", moves.size() == 4)

	var mine_id := m.find_piece_id(0, Rules.PieceType.MINE)
	_check("지뢰는 이동 불가", m.legal_moves(mine_id).size() == 0)

	_check("자기 턴 아닌 말은 이동 불가", m.legal_moves(m.board[0][2]).size() == 0)

	# 좌/우/앞1(=앞2 경로 중간도 막음)/앞대각좌/앞대각우를 전부 막아서 완전 포위
	var s := Match.new()
	s.start_new_match()
	s.phase = Match.Phase.MOVE
	s.current_turn = 0
	var center := s.find_piece_id(0, Rules.PieceType.NUMBER, 1)
	var blockers: Array = [
		s.find_piece_id(0, Rules.PieceType.NUMBER, 2),
		s.find_piece_id(0, Rules.PieceType.NUMBER, 3),
		s.find_piece_id(0, Rules.PieceType.NUMBER, 4),
		s.find_piece_id(0, Rules.PieceType.NUMBER, 5),
		s.find_piece_id(0, Rules.PieceType.NUMBER, 6),
	]
	_force_place(s, center, 2, 4)
	_force_place(s, blockers[0], 1, 4)
	_force_place(s, blockers[1], 3, 4)
	_force_place(s, blockers[2], 2, 3)
	_force_place(s, blockers[3], 1, 3)
	_force_place(s, blockers[4], 3, 3)
	_check("전후좌우+대각 전부 막힌 말은 이동 불가", s.legal_moves(center).size() == 0)


# ── 4단계: 대결 판정 ─────────────────────────────────────────
func _test_stage4_combat() -> void:
	# 4-A: 일반(플러스) 대결 — 3(측) vs 8(적), 세로 인접, 합 11 → 큰 수 승리
	var a := Match.new()
	a.start_new_match()
	var a3 := a.find_piece_id(0, Rules.PieceType.NUMBER, 3)
	var a8 := a.find_piece_id(1, Rules.PieceType.NUMBER, 8)
	a.phase = Match.Phase.MOVE
	a.current_turn = 0
	_force_place(a, a3, 2, 4)
	_force_place(a, a8, 2, 3)
	a._begin_combat_or_finish(0, a3)
	a.decline_item(0)
	a.resolve_duels()
	_check("플러스 대결(3+8=11): 작은 수(3) 제거", not a.pieces[a3].alive)
	_check("플러스 대결(3+8=11): 큰 수(8) 생존", a.pieces[a8].alive)

	# 4-B: 마이너스 대결 — 9(측) vs 2(적), 좌우(col1-2) 인접, 차 7 → 작은 수 승리
	var b := Match.new()
	b.start_new_match()
	var b9 := b.find_piece_id(0, Rules.PieceType.NUMBER, 9)
	var b2 := b.find_piece_id(1, Rules.PieceType.NUMBER, 2)
	b.phase = Match.Phase.MOVE
	b.current_turn = 0
	_force_place(b, b9, 1, 4)
	_force_place(b, b2, 2, 4)
	b._begin_combat_or_finish(0, b9)
	b.decline_item(0)
	b.resolve_duels()
	_check("마이너스 대결(9-2=7): 큰 수(9) 제거", not b.pieces[b9].alive)
	_check("마이너스 대결(9-2=7): 작은 수(2) 생존", b.pieces[b2].alive)

	# 4-C: 마이너스 대결 동일숫자 — 5 vs 5 (col3-4) → 둘 다 제거
	var c := Match.new()
	c.start_new_match()
	var c5a := c.find_piece_id(0, Rules.PieceType.NUMBER, 5)
	var c5b := c.find_piece_id(1, Rules.PieceType.NUMBER, 5)
	c.phase = Match.Phase.MOVE
	c.current_turn = 0
	_force_place(c, c5a, 3, 4)
	_force_place(c, c5b, 4, 4)
	c._begin_combat_or_finish(0, c5a)
	c.decline_item(0)
	c.resolve_duels()
	_check("마이너스 동일숫자(5 vs 5): 둘 다 제거", not c.pieces[c5a].alive and not c.pieces[c5b].alive)

	# 4-D: 동시 대결 — 내 말(2)이 좌(8, 마이너스)엔 이기고 우(9, 플러스)엔 짐
	var d := Match.new()
	d.start_new_match()
	var d_mine := d.find_piece_id(0, Rules.PieceType.NUMBER, 2)
	var d_left := d.find_piece_id(1, Rules.PieceType.NUMBER, 8)  # col1-2 마이너스: 차 6<10 → 작은 수(2) 승리
	var d_right := d.find_piece_id(1, Rules.PieceType.NUMBER, 9)  # col2-3 플러스: 합 11>=10 → 큰 수(9) 승리
	d.phase = Match.Phase.MOVE
	d.current_turn = 0
	_force_place(d, d_mine, 2, 4)
	_force_place(d, d_left, 1, 4)
	_force_place(d, d_right, 3, 4)
	d._begin_combat_or_finish(0, d_mine)
	d.decline_item(0)
	d.resolve_duels()
	_check("동시대결: 내 말은 우측(9)에 져서 제거됨", not d.pieces[d_mine].alive)
	_check("동시대결: 좌측(8)은 내 말한테 져서 제거됨", not d.pieces[d_left].alive)
	_check("동시대결: 우측(9)은 살아남음(먼저 계산된 좌측 결과에 영향받지 않음)", d.pieces[d_right].alive)

	# 4-E: 지뢰 자폭 — 숫자와 상관없이 둘 다 제거
	var e := Match.new()
	e.start_new_match()
	var e_num := e.find_piece_id(0, Rules.PieceType.NUMBER, 1)
	var e_mine := e.find_piece_id(1, Rules.PieceType.MINE)
	e.phase = Match.Phase.MOVE
	e.current_turn = 0
	_force_place(e, e_num, 2, 4)
	_force_place(e, e_mine, 2, 3)
	e._begin_combat_or_finish(0, e_num)
	e.decline_item(0)
	e.resolve_duels()
	_check("지뢰 자폭: 지뢰 제거", not e.pieces[e_mine].alive)
	_check("지뢰 자폭: 대결한 숫자말도 제거", not e.pieces[e_num].alive)

	# 4-F: 왕 대결 — 왕은 무조건 제거, 상대는 생존
	var f := Match.new()
	f.start_new_match()
	var f_num := f.find_piece_id(0, Rules.PieceType.NUMBER, 10)
	var f_king := f.find_piece_id(1, Rules.PieceType.KING)
	f.phase = Match.Phase.MOVE
	f.current_turn = 0
	_force_place(f, f_num, 2, 4)
	_force_place(f, f_king, 2, 3)
	f._begin_combat_or_finish(0, f_num)
	f.decline_item(0)
	f.resolve_duels()
	_check("왕 대결: 왕이 제거됨(숫자 무관)", not f.pieces[f_king].alive)
	_check("왕 대결: 상대 숫자말은 생존", f.pieces[f_num].alive)
	_check("왕을 잡으면 즉시 게임종료", f.phase == Match.Phase.GAME_OVER and f.winner == 0 and f.win_reason == "king_captured")

	# 4-G: 왕 vs 왕 — 아무 일도 없음
	var g := Match.new()
	g.start_new_match()
	var g_king0 := g.find_piece_id(0, Rules.PieceType.KING)
	var g_king1 := g.find_piece_id(1, Rules.PieceType.KING)
	g.phase = Match.Phase.MOVE
	g.current_turn = 0
	_force_place(g, g_king0, 2, 4)
	_force_place(g, g_king1, 2, 3)
	g._begin_combat_or_finish(0, g_king0)
	g.decline_item(0)
	g.resolve_duels()
	_check("왕 vs 왕: 둘 다 생존, 아무 일도 없음", g.pieces[g_king0].alive and g.pieces[g_king1].alive)
	_check("왕 vs 왕 이후 정상적으로 다음 턴으로 넘어감", g.phase == Match.Phase.MOVE and g.current_turn == 1)


# ── 5단계: 승리조건 + 부활 ────────────────────────────────────
func _test_stage5_win_and_revive() -> void:
	# 5-A: 왕이 상대 맨 끝줄에 무전투로 도착 → 즉시 승리
	var a := Match.new()
	a.start_new_match()
	var king0 := a.find_piece_id(0, Rules.PieceType.KING)
	a.phase = Match.Phase.MOVE
	a.current_turn = 0
	_force_place(a, king0, 3, 0)  # side0 기준 상대 맨끝줄 = row 0
	a._begin_combat_or_finish(0, king0)
	_check("왕이 무전투로 상대 맨끝줄 도착 시 즉시 승리", a.phase == Match.Phase.GAME_OVER and a.winner == 0 and a.win_reason == "king_reached_end")

	# 5-B: 숫자말이 무전투로 상대 맨끝줄 도착 → 부활 대기
	var b := Match.new()
	b.start_new_match()
	var num0 := b.find_piece_id(0, Rules.PieceType.NUMBER, 7)
	b.phase = Match.Phase.MOVE
	b.current_turn = 0
	_force_place(b, num0, 3, 0)
	b._begin_combat_or_finish(0, num0)
	_check("숫자말이 상대 맨끝줄 도착 시 부활 대기 상태로 전환", b.phase == Match.Phase.AWAITING_REWARD)

	# 5-B-1: 죽은 말이 없으면 자기자신 부활(그대로 공개만 됨)
	_check("죽은 말 없을 때 자기자신 부활 성공", b.perform_revive(0, num0).ok)
	_check("자기자신 부활 후 정체 공개됨", b.pieces[num0].revealed)
	_check("자기자신 부활 후 이동 단계로 복귀 + 턴 넘어감", b.phase == Match.Phase.MOVE and b.current_turn == 1)

	# 5-C: 죽은 말이 있을 때 그 중 하나를 골라 부활
	var c := Match.new()
	c.start_new_match()
	var c_dead_target := c.find_piece_id(0, Rules.PieceType.NUMBER, 4)
	c.graveyard[0].append(c_dead_target)
	c.pieces[c_dead_target].alive = false
	var c_arrived := c.find_piece_id(0, Rules.PieceType.NUMBER, 6)
	c.phase = Match.Phase.MOVE
	c.current_turn = 0
	_force_place(c, c_arrived, 3, 0)
	c._begin_combat_or_finish(0, c_arrived)
	var revive_result := c.perform_revive(0, c_dead_target)
	_check("죽은 말 선택 부활 성공", revive_result.ok)
	_check("도착했던 말은 제거됨", not c.pieces[c_arrived].alive)
	_check("되살린 말은 생존 + 공개", c.pieces[c_dead_target].alive and c.pieces[c_dead_target].revealed)
	_check("되살린 말은 내 맨끝줄(row 8)에 배치됨", c.pieces[c_dead_target].row == 8)

	# 5-D: 맨끝줄이 꽉 차 있으면 그 앞줄에 부활
	var d := Match.new()
	d.start_new_match()
	for col in range(Rules.BOARD_COLS):
		var filler := d.find_piece_id(0, Rules.PieceType.NUMBER, col + 1)
		_force_place(d, filler, col, 8)
	var d_dead_target := d.find_piece_id(0, Rules.PieceType.NUMBER, 9)
	d.graveyard[0].append(d_dead_target)
	d.pieces[d_dead_target].alive = false
	var d_arrived := d.find_piece_id(0, Rules.PieceType.NUMBER, 10)
	d.phase = Match.Phase.MOVE
	d.current_turn = 0
	_force_place(d, d_arrived, 3, 0)
	d._begin_combat_or_finish(0, d_arrived)
	d.perform_revive(0, d_dead_target)
	_check("맨끝줄이 꽉 차면 그 앞줄(row 7)에 부활", d.pieces[d_dead_target].row == 7)

	# 5-E: 부활 배치 즉시 상대와 인접하면 그 자리에서 대결
	var e := Match.new()
	e.start_new_match()
	var e_dead_target := e.find_piece_id(0, Rules.PieceType.NUMBER, 3)
	e.graveyard[0].append(e_dead_target)
	e.pieces[e_dead_target].alive = false
	var e_arrived := e.find_piece_id(0, Rules.PieceType.NUMBER, 10)
	var e_enemy := e.find_piece_id(1, Rules.PieceType.NUMBER, 1)  # 부활 위치(row8,col?)와 인접시키기 위해 row7에 배치
	e.phase = Match.Phase.MOVE
	e.current_turn = 0
	_force_place(e, e_arrived, 3, 0)
	# e_dead_target(3)이 부활할 예정 위치는 own_back_row(0)=row8의 빈칸 중 첫칸(col0). 그 옆(row7,col0)에 적을 놓으면
	# 인접이 아니라 같은 칸 세로 인접이 되도록 (row8,col0)의 바로 위인 (row7,col0)에 배치.
	_force_place(e, e_enemy, 0, 7)
	e._begin_combat_or_finish(0, e_arrived)
	_check("맨끝줄 도착으로 부활 대기 상태가 됨", e.phase == Match.Phase.AWAITING_REWARD)
	var e_result := e.perform_revive(0, e_dead_target)
	_check("부활 즉시 인접 대결이 감지됨", e_result.ok and e_result.get("pending_duels", []).size() == 1)
	e.decline_item(0)
	e.resolve_duels()
	_check("부활 즉시 대결 계산 완료(합 3+1=4<10 → 작은 수(1) 생존)", e.pieces[e_enemy].alive and not e.pieces[e_dead_target].alive)


# ── 6단계: 아이템 (그 대결을 유발한 쪽만 사용 가능) ─────────────
func _test_stage6_items() -> void:
	# 6-A: 플러스1 아이템으로 원래 지던 대결을 무승부(둘 다 제거)로 바꿈
	var a := Match.new()
	a.start_new_match()
	var a7 := a.find_piece_id(0, Rules.PieceType.NUMBER, 7)
	var a8 := a.find_piece_id(1, Rules.PieceType.NUMBER, 8)
	a.phase = Match.Phase.MOVE
	a.current_turn = 0
	_force_place(a, a7, 2, 4)
	_force_place(a, a8, 2, 3)
	a._begin_combat_or_finish(0, a7)
	_check("가만히 있던 상대(1)는 이 대결에 아이템 사용 불가", not a.declare_item(1, Match.ItemType.PLUS_ONE).ok)
	_check("+1 아이템 선언 성공(이동한 쪽 0)", a.declare_item(0, Match.ItemType.PLUS_ONE).ok)
	a.resolve_duels()
	_check("+1 적용(7→8) 후 동일숫자(8 vs 8)로 둘 다 제거", not a.pieces[a7].alive and not a.pieces[a8].alive)
	_check("+1 아이템 사용 후 소모 처리됨", a.used_items[0]["plus1"])

	# 6-B: 마이너스1 아이템으로 원래 지던 대결을 무승부로 바꿈
	var b := Match.new()
	b.start_new_match()
	var b6 := b.find_piece_id(0, Rules.PieceType.NUMBER, 6)
	var b5 := b.find_piece_id(1, Rules.PieceType.NUMBER, 5)
	b.phase = Match.Phase.MOVE
	b.current_turn = 0
	_force_place(b, b6, 1, 4)
	_force_place(b, b5, 2, 4)  # col1-2 마이너스 경계, 차 1<10 → 작은 수(5) 승리(6이 짐)
	b._begin_combat_or_finish(0, b6)
	_check("-1 아이템 선언 성공", b.declare_item(0, Match.ItemType.MINUS_ONE).ok)
	b.resolve_duels()
	_check("-1 적용(6→5) 후 동일숫자(5 vs 5)로 둘 다 제거", not b.pieces[b6].alive and not b.pieces[b5].alive)

	# 6-C: 아이템은 한 게임에 1개씩만 — 두 번째 사용 시도는 거부
	var c := Match.new()
	c.start_new_match()
	var c_p1 := c.find_piece_id(0, Rules.PieceType.NUMBER, 1)
	var c_e1 := c.find_piece_id(1, Rules.PieceType.NUMBER, 2)
	c.phase = Match.Phase.MOVE
	c.current_turn = 0
	_force_place(c, c_p1, 2, 4)
	_force_place(c, c_e1, 2, 3)
	c._begin_combat_or_finish(0, c_p1)
	c.declare_item(0, Match.ItemType.PLUS_ONE)
	c.resolve_duels()
	# 두 번째 대결에서 같은 아이템 재사용 시도
	var c_p2 := c.find_piece_id(0, Rules.PieceType.NUMBER, 3)
	var c_e2 := c.find_piece_id(1, Rules.PieceType.NUMBER, 4)
	c.current_turn = 0
	_force_place(c, c_p2, 2, 4)
	_force_place(c, c_e2, 2, 3)
	c._begin_combat_or_finish(0, c_p2)
	var second_use := c.declare_item(0, Match.ItemType.PLUS_ONE)
	_check("같은 아이템 두 번째 사용은 거부됨", not second_use.ok and second_use.error == "item_already_used")

	# 6-D: 블라인드는 숫자에 영향 없이 정체만 숨김(제거돼도 revealed=false 유지)
	var d := Match.new()
	d.start_new_match()
	var d_p := d.find_piece_id(0, Rules.PieceType.NUMBER, 1)
	var d_e := d.find_piece_id(1, Rules.PieceType.NUMBER, 9)
	d.phase = Match.Phase.MOVE
	d.current_turn = 0
	_force_place(d, d_p, 2, 4)
	_force_place(d, d_e, 2, 3)
	d._begin_combat_or_finish(0, d_p)
	d.declare_item(0, Match.ItemType.BLIND)
	d.resolve_duels()
	_check("블라인드 사용해도 숫자 계산 결과는 그대로(1+9=10 → 큰 수 승리, 1 제거)", not d.pieces[d_p].alive)
	_check("블라인드로 숨긴 말은 제거돼도 revealed=false", not d.pieces[d_p].revealed)


# ── 7단계: 60초 타임아웃 ────────────────────────────────────
func _test_stage7_timeout() -> void:
	var a := Match.new()
	a.start_new_match()
	var result_a := a.force_arrange_timeout(0)
	_check("배치 단계 시간초과: 상대 승리", result_a.ok and a.winner == 1 and a.win_reason == "arrange_timeout")

	var b := Match.new()
	b.start_new_match()
	b.auto_arrange(0)
	b.auto_arrange(1)
	b.mark_ready(0)
	b.mark_ready(1)
	b.start_move_phase(0)
	var result_b := b.force_move_timeout()
	_check("이동 단계 시간초과: 상대 승리", result_b.ok and b.winner == 1 and b.win_reason == "move_timeout")
