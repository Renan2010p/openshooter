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
@export var locker_camera := Vector3(-1.6, 1.5, 23.2)
@export var locker_target := Vector3(-1.75, 1.1, 18.0)
## Lobby view: the character in the middle of the screen, full body.
@export var lobby_camera := Vector3(0.0, 1.45, 22.6)
@export var lobby_target := Vector3(0.0, 1.05, 18.0)
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
