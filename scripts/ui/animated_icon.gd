class_name AnimatedIcon
extends TextureRect
## Gives an icon a subtle idle pulse/tilt and a hover response when its parent
## (or any ancestor) is a button. Layout is untouched: only scale and rotation
## are animated.

@export var pulse_amount := 0.035
@export var pulse_speed := 1.5
@export var tilt_degrees := 1.2
## Continuous rotation in degrees per second (0 keeps the icon upright).
@export var spin_speed := 0.0
@export var hover_scale := 1.16
## How fast the hover grows/shrinks (higher is snappier).
@export var hover_response := 14.0

var _t := 0.0
var _spin := 0.0
var _hover := false
var _hover_amount := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)
	# The icon can be nested in a row/card inside the button, so look upward
	# instead of only checking the direct parent.
	var node := get_parent()
	while node != null and not (node is BaseButton):
		node = node.get_parent()
	if node is BaseButton:
		node.mouse_entered.connect(func(): _hover = true)
		node.mouse_exited.connect(func(): _hover = false)


func _process(delta: float) -> void:
	_t += delta
	_spin += spin_speed * delta
	var target := hover_scale if _hover else 1.0
	_hover_amount = lerpf(_hover_amount, target, 1.0 - exp(-hover_response * delta))
	var amount := (1.0 + sin(_t * pulse_speed) * pulse_amount) * _hover_amount
	scale = Vector2.ONE * amount
	rotation = deg_to_rad(sin(_t * pulse_speed * 0.6) * tilt_degrees + _spin)
