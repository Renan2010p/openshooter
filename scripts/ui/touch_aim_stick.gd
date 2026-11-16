class_name TouchAimStick
extends Control
## Right-side aim and shoot stick. Touching it enters aim mode automatically;
## pushing past the threshold fires. Deflection controls the look rate.

@export var look_speed := 650.0
@export var fire_threshold := 0.55

var _touch := -1
var _mouse := false
var _screen_path := false
var _knob := Vector2.ZERO
var _firing := false


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
	_firing = false
	Touch.aim_auto = true
	Touch.look_rate = Vector2.ZERO
	Touch.release_fire()
	queue_redraw()


func _drag(relative: Vector2) -> void:
	_knob = (_knob + relative).limit_length(_radius())
	var vec := _knob / maxf(_radius(), 1.0)
	Touch.look_rate = vec * look_speed
	var shooting := vec.length() >= fire_threshold
	if shooting and not _firing:
		_firing = true
		Touch.press_fire()
	elif shooting:
		Touch.fire_held = true
	elif _firing:
		_firing = false
		Touch.release_fire()
	queue_redraw()


func _release() -> void:
	_knob = Vector2.ZERO
	_firing = false
	Touch.aim_auto = false
	Touch.look_rate = Vector2.ZERO
	Touch.release_fire()
	queue_redraw()


func reset() -> void:
	_touch = -1
	_mouse = false
	_screen_path = false
	_release()


func _draw() -> void:
	var center := _center()
	var radius := _radius()
	var ring := Color(0.96, 0.65, 0.14, 0.50)
	if Touch.aim_auto:
		ring.a = 0.92
	if Touch.fire_held or _firing:
		ring = Color(1.0, 0.32, 0.22, 0.95)
	draw_circle(center, radius, Color(0.02, 0.03, 0.04, 0.40))
	draw_arc(center, radius, 0.0, TAU, 48, ring, 2.0, true)
	# Static crosshair inside the base.
	draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(-radius * 0.18, 0), ring, 2.0, true)
	draw_line(center + Vector2(radius * 0.18, 0), center + Vector2(radius * 0.55, 0), ring, 2.0, true)
	draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, -radius * 0.18), ring, 2.0, true)
	draw_line(center + Vector2(0, radius * 0.18), center + Vector2(0, radius * 0.55), ring, 2.0, true)
	draw_circle(center, 2.0, ring)
	# Stick knob.
	var knob := center + _knob
	draw_circle(knob, radius * 0.34, Color(0.02, 0.03, 0.04, 0.35))
	draw_circle(knob, radius * 0.29, Color(0.88, 0.92, 0.97, 0.82))
	draw_arc(knob, radius * 0.29, 0.0, TAU, 36, ring, 2.0, true)
