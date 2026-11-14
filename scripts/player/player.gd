class_name Player
extends CharacterBody3D
## Jogador (local, remoto ou bot) — cena scenes/player/player.tscn.
##
## Quem controla o jogador (o dono, ou o servidor no caso dos bots) calcula o
## movimento e manda a posição para os outros. Tiros e dano são decididos pelo
## servidor em [Combat]. As armas ficam em [WeaponHolder] e a IA em [BotBrain].

@export_group("Movimento")
@export var walk_speed := 6.0
@export var sprint_speed := 8.5
@export var crouch_speed := 3.0
@export var jump_velocity := 5.4
@export var gravity := 16.0
@export var eye_height := 1.72
@export var eye_height_crouched := 1.15

const WALK := 6.0
const SYNC_RATE := 30.0

var pid := 1
var is_bot := false
var local := false
var world: World
var alive := true
var hp := 100
var pitch := 0.0
var crouching := false

@onready var collision: CollisionShape3D = $Collision
@onready var avatar: Avatar = $Avatar
@onready var hitbox: StaticBody3D = $Hitbox
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var view_model: Node3D = $Head/Camera/ViewModel
@onready var muzzle_flash: OmniLight3D = $MuzzleFlash
@onready var name_tag: Label3D = $NameTag
@onready var weapons: WeaponHolder = $Weapons
@onready var brain: BotBrain = $BotBrain

var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _sync_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _step_t := 0.0
var _bob_t := 0.0


func _ready() -> void:
	local = pid == multiplayer.get_unique_id() and not is_bot
	hitbox.set_meta("pid", pid)
	var info := info()
	avatar.setup(info.get("shirt", Color.GRAY), info.get("pants", Color.DIM_GRAY), info.get("skin", Color.BISQUE))
	weapons.setup(self)
	brain.player = self
	if local:
		camera.fov = Config.fov
		camera.current = true
		avatar.set_render_layer(2)
		name_tag.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.queue_free()
		name_tag.text = str(info.get("name", "?"))
		name_tag.modulate = Color(0.8, 0.85, 1.0) if is_bot else Color(1, 0.95, 0.8)
	_net_pos = global_position
	_net_yaw = rotation.y
	_last_pos = global_position
	weapons.equip(WeaponDB.BOT_CHOICES.pick_random() if is_bot else WeaponDB.RIFLE, false)
	if not alive:
		die()


func info() -> Dictionary:
	return Net.players.get(pid, {})


## Este computador decide o movimento deste jogador?
func controlled() -> bool:
	return local or (is_bot and multiplayer.is_server())


func add_recoil(amount: float) -> void:
	pitch = clampf(pitch + amount, -1.5, 1.5)
	rotate_y(randf_range(-1.0, 1.0) * amount * 0.35)


# ------------------------------------------------------------------ vida

func die() -> void:
	alive = false
	hp = 0
	weapons.scoped = false
	weapons.reload_left = 0.0
	for s in hitbox.get_children():
		s.set_deferred("disabled", true)
	name_tag.visible = false
	if local:
		view_model.visible = false


func respawn(pos: Vector3, yaw: float) -> void:
	alive = true
	hp = 100
	weapons.refill()
	global_position = pos
	_net_pos = pos
	rotation.y = yaw
	_net_yaw = yaw
	velocity = Vector3.ZERO
	pitch = 0.0
	avatar.rotation = Vector3.ZERO
	for s in hitbox.get_children():
		s.set_deferred("disabled", false)
	name_tag.visible = not local
	if local:
		view_model.visible = true
		head.rotation = Vector3.ZERO
	if is_bot:
		brain.reset()
		weapons.equip(WeaponDB.BOT_CHOICES.pick_random(), false)
	elif weapons.index == WeaponDB.MINE or weapons.index == WeaponDB.KNIFE:
		weapons.equip(WeaponDB.RIFLE, false)


# ------------------------------------------------------------------ rede

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector3, yaw: float, p: float, crouch: bool, widx: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = p
	crouching = crouch
	if widx != weapons.index:
		weapons.equip(widx, false)


func _send_state() -> void:
	var me := multiplayer.get_unique_id()
	for id in Net.players:
		var other: Dictionary = Net.players[id]
		if id != me and not other.get("bot", false) and other.get("ready", false):
			sync_state.rpc_id(id, global_position, rotation.y, pitch, crouching, weapons.index)


# ------------------------------------------------------------------ laço

func _unhandled_input(event: InputEvent) -> void:
	if not local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not alive:
		return
	if event is InputEventMouseMotion:
		var s := Config.sensitivity * 0.01 * (0.25 if weapons.scoped else 1.0)
		rotate_y(-event.relative.x * s)
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)
	elif event.is_action_pressed("next_weapon"):
		weapons.cycle(1)
	elif event.is_action_pressed("previous_weapon"):
		weapons.cycle(-1)


func _physics_process(delta: float) -> void:
	weapons.tick(delta)
	# No renderizador Compatibility toda luz visível custa uma passada extra.
	muzzle_flash.light_energy = maxf(0.0, muzzle_flash.light_energy - delta * 60.0)
	muzzle_flash.visible = muzzle_flash.light_energy > 0.0
	if controlled():
		_move(delta)
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 1.0 / SYNC_RATE
			_send_state()
	else:
		if global_position.distance_to(_net_pos) > 5.0:
			global_position = _net_pos
		var k := minf(1.0, delta * 15.0)
		global_position = global_position.lerp(_net_pos, k)
		rotation.y = lerp_angle(rotation.y, _net_yaw, k)
		pitch = lerpf(pitch, _net_pitch, k)
	_animate(delta)


func _read_input() -> Dictionary:
	var res := {"wish": Vector3.ZERO, "jump": false, "crouch": false, "sprint": false}
	if world.autoplay or is_bot:
		return brain.think(get_physics_process_delta_time())
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return res
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	res.wish = global_basis * Vector3(iv.x, 0, iv.y)
	res.jump = Input.is_action_pressed("jump")
	res.crouch = Input.is_action_pressed("crouch")
	res.sprint = Input.is_action_pressed("sprint") and iv.y < 0.0
	if Input.is_action_just_pressed("reload"):
		weapons.start_reload()
	for i in WeaponDB.count():
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			weapons.equip(i)
	var w := weapons.data()
	weapons.scoped = w.has_scope and Input.is_action_pressed("aim") and not weapons.is_reloading()
	if Input.is_action_pressed("fire") if w.automatic else Input.is_action_just_pressed("fire"):
		weapons.try_fire()
	return res


func _move(delta: float) -> void:
	var input := {"wish": Vector3.ZERO, "jump": false}
	if alive and world.match_manager.phase == "play":
		input = _read_input()
	crouching = input.get("crouch", false)
	var cap := collision.shape as CapsuleShape3D
	cap.height = 1.4 if crouching else 2.0
	collision.position.y = cap.height / 2.0
	var speed := crouch_speed if crouching else (sprint_speed if input.get("sprint", false) else walk_speed)
	if weapons.scoped:
		speed = minf(speed, 3.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif input.jump and not crouching:
		velocity.y = jump_velocity
	var wish: Vector3 = input.wish
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var accel := 12.0 if is_on_floor() else 2.5
	velocity.x = lerpf(velocity.x, wish.x * speed, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, wish.z * speed, minf(1.0, accel * delta))
	move_and_slide()
	if global_position.y < -15.0:
		global_position = world.map.best_spawn([])
		velocity = Vector3.ZERO
	if local and alive and is_on_floor() and not crouching and Vector2(velocity.x, velocity.z).length() > 2.5:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.3 if input.get("sprint", false) else 0.4
			Sfx.play("step", -14.0, randf_range(0.9, 1.1))


func _animate(delta: float) -> void:
	var moved := global_position - _last_pos
	_last_pos = global_position
	_speed = lerpf(_speed, Vector2(moved.x, moved.z).length() / maxf(delta, 0.001), minf(1.0, delta * 10.0))
	avatar.animate(delta, _speed, pitch, crouching, alive, weapons.swing)
	if not local:
		return
	head.rotation.x = pitch
	var eye := eye_height_crouched if crouching else eye_height
	if not alive:
		eye = 0.5
		head.rotation.z = lerpf(head.rotation.z, 0.6, minf(1.0, delta * 4.0))
	head.position.y = lerpf(head.position.y, eye, minf(1.0, delta * 12.0))
	var w := weapons.data()
	camera.fov = lerpf(camera.fov, w.scope_fov if weapons.scoped else Config.fov, minf(1.0, delta * 14.0))
	view_model.visible = alive and not weapons.scoped
	_bob_t += delta * _speed * 1.4
	var bob := sin(_bob_t) * 0.012 * clampf(_speed / WALK, 0.0, 1.0)
	var dip := 0.0
	if weapons.is_reloading():
		dip = sin(clampf(1.0 - weapons.reload_left / w.reload_time, 0.0, 1.0) * PI)
	var kick := weapons.kick
	var swing := weapons.swing
	view_model.position = w.view_position + Vector3(bob, absf(bob) - dip * 0.15, kick * 0.05)
	view_model.rotation = Vector3(kick * 0.12 - dip * 0.6 - swing * 0.9, swing * 0.6, dip * 0.3)
