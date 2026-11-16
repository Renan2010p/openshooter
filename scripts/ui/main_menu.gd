class_name MainMenu
extends Node3D
## Main menu — scenes/ui/main_menu.tscn. The map rotates in the background and
## each screen is a separate scene in scenes/ui/screens/ (children of %Screens).

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


## Rebuilds the Locker character with the current colors.
func rebuild_avatar() -> void:
	for c in avatar_preview.get_children():
		c.queue_free()
	var a: Avatar = AVATAR_SCENE.instantiate()
	avatar_preview.add_child(a)
	a.setup(Config.shirt, Config.pants, Config.skin)
	_avatar = a
	var gun: Node3D = WeaponDB.get_data(WeaponDB.RIFLE).model.instantiate()
	a.hand.add_child(gun)
	a.foregrip = gun.get_node_or_null("Foregrip")


## Scales the Locker character in and out with the camera transition.
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
		_avatar.idle_preview(delta)
	var in_locker := current_screen() == "Locker"
	if in_locker != _avatar_target:
		_avatar_target = in_locker
		_animate_avatar(in_locker)
	var target_pos: Vector3
	var target_look: Vector3
	if in_locker:
		target_pos = locker_camera
		target_look = locker_target
		avatar_preview.rotation.y += delta * 0.6
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
