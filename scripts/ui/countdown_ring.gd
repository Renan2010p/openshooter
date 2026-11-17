class_name CountdownRing
extends Control
## A ring that empties as a countdown runs, with the seconds left in the middle
## (the respawn timer). Set `total` and `left` (seconds).

@export var ring_color := Color("#ff8a1f")
@export var track_color := Color(1, 1, 1, 0.18)
@export var thickness := 6.0
@export var font: Font = preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
@export var font_size := 34

var total := 1.0:
	set(v):
		total = maxf(v, 0.001)
		queue_redraw()
var left := 0.0:
	set(v):
		left = maxf(v, 0.0)
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - thickness
	draw_arc(center, radius, 0.0, TAU, 48, track_color, thickness, true)
	var part := clampf(left / total, 0.0, 1.0)
	if part > 0.0:
		# Starts at the top and runs clockwise.
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * part, 48, ring_color, thickness, true)
	var text := str(ceili(left))
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center + Vector2(-text_size.x / 2.0, font.get_ascent(font_size) - text_size.y / 2.0)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
