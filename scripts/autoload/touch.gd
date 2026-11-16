extends Node
## Shared touch input state. The on-screen controls write here and the local
## player consumes the values each frame.

var active := false
var move := Vector2.ZERO
var look := Vector2.ZERO
var fire_held := false
var aim_held := false
## Right aim/shoot stick.
var aim_auto := false
var look_rate := Vector2.ZERO
var crouch := false
var scoreboard_held := false

var _fire_pressed := false
var _jump_pressed := false
var _reload_pressed := false
var _weapon_step := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()


func reset() -> void:
	move = Vector2.ZERO
	look = Vector2.ZERO
	fire_held = false
	aim_held = false
	aim_auto = false
	look_rate = Vector2.ZERO
	crouch = false
	scoreboard_held = false
	_fire_pressed = false
	_jump_pressed = false
	_reload_pressed = false
	_weapon_step = 0


# ------------------------------------------------------------------ look

func consume_look() -> Vector2:
	var delta := look
	look = Vector2.ZERO
	return delta


# ------------------------------------------------------------------ fire / aim

func press_fire() -> void:
	fire_held = true
	_fire_pressed = true


func release_fire() -> void:
	fire_held = false


## True once for each new press (semi-automatic weapons).
func consume_fire() -> bool:
	var pressed := _fire_pressed
	_fire_pressed = false
	return pressed


# ------------------------------------------------------------------ actions

func request_jump() -> void:
	_jump_pressed = true


func consume_jump() -> bool:
	var pressed := _jump_pressed
	_jump_pressed = false
	return pressed


func request_reload() -> void:
	_reload_pressed = true


func consume_reload() -> bool:
	var pressed := _reload_pressed
	_reload_pressed = false
	return pressed


func request_weapon(step: int) -> void:
	_weapon_step = step


func consume_weapon_step() -> int:
	var step := _weapon_step
	_weapon_step = 0
	return step
