# lobby_board_art.gd — 로비 왼쪽 장식용 오목판
extends Control

const GRID := 15
const PAD := 28.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var size := get_size()
	var side: float = minf(size.x, size.y)
	var origin := Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)
	var board := Rect2(origin, Vector2(side, side))

	# 보드 바탕
	draw_rect(board, Color(0.78, 0.62, 0.38, 0.92), true)
	draw_rect(board.grow(-3.0), Color(0.55, 0.38, 0.20, 0.35), false, 2.0)

	var inner := board.grow(-PAD)
	var step := inner.size.x / float(GRID - 1)

	# 격자
	for i in GRID:
		var t := float(i) * step
		var col := Color(0.18, 0.12, 0.08, 0.75)
		draw_line(
			inner.position + Vector2(t, 0.0),
			inner.position + Vector2(t, inner.size.y),
			col, 1.5
		)
		draw_line(
			inner.position + Vector2(0.0, t),
			inner.position + Vector2(inner.size.x, t),
			col, 1.5
		)

	# 장식 돌 몇 개
	var stones := [
		Vector2i(7, 7),
		Vector2i(6, 8),
		Vector2i(8, 6),
		Vector2i(5, 5),
		Vector2i(9, 9),
		Vector2i(4, 10),
		Vector2i(10, 4),
	]
	var radius := step * 0.38
	for i in stones.size():
		var cell: Vector2i = stones[i]
		var center := inner.position + Vector2(float(cell.x) * step, float(cell.y) * step)
		var is_black := i % 2 == 0
		var fill := Color(0.08, 0.08, 0.09, 0.95) if is_black else Color(0.94, 0.94, 0.92, 0.96)
		draw_circle(center + Vector2(1.5, 2.0), radius, Color(0, 0, 0, 0.25))
		draw_circle(center, radius, fill)
		if not is_black:
			draw_circle(center + Vector2(-radius * 0.25, -radius * 0.25), radius * 0.22, Color(1, 1, 1, 0.55))
