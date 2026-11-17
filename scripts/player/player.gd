class_name Player
extends CharacterBody3D
## A player (local, remote or bot) — scene scenes/player/player.tscn.
##
## Whoever controls the player (the owner, or the server in the case of bots)
## computes movement and sends the position to everyone else. Shots and damage
## are decided by the server in [Combat]. Weapons live in [WeaponHolder] and the
## AI in [BotBrain].

@export_group("Movement")
@export var walk_speed := 6.0
@export var sprint_speed := 8.5
@export var crouch_speed := 3.0
@export var jump_velocity := 5.4
@export var gravity := 16.0
## Bunny hop: each jump while sprinting adds speed, up to a cap. Releasing
## sprint, crouching, aiming or waiting too long on the ground resets it.
@export var hop_boost := 0.45
@export var hop_max := 2.25
@export var hop_window := 0.45
@export var hop_decay := 4.0
## Ledges up to this height (ramp lips, curbs, low steps) are climbed while
## walking, without having to jump.
@export var step_height := 0.45
@export_group("Aim")
## Mouse sensitivity multiplier while aiming down sights / through a scope.
@export var ads_sensitivity := 0.85
@export var scope_sensitivity := 0.45
## Movement speed cap while aiming down sights.
@export var ads_speed := 4.2
## How fast the view returns after recoil (radians per second, plus a part
## proportional to the current offset).
@export var recoil_recovery := 0.5
@export_group("")
@export var eye_height := 1.72
@export var eye_height_crouched := 1.15

const WALK := 6.0
const SYNC_RATE := 30.0

## Soft aim assist for touch players: narrow cone, line of sight, body aim,
## gentle pull and slowdown. No auto-fire.
const ASSIST_CONE := [0.0, 0.0611, 0.0960]   # radians (3.5 / 5.5 degrees)
const ASSIST_RANGE := [0.0, 25.0, 35.0]      # meters
const ASSIST_PULL := [0.0, 1.25, 2.0]        # pull strength per second
const ASSIST_SLOW := [1.0, 0.72, 0.62]       # look multiplier near a target
const ASSIST_CHEST := 1.05

var pid := 1
var is_bot := false
var local := false
var world: World
var alive := true
var hp := 100
var pitch := 0.0
var crouching := false
var sprinting := false
## Keeps the player in place while still aiming and firing (used by the
## trailer director to stage shots).
var hold := false
## Actor mode (trailer): movement comes from `puppet_input` instead of the
## keyboard or the bot AI; aiming and firing are driven from outside.
var puppet := false
var puppet_input := {"wish": Vector3.ZERO, "jump": false, "crouch": false, "sprint": false}

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
var _hop_bonus := 0.0
var _ground_time := 0.0
## Visual camera kick from recoil; recovers on its own (aim is not changed).
var _punch := Vector2.ZERO
## Recoil offset (x = pitch up, y = yaw), separate from the aim the mouse
## controls: it is added on top of the view and recovers by itself, so firing
## never fights the mouse.
var _recoil := Vector2.ZERO
var _since_shot := 1.0
var _idle_t := 0.0
var _air := 0.0

## Command-line test flags, read once (OS.get_cmdline_user_args() allocates).
static var _args: PackedStringArray = OS.get_cmdline_user_args()
static var _flag_aim: bool = "--aim" in _args
static var _flag_throwtest: bool = "--throwtest" in _args
static var _flag_thirdperson: bool = "--thirdperson" in _args
## "slot_1".."slot_9" built once instead of formatting strings every tick.
static var _slot_actions: Array[StringName] = _make_slot_actions()


static func _make_slot_actions() -> Array[StringName]:
	var list: Array[StringName] = []
	for i in 9:
		list.append(StringName("slot_%d" % (i + 1)))
	return list


func _ready() -> void:
	local = pid == multiplayer.get_unique_id() and not is_bot
	hitbox.set_meta("pid", pid)
	var info := info()
	avatar.setup(info.get("shirt", Color.GRAY), info.get("pants", Color.DIM_GRAY), info.get("skin", Color.BISQUE),
		Cosmetics.sanitize(info.get("look", {})), info.get("hair", Cosmetics.DEFAULT_HAIR))
	weapons.setup(self)
	brain.player = self
	# Distant players are not drawn; the name tag disappears sooner.
	for mi in avatar.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).visibility_range_end = Config.draw_distance()
	name_tag.visibility_range_end = 40.0
	if local:
		camera.fov = Config.fov
		# The camera does not render past the draw distance (less work).
		camera.far = Config.draw_distance() + 5.0
		camera.current = true
		avatar.set_render_layer(2)
		name_tag.visible = false
		if not Touch.active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _flag_thirdperson:
			# Test mode: over-the-shoulder camera to see the character animations.
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
	apply_mode()
	if not alive:
		die()


func info() -> Dictionary:
	return Net.players.get(pid, {})


## Gives the weapons of the current mode (and level, in Gun Game) and draws the
## starting one.
func apply_mode() -> void:
	var mode := world.mode()
	var level := world.level_of(pid)
	weapons.set_loadout(mode.loadout_for(level), _start_weapon(), mode.equipment_refill_seconds)


func _start_weapon() -> int:
	var mode := world.mode()
	var level := world.level_of(pid)
	if is_bot and not mode.is_gun_game():
		# Bots pick a firearm (or the knife) from the mode; no equipment.
		var choices: Array[int] = []
		for i in mode.loadout_for(level):
			if not WeaponDB.get_data(i).is_equipment() and (i != WeaponDB.KNIFE or mode.loadout.size() == 1):
				choices.append(i)
		if not choices.is_empty():
			return choices.pick_random()
	return mode.start_index(level)


## Does this computer decide this player's movement?
func controlled() -> bool:
	return local or (is_bot and multiplayer.is_server())


func add_recoil(amount: float) -> void:
	_since_shot = 0.0
	_recoil.x = minf(_recoil.x + amount, 0.3)
	_recoil.y = clampf(_recoil.y + randf_range(-1.0, 1.0) * amount * 0.3, -0.08, 0.08)
	# Small visual punch that springs back quickly.
	_punch += Vector2(amount * 0.3, randf_range(-1.0, 1.0) * amount * 0.12)


## Recoil recovers once the player stops firing for a moment.
func _recover_recoil(delta: float) -> void:
	_since_shot += delta
	if _recoil == Vector2.ZERO or _since_shot < 0.12:
		return
	var rate := recoil_recovery + _recoil.length() * 5.0
	_recoil = _recoil.move_toward(Vector2.ZERO, rate * delta)


# ------------------------------------------------------------------ health

func die() -> void:
	alive = false
	_hop_bonus = 0.0
	_ground_time = 0.0
	hp = 0
	if local and Touch.active:
		Touch.reset()
	weapons.scoped = false
	weapons.aiming = false
	weapons.reload_left = 0.0
	for s in hitbox.get_children():
		s.set_deferred("disabled", true)
	name_tag.visible = false
	if local:
		view_model.visible = false


func respawn(pos: Vector3, yaw: float) -> void:
	alive = true
	_hop_bonus = 0.0
	_ground_time = 0.0
	hp = 100
	if local and Touch.active:
		Touch.reset()
	weapons.refill()
	global_position = pos
	_net_pos = pos
	rotation.y = yaw
	_net_yaw = yaw
	velocity = Vector3.ZERO
	pitch = 0.0
	_recoil = Vector2.ZERO
	_punch = Vector2.ZERO
	avatar.rotation = Vector3.ZERO
	for s in hitbox.get_children():
		s.set_deferred("disabled", false)
	name_tag.visible = not local
	if local:
		view_model.visible = true
		head.rotation = Vector3.ZERO
	if is_bot:
		brain.reset()
	weapons.equip(_start_weapon(), false, true)


# ------------------------------------------------------------------ network

const FLAG_CROUCH := 1
const FLAG_FLOOR := 2
const FLAG_SPRINT := 4
const FLAG_RELOAD := 8


## State sent 30x/s by whoever controls the player. `flags` carries what the
## animations need (crouching, on the floor, sprinting, reloading).
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
		weapons.equip(widx, false, true)


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


# ------------------------------------------------------------------ loop

func _unhandled_input(event: InputEvent) -> void:
	if Touch.active or not local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not alive:
		return
	if event is InputEventMouseMotion:
		var s := Config.sensitivity * 0.01 * (scope_sensitivity if weapons.scoped else (ads_sensitivity if weapons.aiming else 1.0))
		rotate_y(-event.relative.x * s)
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)
		# The first-person weapon lags slightly behind the mouse.
		_sway += event.relative * 0.0012
	elif event.is_action_pressed("next_weapon"):
		weapons.cycle(1)
	elif event.is_action_pressed("previous_weapon"):
		weapons.cycle(-1)


func _physics_process(delta: float) -> void:
	if local and Touch.active and alive:
		_apply_touch_look(delta)
		_apply_aim_assist(delta)
	weapons.tick(delta)
	# In the Compatibility renderer, every visible light costs an extra pass.
	muzzle_flash.light_energy = maxf(0.0, muzzle_flash.light_energy - delta * 60.0)
	muzzle_flash.visible = muzzle_flash.light_energy > 0.0
	# Shots and throws leave from the head, so it must follow the aim pitch
	# (the local player's head is driven by the first-person camera).
	if not local:
		head.rotation.x = pitch
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


## Animation runs in the render frame, only for players on screen. Distant
## characters are animated fewer times per second; off-screen or beyond the draw
## distance, not at all.
func _process(delta: float) -> void:
	_anim_accum += delta
	if local:
		_throw_test(delta)
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
	if puppet:
		return puppet_input
	if world.autoplay or is_bot:
		return brain.think(get_physics_process_delta_time())
	if Touch.active:
		return _touch_input()
	if _flag_aim:
		# Test mode: hold the right mouse button.
		weapons.aiming = weapons.data().can_aim() and weapons.draw > 0.5
		weapons.scoped = weapons.aiming and weapons.data().has_scope
		return res
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return res
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	res.wish = global_basis * Vector3(iv.x, 0, iv.y)
	res.jump = Input.is_action_pressed("jump")
	res.crouch = Input.is_action_pressed("crouch")
	res.sprint = Input.is_action_pressed("sprint") and iv.y < 0.0
	if Input.is_action_just_pressed("reload"):
		weapons.start_reload()
	for i in mini(WeaponDB.count(), _slot_actions.size()):
		if Input.is_action_just_pressed(_slot_actions[i]):
			weapons.equip_slot(i)
	var w := weapons.data()
	weapons.aiming = w.can_aim() and Input.is_action_pressed("aim") and not weapons.is_reloading() and weapons.draw > 0.5
	weapons.scoped = weapons.aiming and w.has_scope
	var wants_fire := Input.is_action_pressed("fire") if w.automatic else Input.is_action_just_pressed("fire")
	if wants_fire:
		weapons.try_fire()
	return res


## Applies the look delta accumulated by the on-screen touch area.
func _apply_touch_look(delta: float) -> void:
	var look := Touch.consume_look()
	look += Touch.look_rate * delta
	if look == Vector2.ZERO:
		return
	var level := _assist_level()
	if level > 0 and weapons.aiming and _aim_target(level, 1.8) != null:
		look *= ASSIST_SLOW[level]
	var s := Config.sensitivity * 0.0125 * (scope_sensitivity if weapons.scoped else (ads_sensitivity if weapons.aiming else 1.0))
	rotate_y(-look.x * s)
	pitch = clampf(pitch - look.y * s, -1.5, 1.5)
	_sway += look * 0.0012


## 0 when assist is off, the server disallows it or this is not a touch build.
func _assist_level() -> int:
	if not Touch.active:
		return 0
	if not bool(Net.server_info.get("aim_assist", true)):
		return 0
	return clampi(Config.aim_assist, 0, 2)


## Best enemy inside the assist cone with a clear line of sight, or null.
func _aim_target(level: int, cone_scale := 1.0) -> Player:
	if level <= 0 or not weapons.data().is_gun():
		return null
	var cone: float = ASSIST_CONE[level] * cone_scale
	var max_range: float = ASSIST_RANGE[level]
	var origin := head.global_position
	var forward := -head.global_basis.z
	var best: Player = null
	var best_score := 1e9
	var space := get_world_3d().direct_space_state
	for node in world.players.get_children():
		var p := node as Player
		if p == null or p == self or not p.alive:
			continue
		var aim_point := p.global_position + Vector3(0, ASSIST_CHEST, 0)
		var to := aim_point - origin
		var dist := to.length()
		if dist > max_range or dist < 0.5:
			continue
		var angle := forward.angle_to(to / dist)
		if angle > cone:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, aim_point, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var score := angle + dist * 0.002
		if score < best_score:
			best_score = score
			best = p
	return best


## Gently pulls the view toward the chest of a target while aiming.
func _apply_aim_assist(delta: float) -> void:
	var level := _assist_level()
	if level <= 0 or not weapons.aiming or not alive:
		return
	var target := _aim_target(level)
	if target == null:
		return
	var to := target.global_position + Vector3(0, ASSIST_CHEST, 0) - head.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var strength: float = ASSIST_PULL[level]
	var speed := Vector2(velocity.x, velocity.z).length()
	strength *= clampf(1.0 - speed / 8.0, 0.3, 1.0)
	if weapons.data().has_scope:
		strength *= 0.35
	var k := minf(1.0, strength * delta)
	rotation.y = lerp_angle(rotation.y, want_yaw, k)
	pitch = lerpf(pitch, want_pitch, k)


## Input for the mobile controls: analog stick, buttons and touch look.
func _touch_input() -> Dictionary:
	var res := {"wish": Vector3.ZERO, "jump": false, "crouch": Touch.crouch, "sprint": false}
	var mv := Touch.move
	res.wish = global_basis * Vector3(mv.x, 0, mv.y)
	res.jump = Touch.consume_jump()
	res.sprint = mv.length() > 0.9
	if Touch.consume_reload():
		weapons.start_reload()
	var step := Touch.consume_weapon_step()
	if step != 0:
		weapons.cycle(step)
	var w := weapons.data()
	weapons.aiming = w.can_aim() and (Touch.aim_held or Touch.aim_auto) and not weapons.is_reloading() and weapons.draw > 0.5
	weapons.scoped = weapons.aiming and w.has_scope
	var pressed := Touch.consume_fire()
	var wants_fire := Touch.fire_held if w.automatic else pressed
	if wants_fire:
		weapons.try_fire()
	return res


func _move(delta: float) -> void:
	var input := {"wish": Vector3.ZERO, "jump": false}
	if alive and world.match_manager.phase != "end":
		input = _read_input()
	if hold:
		input.wish = Vector3.ZERO
		input.jump = false
	crouching = input.get("crouch", false)
	sprinting = input.get("sprint", false) and not crouching and not weapons.aiming
	var cap := collision.shape as CapsuleShape3D
	cap.height = 1.4 if crouching else 2.0
	collision.position.y = cap.height / 2.0
	var wish: Vector3 = input.wish
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()

	var on_floor := is_on_floor()
	var sprint_input: bool = input.get("sprint", false)
	var moving_forward := wish.length() > 0.5
	var can_hop := sprint_input and not crouching and not weapons.aiming and moving_forward \
		and Vector2(velocity.x, velocity.z).length() > walk_speed * 0.8
	if not sprint_input or crouching or weapons.aiming:
		_hop_bonus = move_toward(_hop_bonus, 0.0, hop_decay * 2.0 * delta)

	if not on_floor:
		velocity.y -= gravity * delta
		_ground_time = 0.0
	elif input.jump and not crouching:
		# Chain hops: land and jump again quickly to keep building speed.
		if can_hop and _ground_time <= hop_window:
			_hop_bonus = minf(_hop_bonus + hop_boost, hop_max)
		elif _ground_time > hop_window:
			_hop_bonus = 0.0
		velocity.y = jump_velocity
		_ground_time = 0.0
	else:
		_ground_time += delta
		if _ground_time > hop_window:
			_hop_bonus = move_toward(_hop_bonus, 0.0, hop_decay * delta)

	var base_speed := crouch_speed if crouching else (sprint_speed if sprint_input else walk_speed)
	if weapons.aiming:
		base_speed = minf(base_speed, ads_speed)
	var speed := base_speed + (_hop_bonus if can_hop else 0.0)

	if on_floor:
		var k := minf(1.0, 12.0 * delta)
		velocity.x = lerpf(velocity.x, wish.x * speed, k)
		velocity.z = lerpf(velocity.z, wish.z * speed, k)
	elif moving_forward:
		# Keep air momentum: only steer toward the wish direction.
		var k := minf(1.0, 2.5 * delta)
		velocity.x = lerpf(velocity.x, wish.x * speed, k)
		velocity.z = lerpf(velocity.z, wish.z * speed, k)
	if not (on_floor and velocity.y <= 0.01 and _try_step_up(delta)):
		move_and_slide()
	if global_position.y < -15.0:
		global_position = world.map.best_spawn([])
		velocity = Vector3.ZERO
	if local and alive and is_on_floor() and not crouching and Vector2(velocity.x, velocity.z).length() > 2.5:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.3 if input.get("sprint", false) else 0.4
			Sfx.play("step", -14.0, randf_range(0.9, 1.1))


## Climbs a low ledge in front of the player (ramp lips, curbs, steps).
## Checks: blocked by a steep surface ahead, room above, free path at the raised
## height and walkable ground to land on. Returns true if the player was moved.
func _try_step_up(delta: float) -> bool:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length() < 0.001:
		return false
	var from := global_transform
	var hit := KinematicCollision3D.new()
	if not test_move(from, motion, hit):
		return false
	# Only real walls/edges; slopes are handled by move_and_slide.
	if hit.get_normal().angle_to(Vector3.UP) <= floor_max_angle + 0.01:
		return false
	var up := Vector3.UP * step_height
	if test_move(from, up):
		return false
	var raised := from.translated(up)
	if test_move(raised, motion):
		return false
	var ahead := raised.translated(motion)
	var ground := KinematicCollision3D.new()
	if not test_move(ahead, -up, ground):
		return false
	if ground.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false
	var target := ahead.origin + ground.get_travel()
	var rise := target.y - global_position.y
	if rise <= 0.01:
		return false
	global_position = target
	velocity.y = 0.0
	apply_floor_snap()
	# The camera eases up instead of popping.
	if local:
		head.position.y -= rise
	return true


func _animate(delta: float) -> void:
	# Speed and direction: from the physics of whoever controls the player, or
	# from the movement received over the network for everyone else.
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


## First-person camera and weapon: step bob, mouse lag, sprint pose, landing,
## drawing and reloading.
func _animate_first_person(delta: float, w: WeaponData, on_floor: bool, reload: float) -> void:
	var k := minf(1.0, delta * 12.0)
	if on_floor and not _was_on_floor:
		_land = 1.0
	_was_on_floor = on_floor
	_land = maxf(0.0, _land - delta * 3.5)
	_air = lerpf(_air, 0.0 if on_floor else 1.0, minf(1.0, delta * 8.0))
	_idle_t += delta
	# Recoil punch: springs back toward zero.
	_punch = _punch.lerp(Vector2.ZERO, minf(1.0, delta * 14.0))
	_recover_recoil(delta)
	var moving := clampf(_speed / WALK, 0.0, 1.4) if on_floor else 0.0
	_bob_t += delta * _speed * (1.25 if sprinting else 1.45)

	# Camera: eye height, gentle bob, landing and side tilt.
	var eye := eye_height_crouched if crouching else eye_height
	if not alive:
		eye = 0.5
		head.rotation.z = lerpf(head.rotation.z, 0.6, minf(1.0, delta * 4.0))
	else:
		head.rotation.z = lerpf(head.rotation.z, -_local_vel.x / walk_speed * 0.02 + _punch.y * 0.3, k)
	var cam_bob := absf(sin(_bob_t)) * 0.035 * moving
	head.position.y = lerpf(head.position.y, eye + cam_bob - _land * 0.12, k)
	head.rotation.x = clampf(pitch + _recoil.x + _punch.x, -1.55, 1.55)
	head.rotation.y = _recoil.y
	var target_fov := Config.fov + (6.0 if sprinting and _speed > 1.0 else 0.0) \
		+ clampf(_hop_bonus * 2.0, 0.0, 4.0)
	if weapons.scoped:
		target_fov = w.scope_fov
	elif weapons.aiming:
		target_fov = Config.fov * w.ads_zoom
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 10.0))

	# Weapon: figure-eight bob, mouse lag, sprint, draw, reload, recoil and swing.
	view_model.visible = alive and not weapons.scoped and not has_meta("third_person")
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, delta * 8.0)).limit_length(0.12)
	var bob := Vector3(sin(_bob_t) * 0.014, -absf(cos(_bob_t)) * 0.012, 0) * moving
	# Breathing: a slow idle drift that fades out while moving.
	var still := 1.0 - clampf(moving, 0.0, 1.0)
	var breath := Vector3(sin(_idle_t * 1.1) * 0.0025, sin(_idle_t * 2.2) * 0.003, 0) * still
	var pos := w.view_position + bob + breath
	var rot := Vector3(-_sway.y * 0.6, -_sway.x * 0.8, -_sway.x * 0.5)
	# Strafing rolls the weapon slightly; in the air it lifts and tilts.
	rot.z += -_local_vel.x / walk_speed * 0.06
	pos.y += _air * 0.02
	rot.x += _air * 0.06
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
	if weapons.aiming:
		# Aiming: weapon centered, sight aligned with the middle of the screen
		# and almost no sway.
		pos = w.ads_position + bob * 0.15 + Vector3(0, -_land * 0.02, 0)
		rot = Vector3(-_sway.y * 0.1, -_sway.x * 0.15, 0)
		pos.z += weapons.kick * 0.03
		rot.x += weapons.kick * 0.05
	else:
		pos.z += weapons.kick * 0.05
		rot.x += weapons.kick * 0.12
	rot += Vector3(-weapons.swing * 0.9, weapons.swing * 0.6, 0)
	var follow := minf(1.0, delta * (22.0 if weapons.aiming else 18.0))
	view_model.position = view_model.position.lerp(pos, follow)
	view_model.rotation = view_model.rotation.lerp(rot, follow)


var _throw_t := 1.0
var _throw_i := 0

## Test mode (--throwtest): throws a grenade, poison and a barrier in sequence.
func _throw_test(delta: float) -> bool:
	if not _flag_throwtest or not alive:
		return false
	_throw_t -= delta
	if _throw_t > 0.0:
		return false
	_throw_t = 1.6
	var order := [WeaponDB.BARRIER, WeaponDB.POISON, WeaponDB.GRENADE]
	weapons.equip(order[_throw_i % order.size()], false, true)
	weapons.cooldown = 0.0
	weapons.ammo[weapons.index][0] = 5
	weapons.try_fire()
	_throw_i += 1
	return true
