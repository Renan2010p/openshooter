class_name TouchJoystick
extends Control
## On-screen movement stick for the mobile port.

var _touch := -1
var _mouse := false
var _screen_path := false
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y) * 0.38


func _center() -> Vector2:
	return size / 2.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_screen_path = true
			_press()
			accept_event()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_screen_path = false
			_release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		_drag(event.relative)
		accept_event()
	elif _screen_path:
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse = true
			_press()
			accept_event()
		else:
			_mouse = false
			_release()
			accept_event()
	elif event is InputEventMouseMotion and _mouse:
		_drag(event.relative)
		accept_event()


func _press() -> void:
	_knob = Vector2.ZERO
	Touch.move = Vector2.ZERO
	queue_redraw()


## Relative drag works with both emulated mouse and real touch events, independent
## of the coordinate space used by the event.
func _drag(relative: Vector2) -> void:
	_knob = (_knob + relative).limit_length(_radius())
	Touch.move = _knob / maxf(_radius(), 1.0)
	queue_redraw()


func _release() -> void:
	_knob = Vector2.ZERO
	Touch.move = Vector2.ZERO
	queue_redraw()


func reset() -> void:
	_touch = -1
	_mouse = false
	_screen_path = false
	_release()


## Big translucent base with a light ring and a small arrow on top, and a
## solid white knob.
func _draw() -> void:
	var center := _center()
	var radius := _radius()
	draw_circle(center, radius, Color(0.06, 0.07, 0.09, 0.35))
	draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.45), 2.5, true)
	var tip := center + Vector2(0, -radius + 10.0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-7, 8), tip + Vector2(7, 8)]), Color(1, 1, 1, 0.75))
	var knob := center + _knob
	draw_circle(knob + Vector2(0, 2), radius * 0.37, Color(0, 0, 0, 0.18))
	draw_circle(knob, radius * 0.37, Color(0.93, 0.93, 0.91, 0.95))
