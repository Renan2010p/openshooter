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


const LABEL_FONT := preload("res://assets/fonts/Barlow-Bold.ttf")


## Orange FIRE button: tinted disc, orange ring, a crosshair and its label.
## While held it brightens; past the fire threshold it turns solid. A light
## knob shows where the finger has dragged.
func _draw() -> void:
	var center := _center()
	var radius := _radius()
	var fill := Color(1.0, 0.541, 0.122, 0.3)
	if Touch.aim_auto:
		fill.a = 0.45
	if Touch.fire_held or _firing:
		fill.a = 0.75
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 64, Color(1.0, 0.541, 0.122, 1.0), 3.0, true)
	# Crosshair icon.
	var icon := center + Vector2(0, -radius * 0.15)
	var white := Color(1, 1, 1, 0.95)
	draw_arc(icon, 13.0, 0.0, TAU, 32, white, 2.5, true)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(icon + dir * 8.0, icon + dir * 19.0, white, 2.5, true)
	var text := "FIRE · DRAG TO AIM"
	var text_size := LABEL_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(LABEL_FONT, center + Vector2(-text_size.x / 2.0, radius * 0.42), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)
	if _knob != Vector2.ZERO:
		draw_circle(center + _knob, radius * 0.22, Color(1, 1, 1, 0.35))
