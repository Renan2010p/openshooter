class_name AnimatedIcon
extends TextureRect
## Gives an icon a subtle idle pulse/tilt and a hover response when its parent
## is a button. Layout is untouched: only scale and rotation are animated.

@export var pulse_amount := 0.035
@export var pulse_speed := 1.5
@export var tilt_degrees := 1.2
## Continuous rotation in degrees per second (0 keeps the icon upright).
@export var spin_speed := 0.0
@export var hover_scale := 1.14

var _t := 0.0
var _spin := 0.0
var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)
	var parent := get_parent()
	if parent is BaseButton:
		parent.mouse_entered.connect(func(): _hover = true)
		parent.mouse_exited.connect(func(): _hover = false)


func _process(delta: float) -> void:
	_t += delta
	_spin += spin_speed * delta
	var amount := 1.0 + sin(_t * pulse_speed) * pulse_amount
	if _hover:
		amount *= hover_scale
	scale = Vector2.ONE * amount
	rotation = deg_to_rad(sin(_t * pulse_speed * 0.6) * tilt_degrees + _spin)
