@tool
class_name Crosshair
extends Control
## Dynamic crosshair: the four lines spread apart according to weapon spread.

@export var color := Color(0.95, 0.97, 1.0, 0.95):
	set(v):
		color = v
		queue_redraw()
@export var outline_color := Color(0, 0, 0, 0.65):
	set(v):
		outline_color = v
		queue_redraw()
@export var line_length := 9.0:
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
@export var dot_size := 2.0:
	set(v):
		dot_size = v
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var t := thickness
	var o := 1.0
	var bars := [
		Rect2(c + Vector2(-gap - line_length, -t / 2.0), Vector2(line_length, t)),
		Rect2(c + Vector2(gap, -t / 2.0), Vector2(line_length, t)),
		Rect2(c + Vector2(-t / 2.0, -gap - line_length), Vector2(t, line_length)),
		Rect2(c + Vector2(-t / 2.0, gap), Vector2(t, line_length)),
	]
	# Dark outline keeps the crosshair readable on bright maps.
	for r in bars:
		draw_rect(r.grow(o), outline_color)
	for r in bars:
		draw_rect(r, color)
	if show_dot:
		var dot := Rect2(c - Vector2.ONE * (dot_size / 2.0), Vector2.ONE * dot_size)
		draw_rect(dot.grow(o), outline_color)
		draw_rect(dot, color)


var _flash_tween: Tween
var _base_color := Color.TRANSPARENT


## Briefly tints the crosshair (kill confirmation) and eases back.
func flash(tint: Color, duration := 0.35) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
		color = _base_color
	_base_color = color
	color = tint
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "color", _base_color, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
