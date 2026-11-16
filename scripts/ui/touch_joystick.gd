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


func _draw() -> void:
	var center := _center()
	var radius := _radius()
	draw_circle(center, radius, Color(0.02, 0.03, 0.04, 0.40))
	draw_arc(center, radius, 0.0, TAU, 48, Color(0.96, 0.65, 0.14, 0.40), 2.0, true)
	draw_circle(center, radius * 0.09, Color(0.96, 0.65, 0.14, 0.28))
	var knob := center + _knob
	draw_circle(knob, radius * 0.43, Color(0.02, 0.03, 0.04, 0.35))
	draw_circle(knob, radius * 0.38, Color(0.88, 0.92, 0.97, 0.78))
	draw_arc(knob, radius * 0.38, 0.0, TAU, 36, Color(0.96, 0.65, 0.14, 0.85), 2.0, true)
