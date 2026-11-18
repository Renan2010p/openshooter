class_name SegmentBar
extends Control
## A bar made of slanted segments (the in-match health bar). `value` goes from
## 0 to 1; a partly filled segment is drawn at reduced opacity.

@export var segments := 10:
	set(v):
		segments = maxi(1, v)
		queue_redraw()
@export_range(0.0, 1.0) var value := 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var color := Color("#a9d8ff"):
	set(v):
		color = v
		queue_redraw()
@export var empty_color := Color(1, 1, 1, 0.2)
## Gap between segments (pixels).
@export var gap := 4.0
## Horizontal slant of each segment (pixels the top is shifted right).
@export var slant := 4.0


func _draw() -> void:
	var width := (size.x - gap * (segments - 1) - slant) / segments
	var filled := value * segments
	for i in segments:
		var x := i * (width + gap)
		var fill := clampf(filled - i, 0.0, 1.0)
		var segment_color := empty_color
		if fill >= 0.999:
			segment_color = color
		elif fill > 0.0:
			segment_color = Color(color, color.a * (0.35 + 0.5 * fill))
		var points := PackedVector2Array([
			Vector2(x + slant, 0), Vector2(x + slant + width, 0),
			Vector2(x + width, size.y), Vector2(x, size.y),
		])
		draw_colored_polygon(points, segment_color)
