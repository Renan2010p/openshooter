@tool
class_name Crosshair
extends Control
## Mira dinâmica: as quatro linhas se afastam conforme a imprecisão da arma.

@export var color := Color(1, 1, 1, 0.9):
	set(v):
		color = v
		queue_redraw()
@export var line_length := 10.0:
	set(v):
		line_length = v
		queue_redraw()
@export var thickness := 2.0:
	set(v):
		thickness = v
		queue_redraw()
@export var gap := 6.0:
	set(v):
		if absf(v - gap) > 0.25:
			gap = v
			queue_redraw()
@export var show_dot := true


func _draw() -> void:
	var c := size / 2.0
	var t := thickness
	draw_rect(Rect2(c + Vector2(-gap - line_length, -t / 2.0), Vector2(line_length, t)), color)
	draw_rect(Rect2(c + Vector2(gap, -t / 2.0), Vector2(line_length, t)), color)
	draw_rect(Rect2(c + Vector2(-t / 2.0, -gap - line_length), Vector2(t, line_length)), color)
	draw_rect(Rect2(c + Vector2(-t / 2.0, gap), Vector2(t, line_length)), color)
	if show_dot:
		draw_rect(Rect2(c - Vector2.ONE, Vector2(2, 2)), color)
