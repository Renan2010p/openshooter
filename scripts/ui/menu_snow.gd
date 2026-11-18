class_name MenuSnow
extends Control
## Falling snow over the menu background (Christmas edition), behind the
## panels: three layers of 2D particles (far, middle, near) with a slow drift.
##
## Not created on Low quality or on phones (see MenuSnow.wanted()), so it never
## costs frames where they are scarce.

## Flakes per layer: [amount, size min, size max, fall speed, alpha].
const LAYERS := [
	[110, 0.10, 0.16, 26.0, 0.35],
	[60, 0.18, 0.26, 42.0, 0.55],
	[20, 0.30, 0.42, 64.0, 0.75],
]
## Distance a flake falls before it disappears (the menu is 720 px tall,
## more on tall windows: the stretch mode is "expand").
const FALL := 860.0

var _layers: Array[CPUParticles2D] = []


## True when the menu should show the snow.
static func wanted() -> bool:
	return Holiday.ENABLED and Config.quality != Config.Quality.LOW and not Touch.active


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flake := _flake_texture()
	for layer in LAYERS:
		var p := CPUParticles2D.new()
		p.texture = flake
		p.amount = int(layer[0])
		p.lifetime = FALL / (float(layer[3]) * 0.85)
		p.preprocess = p.lifetime
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.direction = Vector2(-0.18, 1.0)
		p.spread = 6.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = float(layer[3]) * 0.85
		p.initial_velocity_max = float(layer[3]) * 1.15
		p.scale_amount_min = float(layer[1])
		p.scale_amount_max = float(layer[2])
		# Sideways sway.
		p.tangential_accel_min = -4.0
		p.tangential_accel_max = 4.0
		p.color = Color(0.94, 0.97, 1.0, float(layer[4]))
		add_child(p)
		_layers.append(p)
	resized.connect(_fit)
	_fit()


## Emission strip just above the top edge, a bit wider than the screen so the
## drift to the left never leaves the right edge empty.
func _fit() -> void:
	for p in _layers:
		p.position = Vector2(size.x * 0.55, -12.0)
		p.emission_rect_extents = Vector2(size.x * 0.6, 4.0)


## Soft round flake, 32 px.
static func _flake_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	return texture
