class_name TouchControls
extends Control
## On-screen controls for the Android/mobile port.

signal pause_requested

@onready var joystick: TouchJoystick = %Joystick


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
	joy.offset_right = joy.offset_left + 200.0 * scale
	joy.offset_top = joy.offset_bottom - 200.0 * scale
	modulate.a = clampf(Config.touch_opacity, 0.4, 1.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	if %Crouch.button_pressed != Touch.crouch:
		%Crouch.set_pressed_no_signal(Touch.crouch)
	if %Score.button_pressed != Touch.scoreboard_held:
		%Score.set_pressed_no_signal(Touch.scoreboard_held)


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
