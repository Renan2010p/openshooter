class_name MainMenu
extends Node3D
## Main menu — scenes/ui/main_menu.tscn. Each screen is a separate scene in
## scenes/ui/screens/ (children of %Screens).
##
## On the lobby (Home) and the Locker, the camera frames the player's character
## (the "showcase"), standing still and inspecting its weapon; it can be
## turned by dragging. On
## every other screen the camera orbits the background map.

signal host_requested(info: Dictionary)
signal join_requested(ip: String, code: String)
signal quit_requested

const AVATAR_SCENE := preload("res://scenes/player/avatar.tscn")

@export_group("Background camera")
@export var orbit_radius := 30.0
@export var orbit_height := 12.0
@export var orbit_speed := 0.05
@export var locker_camera := Vector3(1.6, 1.5, 23.2)
@export var locker_target := Vector3(1.75, 1.1, 18.0)
## Lobby view: the character in the middle of the screen, full body.
@export var lobby_camera := Vector3(0.1, 1.24, 20.75)
@export var lobby_target := Vector3(0.1, 1.24, 18.0)
## Seconds after a drag before the character turns back to face the camera.
@export var lobby_return_delay := 2.5
## How quickly the camera glides between the orbit and the Locker view.
@export var camera_smoothing := 2.4

## Message shown on open (for example "The connection to the server was lost.").
var message := ""

@onready var camera: Camera3D = $Camera
@onready var avatar_preview: Node3D = $AvatarPreview
@onready var screens: Control = %Screens
@onready var status_label: Label = %Status

var _current: MenuScreen
var _avatar: Avatar
var _t := 0.0
var _status_seq := 0
var _look_target := Vector3(0, 1.2, 0)
var _avatar_target := false
var _dragging := false
var _since_drag := 100.0

## Part of the character the Locker camera frames: "head", "body", "legs" or
## "feet" (set by the Locker tabs).
var locker_focus := "body"
## For each focus: the point on the character (avatar at AvatarPreview) and
## how close the camera gets (1.0 = the full-body Locker view).
const LOCKER_FOCUS := {
	"head": [Vector3(0, 1.86, 0), 0.72],
	"body": [Vector3(0, 1.0, 0), 1.0],
	"legs": [Vector3(0, 0.56, 0), 0.7],
	"feet": [Vector3(0, 0.21, 0), 0.55],
}

## The Locker's Back tab turns the character around to show its back
## (turned a little, so the back item is seen at an angle).
var locker_show_back := false
const BACK_VIEW_OFFSET := PI - 0.5

## Showcase (Home and Locker), drawn like the approved mockup, back to front:
## the map, dark gradients, a dot grid, a huge outlined title, a slanted
## orange slab, and the character on top of all of it. The character is
## rendered by its own camera into a transparent viewport (_avatar_view), so
## the 2D layers can sit between the map and the character.
const SHOWCASE_FONT := preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
## Render layer only the showcase camera sees (bit value).
const AVATAR_LAYER := 2
const SHADE_SHADER := """
shader_type canvas_item;
// Mockup: linear-gradient(90deg, .94 0%, .6 30%, .08 52%, .55 78%, .9 100%),
// a 200 px dark fade at the bottom, and the map at 62% brightness.
uniform vec4 color : source_color = vec4(0.043, 0.047, 0.063, 1.0);
float across(float x) {
	if (x < 0.30) return mix(0.94, 0.60, x / 0.30);
	if (x < 0.52) return mix(0.60, 0.08, (x - 0.30) / 0.22);
	if (x < 0.78) return mix(0.08, 0.55, (x - 0.52) / 0.26);
	return mix(0.55, 0.90, (x - 0.78) / 0.22);
}
void fragment() {
	float bottom = clamp((UV.y - 0.722) / 0.278, 0.0, 1.0) * 0.92;
	float a = 1.0 - (1.0 - 0.38) * (1.0 - across(UV.x)) * (1.0 - bottom);
	COLOR = vec4(color.rgb, a);
}
"""
const DOTS_SHADER := """
shader_type canvas_item;
// 9 px grid of soft dots, fading out toward the bottom-left.
uniform vec2 box_size = vec2(420.0, 300.0);
void fragment() {
	vec2 px = UV * box_size;
	vec2 cell = mod(px, 9.0) - 4.5;
	float dot = 1.0 - smoothstep(1.2, 1.6, length(cell));
	float fade = clamp((UV.x + (1.0 - UV.y)) - 0.9, 0.0, 1.0);
	COLOR = vec4(1.0, 1.0, 1.0, 0.14 * dot * fade);
}
"""
var _showcase: Control
var _showcase_title: Label
var _showcase_slab: Panel
var _avatar_view: SubViewport
var _avatar_camera: Camera3D
var _layer_t := 0.0

## Screens that show the character.
const SHOWCASE_SCREENS := ["Home", "Locker"]
## Radians per pixel when dragging the character.
const DRAG_TURN := 0.012
var _avatar_tween: Tween


func _ready() -> void:
	# A different background map every time the menu opens.
	var map := MapDB.instantiate(MapDB.random_index())
	add_child(map)
	move_child(map, 0)
	for s in screens.get_children():
		if s is MenuScreen:
			s.menu = self
			s.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.start_listening()
	set_status(message)
	rebuild_avatar()
	_build_showcase()
	avatar_preview.rotation.y = PI  # facing the lobby camera
	avatar_preview.visible = false
	avatar_preview.scale = Vector3.ONE * 0.01
	show_screen("Home")


func _exit_tree() -> void:
	Net.stop_listening()


## Shows a screen by node name (Home, Modes, Browser, Private, Create, Locker,
## Settings, Stats). `arg` is forwarded to MenuScreen.enter().
func show_screen(screen_name: String, arg: Variant = null) -> void:
	if _current:
		_current.leave()
		_current.visible = false
	_current = screens.get_node(screen_name) as MenuScreen
	_current.visible = true
	_current.enter(arg)
	var content := _current.get_node_or_null("Content") as Control
	if content:
		UiMotion.slide_in(content)
		UiMotion.stagger(content)


func current_screen() -> String:
	return _current.name if _current else ""


func set_status(text: String, ok := false) -> void:
	_status_seq += 1
	var seq := _status_seq
	status_label.text = text
	status_label.visible = text != ""
	status_label.theme_type_variation = &"StatusOk" if ok else &"StatusError"
	if text != "":
		UiMotion.pop_in(status_label, 0.16)
		get_tree().create_timer(6.0).timeout.connect(func():
			if seq == _status_seq:
				status_label.text = ""
				status_label.visible = false)


func request_host(info: Dictionary) -> void:
	host_requested.emit(info)


func request_join(ip: String, code := "") -> void:
	set_status("Connecting to %s..." % ip, true)
	join_requested.emit(ip, code)


func request_quit() -> void:
	quit_requested.emit()


## Rebuilds the showcase character with the current colors.
func rebuild_avatar() -> void:
	if is_instance_valid(_avatar):
		_avatar.queue_free()
	var a: Avatar = AVATAR_SCENE.instantiate()
	avatar_preview.add_child(a)
	a.setup(Config.shirt, Config.pants, Config.skin, Config.look, Config.hair)
	_avatar = a
	var gun: Node3D = WeaponDB.get_data(WeaponDB.RIFLE).model.instantiate()
	a.hand.add_child(gun)
	a.foregrip = gun.get_node_or_null("Foregrip")
	a.held_weapon = gun
	_put_on_avatar_layer(a)


func _build_showcase() -> void:
	# The character's own camera: same place as the main camera every frame,
	# sees only AVATAR_LAYER, transparent background.
	_avatar_view = SubViewport.new()
	_avatar_view.transparent_bg = true
	_avatar_view.msaa_3d = get_viewport().msaa_3d
	_avatar_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_avatar_camera = Camera3D.new()
	_avatar_camera.cull_mask = AVATAR_LAYER
	_avatar_camera.current = true
	_avatar_view.add_child(_avatar_camera)
	add_child(_avatar_view)
	camera.cull_mask &= ~AVATAR_LAYER

	_showcase = Control.new()
	_showcase.name = "Showcase"
	_showcase.set_anchors_preset(Control.PRESET_FULL_RECT)
	_showcase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_showcase.visible = false
	var root := $UI/Root as Control
	root.add_child(_showcase)
	# Under the Atmosphere layer (its footer stays on top; its shades are
	# hidden while the showcase shows).
	root.move_child(_showcase, $UI/Root/Atmosphere.get_index())

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.material = _shader_material(SHADE_SHADER)
	_showcase.add_child(shade)

	var dots := ColorRect.new()
	dots.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dots.offset_left = -420.0
	dots.offset_bottom = 300.0
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.material = _shader_material(DOTS_SHADER)
	_showcase.add_child(dots)

	# Outline-only title, 210 px, lines at 0.82 of the size, top at 150 px.
	_showcase_title = Label.new()
	_showcase_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_showcase_title.offset_top = 150.0 - 30.0
	_showcase_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_showcase_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_showcase_title.add_theme_font_override("font", SHOWCASE_FONT)
	_showcase_title.add_theme_font_size_override("font_size", 210)
	_showcase_title.add_theme_constant_override("line_spacing", -int(SHOWCASE_FONT.get_height(210) - 210 * 0.82))
	_showcase_title.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	_showcase_title.add_theme_color_override("font_outline_color", Color(1.0, 0.541, 0.122, 0.42))
	_showcase_title.add_theme_constant_override("outline_size", 4)
	_showcase.add_child(_showcase_title)

	# Slab: 240 x 560 at (520, 120), slanted 14 degrees, orange left edge.
	_showcase_slab = Panel.new()
	_showcase_slab.position = Vector2(520, 120)
	_showcase_slab.size = Vector2(240, 560)
	_showcase_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slab_style := StyleBoxFlat.new()
	slab_style.bg_color = Color(1.0, 0.541, 0.122, 0.16)
	slab_style.border_color = Color(1.0, 0.541, 0.122, 1.0)
	slab_style.border_width_left = 3
	slab_style.skew = Vector2(tan(deg_to_rad(14.0)), 0.0)
	_showcase_slab.add_theme_stylebox_override("panel", slab_style)
	_showcase.add_child(_showcase_slab)

	var character := TextureRect.new()
	character.set_anchors_preset(Control.PRESET_FULL_RECT)
	character.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character.stretch_mode = TextureRect.STRETCH_SCALE
	character.texture = _avatar_view.get_texture()
	_showcase.add_child(character)


func _shader_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


## Puts every mesh of the character on AVATAR_LAYER (only the showcase
## camera draws it; the light still casts its shadow on the map).
func _put_on_avatar_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = AVATAR_LAYER
	for child in node.get_children():
		_put_on_avatar_layer(child)


## Makes the character react to a new Locker item in `slot` with an emote.
func avatar_react(slot: String) -> void:
	if not is_instance_valid(_avatar):
		return
	match slot:
		"hat", "hair", "face":
			_avatar.play_emote("touch_head")
		"feet", "legs":
			_avatar.play_emote("look_down")
		_:
			_avatar.play_emote("show_off")


## Lets the character turn to its resting angle now, even right after a drag
## (used when the Locker switches tabs).
func turn_to_rest() -> void:
	_since_drag = lobby_return_delay


## Drag anywhere outside the buttons to turn the character. Touch screens
## send these as mouse events too (Godot's default "emulate mouse from touch").
func _unhandled_input(event: InputEvent) -> void:
	if not _avatar_target:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		avatar_preview.rotation.y += event.relative.x * DRAG_TURN
		_since_drag = 0.0


## Scales the showcase character in and out with the camera transition.
func _animate_avatar(show: bool) -> void:
	if _avatar_tween and _avatar_tween.is_valid():
		_avatar_tween.kill()
	if show:
		avatar_preview.visible = true
		avatar_preview.scale = Vector3.ONE * 0.01
		_avatar_tween = create_tween()
		_avatar_tween.tween_property(avatar_preview, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_avatar_tween = create_tween()
		_avatar_tween.tween_property(avatar_preview, "scale", Vector3.ONE * 0.01, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_avatar_tween.tween_callback(func(): avatar_preview.visible = false)


func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_avatar):
		_avatar.menu_preview(delta)
	var screen := current_screen()
	var showcase := screen in SHOWCASE_SCREENS
	if showcase != _avatar_target:
		_avatar_target = showcase
		_dragging = false
		_animate_avatar(showcase)
	if is_instance_valid(_showcase):
		_showcase.visible = showcase
		$UI/Root/Atmosphere/Tint.visible = not showcase
		$UI/Root/Atmosphere/LeftShade.visible = not showcase
		$UI/Root/Atmosphere/Vignette.visible = not showcase
		var locker := screen == "Locker"
		_showcase_title.text = "LOCKER" if locker else (
			"WINTER\nWARFARE" if Holiday.ENABLED else "OPEN\nSHOOTER")
		# In the Locker the character stands left of centre (panel on the right).
		_showcase_title.offset_right = -340.0 if locker else 0.0
		_showcase_slab.visible = not locker
		_layer_t -= delta
		if _layer_t <= 0.0:
			_layer_t = 0.5
			_put_on_avatar_layer(avatar_preview)
	_since_drag += delta
	var target_pos: Vector3
	var target_look: Vector3
	if screen == "Locker":
		# Same view direction as the full-body view, moved toward the focused
		# part and closer, so that part stays where the character was.
		var focus: Array = LOCKER_FOCUS.get(locker_focus, LOCKER_FOCUS["body"])
		var point: Vector3 = avatar_preview.global_position + focus[0]
		var zoom: float = focus[1]
		var body_center := avatar_preview.global_position + LOCKER_FOCUS["body"][0]
		target_pos = point + (locker_camera - body_center) * zoom
		target_look = point + (locker_target - body_center) * zoom
	elif screen == "Home":
		target_pos = lobby_camera
		target_look = lobby_target
	if showcase:
		# The character stands still in its pose. After a drag it turns
		# smoothly back to the resting angle (its back, for the Back tab).
		# Facing the camera: the character looks down -Z, so the angle that
		# points -Z at the camera is atan2(-dx, -dz).
		var to_camera := target_pos - avatar_preview.global_position
		var rest := atan2(-to_camera.x, -to_camera.z)
		if screen == "Locker" and locker_show_back:
			rest += BACK_VIEW_OFFSET
		if not _dragging and _since_drag > lobby_return_delay:
			var back := 1.0 - exp(-2.0 * delta)
			avatar_preview.rotation.y = lerp_angle(avatar_preview.rotation.y, rest, back)
	else:
		var a := _t * orbit_speed
		var bob := sin(_t * 0.35) * 0.55
		target_pos = Vector3(sin(a) * orbit_radius, orbit_height + bob, cos(a) * orbit_radius)
		target_look = Vector3(0, 1.2, 0)
	# Smooth both ways, so leaving the Locker glides back instead of teleporting.
	var k := 1.0 - exp(-camera_smoothing * delta)
	camera.global_position = camera.global_position.lerp(target_pos, k)
	_look_target = _look_target.lerp(target_look, k)
	camera.look_at(_look_target)
	if is_instance_valid(_avatar_camera):
		# Same pixel size as the window, so the character is as sharp as the map.
		var pixels := Vector2i(get_viewport().get_visible_rect().size * get_viewport().get_final_transform().get_scale())
		if _avatar_view.size != pixels:
			_avatar_view.size = pixels
		_avatar_camera.global_transform = camera.global_transform
		_avatar_camera.fov = camera.fov
