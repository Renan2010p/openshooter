class_name ThrowableManager
extends Node3D
## Grenades, poison and barriers. Every computer shows the flight; the server
## decides when and where each item activates, who takes damage and when a
## barrier falls.

const PROJECTILE := preload("res://scenes/fx/thrown_projectile.tscn")
const EXPLOSION := preload("res://scenes/fx/explosion.tscn")
const CLOUD := preload("res://scenes/fx/poison_cloud.tscn")
const WALL := preload("res://scenes/fx/barrier_wall.tscn")

## Health of each barrier.
@export var barrier_health := 300.0
## Seconds between each poison cloud damage tick.
@export var poison_tick := 0.5
## Maximum throw speed (anti-cheat).
@export var max_speed := 30.0

@onready var world: World = get_parent()

var _seq := 0
var _projectiles := {}
## Server: active clouds {pos, owner, widx, left, tick}.
var _clouds: Array[Dictionary] = []
var _barriers := {}


# ------------------------------------------------------------------ throwing

func throw(pid: int, widx: int, origin: Vector3, velocity: Vector3) -> void:
	if multiplayer.is_server():
		_server_throw(pid, widx, origin, velocity)
	else:
		request_throw.rpc_id(1, widx, origin, velocity)


@rpc("any_peer", "reliable")
func request_throw(widx: int, origin: Vector3, velocity: Vector3) -> void:
	if multiplayer.is_server():
		_server_throw(multiplayer.get_remote_sender_id(), widx, origin, velocity)


func _server_throw(pid: int, widx: int, origin: Vector3, velocity: Vector3) -> void:
	var p := world.get_player(pid)
	if p == null or not p.alive or world.match_manager.phase != "play":
		return
	if not WeaponDB.get_data(widx).is_throwable():
		return
	if origin.distance_to(p.head.global_position) > 3.0:
		origin = p.head.global_position
	_seq += 1
	spawn_projectile.rpc(_seq, pid, widx, origin, velocity.limit_length(max_speed))
	get_tree().create_timer(WeaponDB.get_data(widx).fuse).timeout.connect(_server_activate.bind(_seq))


@rpc("authority", "call_local", "reliable")
func spawn_projectile(id: int, owner_id: int, widx: int, origin: Vector3, velocity: Vector3) -> void:
	var n: Node3D = PROJECTILE.instantiate()
	add_child(n)
	n.setup(id, owner_id, widx, origin, velocity)
	_projectiles[id] = n


# ------------------------------------------------------------------ activation

func _server_activate(id: int) -> void:
	var n: Node3D = _projectiles.get(id)
	if not is_instance_valid(n):
		return
	var w := WeaponDB.get_data(n.weapon_idx)
	var pos := n.global_position
	activate.rpc(id, pos, n.throw_yaw())
	match w.throw_effect:
		WeaponData.ThrowEffect.FRAG:
			_server_blast(pos, n.owner_id, n.weapon_idx, w)
		WeaponData.ThrowEffect.POISON:
			_clouds.append({"pos": pos, "owner": n.owner_id, "widx": n.weapon_idx, "left": w.effect_duration, "tick": 0.0})
		WeaponData.ThrowEffect.BARRIER:
			get_tree().create_timer(w.effect_duration).timeout.connect(func(): if _barriers.has(id): remove_barrier.rpc(id))


@rpc("authority", "call_local", "reliable")
func activate(id: int, pos: Vector3, yaw: float) -> void:
	var n: Node3D = _projectiles.get(id)
	var widx: int = n.weapon_idx if is_instance_valid(n) else WeaponDB.GRENADE
	if is_instance_valid(n):
		n.queue_free()
	_projectiles.erase(id)
	var w := WeaponDB.get_data(widx)
	match w.throw_effect:
		WeaponData.ThrowEffect.FRAG:
			var fx: Node3D = EXPLOSION.instantiate()
			world.effects.add_child(fx)
			fx.global_position = pos + Vector3(0, 0.4, 0)
			Sfx.play_at("explosion", pos, 6.0)
			var lp := world.local_player
			if lp and lp.global_position.distance_to(pos) < 15.0:
				world.hud.shake(0.5)
		WeaponData.ThrowEffect.POISON:
			var cloud: Node3D = CLOUD.instantiate()
			cloud.duration = w.effect_duration
			cloud.radius = w.effect_radius
			world.effects.add_child(cloud)
			cloud.global_position = pos
			Sfx.play_at("explosion", pos, -8.0, 2.2)
		WeaponData.ThrowEffect.BARRIER:
			var wall: StaticBody3D = WALL.instantiate()
			wall.barrier_id = id
			wall.health = barrier_health
			world.effects.add_child(wall)
			wall.global_position = _ground_below(pos)
			wall.rotation.y = yaw
			_barriers[id] = wall
			Sfx.play_at("reload", pos, 2.0, 0.7)


func _ground_below(pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 4.0, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() else pos


## Grenade damage: falls off with distance; also breaks nearby barriers.
func _server_blast(pos: Vector3, owner_id: int, widx: int, w: WeaponData) -> void:
	for p: Player in world.players.get_children():
		var d := (p.global_position + Vector3(0, 0.9, 0)).distance_to(pos)
		if p.alive and d < w.effect_radius:
			world.combat.server_damage(p.pid, owner_id, int(w.damage * (1.0 - d / w.effect_radius)) + 10, widx, false)
	for id in _barriers.keys():
		var wall: Node3D = _barriers[id]
		if is_instance_valid(wall) and wall.global_position.distance_to(pos) < w.effect_radius:
			damage_barrier(id, w.damage)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _clouds.is_empty():
		return
	for c in _clouds.duplicate():
		c.left -= delta
		c.tick -= delta
		if c.tick <= 0.0:
			c.tick = poison_tick
			var w := WeaponDB.get_data(c.widx)
			for p: Player in world.players.get_children():
				var off: Vector3 = p.global_position - c.pos
				if p.alive and Vector2(off.x, off.z).length() < w.effect_radius and absf(off.y) < 3.0:
					world.combat.server_damage(p.pid, c.owner, int(w.damage), c.widx, false)
		if c.left <= 0.0:
			_clouds.erase(c)


# ------------------------------------------------------------------ barriers

## Called by the server when a shot or explosion hits a barrier.
func damage_barrier(id: int, amount: float) -> void:
	var wall = _barriers.get(id)
	if not is_instance_valid(wall):
		return
	wall.health -= amount
	if wall.health <= 0.0:
		remove_barrier.rpc(id)
	else:
		barrier_hit.rpc(id)


@rpc("authority", "call_local", "unreliable")
func barrier_hit(id: int) -> void:
	var wall = _barriers.get(id)
	if is_instance_valid(wall):
		wall.flash()


@rpc("authority", "call_local", "reliable")
func remove_barrier(id: int) -> void:
	var wall = _barriers.get(id)
	_barriers.erase(id)
	if is_instance_valid(wall):
		wall.collapse()


## End of match or map change: clear everything from the ground.
func clear_all() -> void:
	for id in _projectiles.keys():
		if is_instance_valid(_projectiles[id]):
			_projectiles[id].queue_free()
	_projectiles.clear()
	for id in _barriers.keys():
		if is_instance_valid(_barriers[id]):
			_barriers[id].queue_free()
	_barriers.clear()
	_clouds.clear()
