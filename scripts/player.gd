class_name Player
extends CharacterBody3D
## Jogador (local, remoto ou bot). Quem controla manda a posição para os outros;
## os tiros são conferidos pelo servidor.

const WALK := 6.0
const SPRINT := 8.5
const CROUCH := 3.0
const JUMP := 5.4
const GRAVITY := 16.0
const EYE := 1.72
const EYE_CROUCH := 1.15

var pid := 1
var is_bot := false
var local := false
var world: World
var alive := true
var hp := 100
var pitch := 0.0
var crouching := false
var weapon_idx := Weapons.RIFLE
var ammo := []
var fire_cd := 0.0
var reload_t := 0.0
var scoped := false
var kick := 0.0
var swing := 0.0
var bob_t := 0.0
var step_t := 0.0
var dead_t := 0.0

var head: Node3D
var cam: Camera3D
var vm: Node3D
var vm_gun: Node3D
var parts := {}
var tp_gun: Node3D
var hitbox: StaticBody3D
var body_shape: CollisionShape3D
var capsule: CapsuleShape3D
var hit_shapes: Array[CollisionShape3D] = []
var tag: Label3D
var flash: OmniLight3D

var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var _sync_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0

var bot_wp := Vector3.ZERO
var bot_enemy: Player
var bot_scan := 0.0
var bot_react := 0.0
var bot_strafe := 1.0
var bot_strafe_t := 0.0
var bot_stuck := 0.0
var bot_err := Vector2.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.3
	local = pid == multiplayer.get_unique_id() and not is_bot

	body_shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.0
	body_shape.shape = capsule
	body_shape.position.y = 1.0
	add_child(body_shape)

	var info: Dictionary = Net.players.get(pid, {})
	parts = Models.avatar(info.get("shirt", Color.GRAY), info.get("pants", Color.DIM_GRAY), info.get("skin", Color.BISQUE))
	add_child(parts.root)

	hitbox = StaticBody3D.new()
	hitbox.collision_layer = 4
	hitbox.collision_mask = 0
	hitbox.set_meta("pid", pid)
	add_child(hitbox)
	for spec in [[Vector3(0.8, 1.62, 0.5), Vector3(0, 0.81, 0)], [Vector3(0.56, 0.56, 0.56), Vector3(0, 1.9, 0)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[0]
		cs.shape = bs
		cs.position = spec[1]
		hitbox.add_child(cs)
		hit_shapes.append(cs)

	head = Node3D.new()
	head.position.y = EYE
	add_child(head)

	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.4)
	flash.omni_range = 4.0
	flash.light_energy = 0.0
	flash.visible = false
	flash.shadow_enabled = false
	add_child(flash)

	if local:
		cam = Camera3D.new()
		cam.fov = Config.fov
		cam.near = 0.03
		cam.cull_mask = 1 | 4
		head.add_child(cam)
		cam.current = true
		Models.set_layer(parts.root, 2)
		vm = Node3D.new()
		vm.scale = Vector3.ONE * 0.7
		cam.add_child(vm)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		tag = Label3D.new()
		tag.text = str(info.get("name", "?"))
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position.y = 2.45
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.outline_size = 10
		tag.modulate = Color(1, 0.95, 0.8) if not is_bot else Color(0.8, 0.85, 1.0)
		add_child(tag)
	net_pos = global_position
	net_yaw = rotation.y
	_last_pos = global_position
	_refill()
	if is_bot:
		weapon_idx = [Weapons.PISTOL, Weapons.RIFLE, Weapons.RIFLE, Weapons.SHOTGUN, Weapons.SNIPER].pick_random()
	_equip(weapon_idx, false)
	if not alive:
		die()


func controlled() -> bool:
	return local or (is_bot and multiplayer.is_server())


# ------------------------------------------------------------------ armas

func _refill() -> void:
	ammo.clear()
	for w in Weapons.LIST:
		ammo.append([int(w.get("mag", 0)), int(w.get("reserve", 0))])


func _equip(idx: int, sound := true) -> void:
	weapon_idx = clampi(idx, 0, Weapons.LIST.size() - 1)
	scoped = false
	reload_t = 0.0
	fire_cd = maxf(fire_cd, 0.25)
	if tp_gun:
		tp_gun.queue_free()
	tp_gun = Models.weapon(weapon_idx)
	tp_gun.position = Vector3(0, -0.72, -0.05)
	tp_gun.rotation.x = -PI / 2.0
	parts.arm_r.add_child(tp_gun)
	if local:
		Models.set_layer(tp_gun, 2)
		if vm_gun:
			vm_gun.queue_free()
		vm_gun = Node3D.new()
		vm.add_child(vm_gun)
		var g := Models.weapon(weapon_idx)
		vm_gun.add_child(g)
		var skin: Color = Net.players.get(pid, {}).get("skin", Config.skin)
		var shirt: Color = Net.players.get(pid, {}).get("shirt", Config.shirt)
		Models.box(vm_gun, Vector3(0.09, 0.09, 0.32), Vector3(0.02, -0.07, 0.2), Models.mat(skin))
		Models.box(vm_gun, Vector3(0.11, 0.11, 0.3), Vector3(0.03, -0.09, 0.45), Models.mat(shirt))
		if weapon_idx in [Weapons.RIFLE, Weapons.SHOTGUN, Weapons.SNIPER]:
			Models.box(vm_gun, Vector3(0.08, 0.08, 0.4), Vector3(-0.12, -0.06, -0.12), Models.mat(skin), Vector3(0, -35, 0))
		Models.bake(vm_gun)
		Models.set_layer(vm_gun, 4)
		for mi in vm_gun.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if sound:
			Config.play("switch", -6.0)


func current_spread() -> float:
	var w := Weapons.get_w(weapon_idx)
	var s: float = w.get("spread", 0.0)
	if w.get("scope", false):
		s = 0.0015 if scoped else s
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 1.0:
		s += 0.015 * clampf(hv / WALK, 0.0, 1.5)
	if not is_on_floor():
		s += 0.04
	if crouching:
		s *= 0.6
	return s


func muzzle_pos() -> Vector3:
	var g := vm_gun.get_child(0) if local and vm_gun and vm_gun.get_child_count() > 0 else tp_gun
	if g == null:
		return head.global_position
	return g.to_global(g.get_meta("muzzle", Vector3.ZERO))


func try_fire() -> void:
	if not alive or fire_cd > 0.0 or reload_t > 0.0 or world.phase != "play":
		return
	var w := Weapons.get_w(weapon_idx)
	if w.get("mine", false):
		if ammo[weapon_idx][0] <= 0:
			if local:
				world.hud.toast("Você não tem mais minas nesta vida.")
			return
		var from := global_position + (-global_basis.z) * 1.0 + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if r.is_empty():
			return
		ammo[weapon_idx][0] -= 1
		fire_cd = w.rate
		world.place_mine(pid, r.position)
		return
	if not w.get("melee", false):
		if ammo[weapon_idx][0] <= 0:
			if local:
				Config.play("empty", -4.0)
			fire_cd = 0.25
			start_reload()
			return
		ammo[weapon_idx][0] -= 1
	fire_cd = w.rate
	var origin := head.global_position
	var basis := head.global_basis
	var sp := current_spread()
	var dirs := PackedVector3Array()
	for i in int(w.get("pellets", 1)):
		var d := -basis.z + basis.x * randf_range(-sp, sp) + basis.y * randf_range(-sp, sp)
		if is_bot:
			d += basis.x * (bot_err.x + randf_range(-0.02, 0.02)) + basis.y * (bot_err.y + randf_range(-0.02, 0.02))
		dirs.append(d.normalized())
	_fire_fx()
	world.fire(pid, origin, dirs, weapon_idx)
	var rec: float = w.get("recoil", 0.0)
	if local:
		pitch = clampf(pitch + rec, -1.5, 1.5)
		rotate_y(randf_range(-1.0, 1.0) * rec * 0.35)
	if not w.get("melee", false) and ammo[weapon_idx][0] <= 0:
		start_reload()


func _fire_fx() -> void:
	var w := Weapons.get_w(weapon_idx)
	if w.get("melee", false):
		swing = 1.0
		Config.play_at("knife", head.global_position, -2.0)
		return
	kick = 1.0
	if local:
		Config.play(w.sound, -3.0, randf_range(0.95, 1.05))
	else:
		Config.play_at(w.sound, head.global_position, 2.0, randf_range(0.95, 1.05))
	flash.global_position = muzzle_pos()
	flash.light_energy = 3.0


func start_reload() -> void:
	var w := Weapons.get_w(weapon_idx)
	if w.get("melee", false) or w.get("mine", false) or reload_t > 0.0 or not alive:
		return
	var a: Array = ammo[weapon_idx]
	if a[0] >= int(w.mag) or a[1] <= 0:
		return
	reload_t = w.reload
	scoped = false
	if local:
		Config.play("reload", -6.0)


func _finish_reload() -> void:
	var w := Weapons.get_w(weapon_idx)
	var a: Array = ammo[weapon_idx]
	var take := mini(int(w.mag) - a[0], a[1])
	a[0] += take
	a[1] -= take


# ------------------------------------------------------------------ vida

func die() -> void:
	alive = false
	hp = 0
	scoped = false
	reload_t = 0.0
	dead_t = 0.0
	for s in hit_shapes:
		s.set_deferred("disabled", true)
	if tag:
		tag.visible = false
	if vm:
		vm.visible = false


func respawn(pos: Vector3, yaw: float) -> void:
	alive = true
	hp = 100
	_refill()
	global_position = pos
	net_pos = pos
	rotation.y = yaw
	net_yaw = yaw
	velocity = Vector3.ZERO
	pitch = 0.0
	parts.root.rotation = Vector3.ZERO
	parts.root.position = Vector3.ZERO
	for s in hit_shapes:
		s.set_deferred("disabled", false)
	if tag:
		tag.visible = true
	if vm:
		vm.visible = true
	if local:
		head.rotation = Vector3.ZERO
	if is_bot:
		bot_wp = Vector3.ZERO
		_equip([Weapons.PISTOL, Weapons.RIFLE, Weapons.RIFLE, Weapons.SHOTGUN, Weapons.SNIPER].pick_random(), false)
	elif weapon_idx == Weapons.MINE or weapon_idx == Weapons.KNIFE:
		_equip(Weapons.RIFLE, false)


# ------------------------------------------------------------------ rede

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector3, yaw: float, p: float, crouch: bool, widx: int) -> void:
	net_pos = pos
	net_yaw = yaw
	net_pitch = p
	crouching = crouch
	if widx != weapon_idx:
		_equip(widx, false)


# ------------------------------------------------------------------ laço

func _unhandled_input(event: InputEvent) -> void:
	if not local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and alive:
		var s := Config.sensitivity * 0.01 * (0.25 if scoped else 1.0)
		rotate_y(-event.relative.x * s)
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed and alive:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_equip(posmod(weapon_idx - 1, Weapons.LIST.size()))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_equip(posmod(weapon_idx + 1, Weapons.LIST.size()))


func _physics_process(delta: float) -> void:
	fire_cd = maxf(0.0, fire_cd - delta)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()
	# No renderizador Compatibility toda luz visível custa uma passada extra
	# em cada objeto que ela toca, mesmo com brilho 0. Por isso ela some de verdade.
	flash.light_energy = maxf(0.0, flash.light_energy - delta * 60.0)
	flash.visible = flash.light_energy > 0.0
	if controlled():
		_move(delta)
		_sync_t -= delta
		if _sync_t <= 0.0:
			_sync_t = 1.0 / 30.0
			var me := multiplayer.get_unique_id()
			for id in Net.players:
				var info: Dictionary = Net.players[id]
				if id != me and not info.get("bot", false) and info.get("ready", false):
					sync_state.rpc_id(id, global_position, rotation.y, pitch, crouching, weapon_idx)
	else:
		if global_position.distance_to(net_pos) > 5.0:
			global_position = net_pos
		global_position = global_position.lerp(net_pos, minf(1.0, delta * 15.0))
		rotation.y = lerp_angle(rotation.y, net_yaw, minf(1.0, delta * 15.0))
		pitch = lerpf(pitch, net_pitch, minf(1.0, delta * 15.0))
	_animate(delta)


func _move(delta: float) -> void:
	var wish := Vector3.ZERO
	var want_jump := false
	var want_crouch := false
	var want_sprint := false
	if alive and world.phase == "play":
		if local and world.autoplay:
			var r := _bot_think(delta)
			wish = r.wish
			want_jump = r.jump
		elif local and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			wish = global_basis * Vector3(iv.x, 0, iv.y)
			want_jump = Input.is_action_pressed("jump")
			want_crouch = Input.is_action_pressed("crouch")
			want_sprint = Input.is_action_pressed("sprint") and iv.y < 0.0
			if Input.is_action_just_pressed("reload"):
				start_reload()
			for i in 6:
				if Input.is_action_just_pressed("slot%d" % (i + 1)):
					_equip(i)
			var w := Weapons.get_w(weapon_idx)
			scoped = w.get("scope", false) and Input.is_action_pressed("aim") and reload_t <= 0.0
			var trigger := Input.is_action_pressed("fire") if w.get("auto", false) else Input.is_action_just_pressed("fire")
			if trigger:
				try_fire()
		elif is_bot:
			var r := _bot_think(delta)
			wish = r.wish
			want_jump = r.jump
	crouching = want_crouch
	capsule.height = 1.4 if crouching else 2.0
	body_shape.position.y = capsule.height / 2.0
	var speed := CROUCH if crouching else (SPRINT if want_sprint else WALK)
	if scoped:
		speed = minf(speed, 3.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump and not crouching:
		velocity.y = JUMP
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target := wish * speed
	var accel := 12.0 if is_on_floor() else 2.5
	velocity.x = lerpf(velocity.x, target.x, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, target.z, minf(1.0, accel * delta))
	move_and_slide()
	if global_position.y < -15.0:
		global_position = world.map.best_spawn([])
		velocity = Vector3.ZERO
	if local and alive and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 2.5 and not crouching:
		step_t -= delta
		if step_t <= 0.0:
			step_t = 0.3 if want_sprint else 0.4
			Config.play("step", -14.0, randf_range(0.9, 1.1))


func _animate(delta: float) -> void:
	var moved := global_position - _last_pos
	_last_pos = global_position
	_speed = lerpf(_speed, Vector2(moved.x, moved.z).length() / maxf(delta, 0.001), minf(1.0, delta * 10.0))
	bob_t += delta * _speed * 1.4
	var swing_legs := sin(bob_t) * clampf(_speed / WALK, 0.0, 1.0) * 0.7
	parts.leg_l.rotation.x = swing_legs
	parts.leg_r.rotation.x = -swing_legs
	parts.arm_r.rotation = Vector3(PI / 2.0 + pitch - swing * 0.8, 0, 0)
	parts.arm_l.rotation = Vector3(PI / 2.0 + pitch, -0.45, 0)
	parts.head.rotation.x = pitch * 0.7
	parts.root.position.y = -0.5 if crouching and alive else 0.0
	if not alive:
		dead_t += delta
		parts.root.rotation.x = lerpf(parts.root.rotation.x, PI / 2.0, minf(1.0, delta * 8.0))
	if local:
		head.rotation.x = pitch
		var target_eye := EYE_CROUCH if crouching else EYE
		if not alive:
			target_eye = 0.5
			head.rotation.z = lerpf(head.rotation.z, 0.6, minf(1.0, delta * 4.0))
		head.position.y = lerpf(head.position.y, target_eye, minf(1.0, delta * 12.0))
		var w := Weapons.get_w(weapon_idx)
		cam.fov = lerpf(cam.fov, 20.0 if scoped else Config.fov, minf(1.0, delta * 14.0))
		vm.visible = alive and not scoped
		kick = maxf(0.0, kick - delta * 8.0)
		swing = maxf(0.0, swing - delta * 4.0)
		var bob := sin(bob_t) * 0.012 * clampf(_speed / WALK, 0.0, 1.0)
		var reload_dip := 0.0
		if reload_t > 0.0:
			reload_dip = sin(clampf(1.0 - reload_t / float(w.get("reload", 1.0)), 0.0, 1.0) * PI)
		vm.position = Vector3(0.2 + bob, -0.21 + absf(bob) - reload_dip * 0.15, -0.36 + kick * 0.05)
		vm.rotation = Vector3(kick * 0.12 - reload_dip * 0.6 - swing * 0.9, swing * 0.6, reload_dip * 0.3)


# ------------------------------------------------------------------ bots

func _bot_think(delta: float) -> Dictionary:
	var res := {"wish": Vector3.ZERO, "jump": false}
	bot_scan -= delta
	if bot_scan <= 0.0:
		bot_scan = 0.25
		var e := _bot_find_enemy()
		if e != bot_enemy:
			bot_enemy = e
			bot_react = randf_range(0.3, 0.6)
			bot_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 0.035
	if bot_enemy and bot_enemy.alive:
		var target := bot_enemy.global_position + Vector3(0, 1.3, 0)
		var to := target - head.global_position
		var want_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, minf(1.0, delta * 6.0))
		pitch = lerpf(pitch, atan2(to.y, Vector2(to.x, to.z).length()), minf(1.0, delta * 6.0))
		bot_react -= delta
		bot_err *= 1.0 - delta * 0.6
		if bot_react <= 0.0 and absf(angle_difference(rotation.y, want_yaw)) < 0.1:
			try_fire()
		bot_strafe_t -= delta
		if bot_strafe_t <= 0.0:
			bot_strafe = [-1.0, 1.0].pick_random()
			bot_strafe_t = randf_range(0.6, 1.6)
		var dist := to.length()
		var fwd := 0.0
		if weapon_idx == Weapons.SHOTGUN or weapon_idx == Weapons.PISTOL:
			fwd = 1.0 if dist > 7.0 else 0.0
		elif dist > 28.0:
			fwd = 1.0
		elif dist < 7.0:
			fwd = -0.6
		res.wish = global_basis * Vector3(bot_strafe * 0.8, 0, -fwd)
	else:
		if bot_wp == Vector3.ZERO or Vector2(bot_wp.x - global_position.x, bot_wp.z - global_position.z).length() < 1.5:
			bot_wp = world.map.waypoints.pick_random()
		var to := bot_wp - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 4.0))
		pitch = lerpf(pitch, 0.0, minf(1.0, delta * 4.0))
		res.wish = -global_basis.z
		if Vector2(velocity.x, velocity.z).length() < 1.0:
			bot_stuck += delta
		else:
			bot_stuck = maxf(0.0, bot_stuck - delta)
		res.jump = bot_stuck > 0.4
		if bot_stuck > 1.8:
			bot_wp = world.map.waypoints.pick_random()
			bot_stuck = 0.0
		if ammo[weapon_idx][0] < int(Weapons.get_w(weapon_idx).get("mag", 0)) / 2:
			start_reload()
	return res


func _bot_find_enemy() -> Player:
	var best: Player = null
	var best_d := 65.0
	for p in world.players_node.get_children():
		if p == self or not p.alive:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d and _can_see(p):
			best = p
			best_d = d
	return best


func _can_see(p: Player) -> bool:
	var q := PhysicsRayQueryParameters3D.create(head.global_position, p.global_position + Vector3(0, 1.5, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
