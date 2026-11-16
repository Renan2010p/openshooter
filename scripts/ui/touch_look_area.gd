class_name TouchLookArea
extends Control
## Full-screen touch area used to look around.

var _touch := -1
var _mouse := false
var _screen_path := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_screen_path = true
			accept_event()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_screen_path = false
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		Touch.look += event.relative
		accept_event()
	elif _screen_path:
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _mouse:
		Touch.look += event.relative
		accept_event()


func reset() -> void:
	_touch = -1
	_mouse = false
	_screen_path = false
