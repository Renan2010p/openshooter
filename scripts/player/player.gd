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
var sprinting := false

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
var _local_vel := Vector3.ZERO
var _step_t := 0.0
var _bob_t := 0.0
var _sway := Vector2.ZERO
var _land := 0.0
var _was_on_floor := true
var _net_on_floor := true
var _net_reloading := false
var _net_reload_t := 0.0
var _anim := Avatar.AnimState.new()
var _anim_accum := 0.0


func _ready() -> void:
	local = pid == multiplayer.get_unique_id() and not is_bot
	hitbox.set_meta("pid", pid)
	var info := info()
	avatar.setup(info.get("shirt", Color.GRAY), info.get("pants", Color.DIM_GRAY), info.get("skin", Color.BISQUE))
	weapons.setup(self)
	brain.player = self
	# Jogadores longe não são desenhados; o nome some antes.
	for mi in avatar.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).visibility_range_end = Config.draw_distance()
	name_tag.visibility_range_end = 40.0
	if local:
		camera.fov = Config.fov
		# A câmera não enxerga além da distância de desenho (menos trabalho).
		camera.far = Config.draw_distance() + 5.0
		camera.current = true
		avatar.set_render_layer(2)
		name_tag.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if "--thirdperson" in OS.get_cmdline_user_args():
			# Teste: câmera atrás do ombro para ver as animações do boneco.
			camera.position = Vector3(0.9, 0.3, 3.4)
			camera.cull_mask = 1 | 2
			view_model.visible = false
			set_meta("third_person", true)
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

const FLAG_CROUCH := 1
const FLAG_FLOOR := 2
const FLAG_SPRINT := 4
const FLAG_RELOAD := 8


## Estado enviado 30x/s por quem controla o jogador. `flags` leva o que as
## animações precisam (agachado, no chão, correndo, recarregando).
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector3, yaw: float, p: float, flags: int, widx: int) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = p
	crouching = flags & FLAG_CROUCH != 0
	_net_on_floor = flags & FLAG_FLOOR != 0
	sprinting = flags & FLAG_SPRINT != 0
	var reloading := flags & FLAG_RELOAD != 0
	if reloading and not _net_reloading:
		_net_reload_t = 0.0
	_net_reloading = reloading
	if widx != weapons.index:
		weapons.equip(widx, false)


func _send_state() -> void:
	var flags := 0
	if crouching:
		flags |= FLAG_CROUCH
	if is_on_floor():
		flags |= FLAG_FLOOR
	if sprinting:
		flags |= FLAG_SPRINT
	if weapons.is_reloading():
		flags |= FLAG_RELOAD
	var me := multiplayer.get_unique_id()
	for id in Net.players:
		var other: Dictionary = Net.players[id]
		if id != me and not other.get("bot", false) and other.get("ready", false):
			sync_state.rpc_id(id, global_position, rotation.y, pitch, flags, weapons.index)


# ------------------------------------------------------------------ laço

func _unhandled_input(event: InputEvent) -> void:
	if not local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not alive:
		return
	if event is InputEventMouseMotion:
		var s := Config.sensitivity * 0.01 * (0.25 if weapons.scoped else 1.0)
		rotate_y(-event.relative.x * s)
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)
		# A arma em primeira pessoa "atrasa" um pouco atrás do mouse.
		_sway += event.relative * 0.0012
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


## Animação no quadro de desenho, só para quem aparece na tela. Bonecos longe
## são animados menos vezes por segundo; fora da tela ou além da distância de
## desenho, nem são animados.
func _process(delta: float) -> void:
	_anim_accum += delta
	if local:
		_animate(_anim_accum)
		_anim_accum = 0.0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	if d > Config.draw_distance() or not cam.is_position_in_frustum(global_position + Vector3.UP):
		_anim_accum = minf(_anim_accum, 0.1)
		return
	var interval := 0.0 if d < 20.0 else (1.0 / 30.0 if d < 40.0 else 1.0 / 15.0)
	if _anim_accum < interval:
		return
	_animate(_anim_accum)
	_anim_accum = 0.0


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
	sprinting = input.get("sprint", false) and not crouching and not weapons.scoped
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
	# Velocidade e direção: pela física de quem controla, ou pelo deslocamento
	# recebido da rede para os outros.
	var moved := global_position - _last_pos
	_last_pos = global_position
	var vel := velocity if controlled() else moved / maxf(delta, 0.001)
	vel.y = 0.0
	_local_vel = _local_vel.lerp(global_basis.inverse() * vel, minf(1.0, delta * 10.0))
	_speed = _local_vel.length()
	var on_floor := is_on_floor() if controlled() else _net_on_floor
	var w := weapons.data()
	var reload := -1.0
	if controlled() and weapons.is_reloading():
		reload = clampf(1.0 - weapons.reload_left / w.reload_time, 0.0, 1.0)
	elif not controlled() and _net_reloading:
		_net_reload_t += delta
		reload = clampf(_net_reload_t / maxf(w.reload_time, 0.1), 0.0, 1.0)

	_anim.speed = _speed
	_anim.move = Vector2(_local_vel.x, -_local_vel.z) / maxf(_speed, 0.001)
	_anim.pitch = pitch
	_anim.on_floor = on_floor
	_anim.crouching = crouching
	_anim.sprinting = sprinting and _speed > 1.0
	_anim.alive = alive
	_anim.two_handed = w.two_handed
	_anim.reload = reload
	_anim.draw = weapons.draw
	_anim.kick = weapons.kick
	_anim.swing = weapons.swing
	avatar.animate(delta, _anim)

	if not local:
		return
	_animate_first_person(delta, w, on_floor, reload)


## Câmera e arma em primeira pessoa: balanço do passo, atraso do mouse, pose de
## corrida, aterrissagem, saque e recarga.
func _animate_first_person(delta: float, w: WeaponData, on_floor: bool, reload: float) -> void:
	var k := minf(1.0, delta * 12.0)
	if on_floor and not _was_on_floor:
		_land = 1.0
	_was_on_floor = on_floor
	_land = maxf(0.0, _land - delta * 3.5)
	var moving := clampf(_speed / WALK, 0.0, 1.4) if on_floor else 0.0
	_bob_t += delta * _speed * (1.25 if sprinting else 1.45)

	# Câmera: altura do olho, balanço suave, aterrissagem e inclinação lateral.
	var eye := eye_height_crouched if crouching else eye_height
	if not alive:
		eye = 0.5
		head.rotation.z = lerpf(head.rotation.z, 0.6, minf(1.0, delta * 4.0))
	else:
		head.rotation.z = lerpf(head.rotation.z, -_local_vel.x / walk_speed * 0.02, k)
	var cam_bob := absf(sin(_bob_t)) * 0.035 * moving
	head.position.y = lerpf(head.position.y, eye + cam_bob - _land * 0.12, k)
	head.rotation.x = pitch
	var target_fov := w.scope_fov if weapons.scoped else Config.fov + (6.0 if sprinting and _speed > 1.0 else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 10.0))

	# Arma: passo em "8", atraso do mouse, corrida, saque, recarga, coice e golpe.
	view_model.visible = alive and not weapons.scoped and not has_meta("third_person")
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, delta * 8.0)).limit_length(0.12)
	var bob := Vector3(sin(_bob_t) * 0.014, -absf(cos(_bob_t)) * 0.012, 0) * moving
	var pos := w.view_position + bob
	var rot := Vector3(-_sway.y * 0.6, -_sway.x * 0.8, -_sway.x * 0.5)
	if sprinting and _speed > 1.0:
		pos += Vector3(-0.05, -0.06, 0.03)
		rot += Vector3(-0.25, 0.7, 0.2)
	if crouching:
		pos += Vector3(-0.015, 0.01, 0)
		rot.z += 0.05
	var draw := 1.0 - weapons.draw
	pos.y -= draw * 0.3 + _land * 0.04
	rot.x -= draw * 0.9
	if reload >= 0.0:
		var r := sin(reload * PI)
		pos.y -= r * 0.12
		rot += Vector3(-r * 0.5, r * 0.25, r * 0.45)
	pos.z += weapons.kick * 0.05
	rot.x += weapons.kick * 0.12
	rot += Vector3(-weapons.swing * 0.9, weapons.swing * 0.6, 0)
	view_model.position = view_model.position.lerp(pos, minf(1.0, delta * 18.0))
	view_model.rotation = view_model.rotation.lerp(rot, minf(1.0, delta * 18.0))
