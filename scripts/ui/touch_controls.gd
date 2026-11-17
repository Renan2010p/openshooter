class_name TouchControls
extends Control
## On-screen controls for the Android/mobile port.

signal pause_requested

## Joystick box at 100% size (the base circle is 0.76 of it).
const JOYSTICK_SIZE := 250.0

@onready var joystick: TouchJoystick = %Joystick

var _weapon := -1
var _ammo_text := ""


func _ready() -> void:
	%Jump.pressed.connect(Touch.request_jump)
	%Reload.pressed.connect(Touch.request_reload)
	%Crouch.toggled.connect(func(on: bool): Touch.crouch = on)
	%Prev.pressed.connect(func(): Touch.request_weapon(-1))
	%Next.pressed.connect(func(): Touch.request_weapon(1))
	%Pause.pressed.connect(func(): pause_requested.emit())
	%Score.toggled.connect(func(on: bool): Touch.scoreboard_held = on)
	Config.changed.connect(_apply_config)
	_apply_config()


## Applies the mobile control size and opacity from the settings.
func _apply_config() -> void:
	var scale := clampf(Config.touch_joystick_size, 0.8, 2.0)
	var joy := %Joystick as Control
	joy.offset_right = joy.offset_left + JOYSTICK_SIZE * scale
	joy.offset_top = joy.offset_bottom - JOYSTICK_SIZE * scale
	modulate.a = clampf(Config.touch_opacity, 0.4, 1.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	if %Crouch.button_pressed != Touch.crouch:
		%Crouch.set_pressed_no_signal(Touch.crouch)
	if %Score.button_pressed != Touch.scoreboard_held:
		%Score.set_pressed_no_signal(Touch.scoreboard_held)


## Weapon switcher card: silhouette, "24 / 90" and the name. `mag` < 0
## shows no ammo (melee); `reserve` < 0 shows only the count (equipment).
func set_weapon(weapon: int, mag: int, reserve: int) -> void:
	if weapon != _weapon:
		_weapon = weapon
		var data := WeaponDB.get_data(weapon)
		%WeaponIcon.texture = Hud.weapon_texture(weapon)
		%WeaponName.text = data.display_name.to_upper()
	var text := "∞" if mag < 0 else (str(mag) if reserve < 0 else "%d[font_size=16] / %d[/font_size]" % [mag, reserve])
	if text != _ammo_text:
		_ammo_text = text
		%Ammo.text = text


func reset() -> void:
	if not is_node_ready():
		return
	joystick.reset()
	Touch.reset()
	%Crouch.set_pressed_no_signal(false)
	%Score.set_pressed_no_signal(false)
	%AimStick.reset()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and is_node_ready():
		reset()
