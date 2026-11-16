class_name PickupManager
extends Node3D
## Server-side health drops. Killing another player spawns a medkit that any
## living player can collect to regain health.

const PICKUP := preload("res://scenes/fx/health_pickup.tscn")

@export var heal_amount := 35
@export var lifetime := 25.0

@onready var world: World = get_parent()

var _items := {}
var _next_id := 1


func spawn_health(at: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var id := _next_id
	_next_id += 1
	var pos := _floor_position(at)
	_make(id, pos, true)
	if not multiplayer.get_peers().is_empty():
		pickup_spawned.rpc(id, pos)
	get_tree().create_timer(lifetime).timeout.connect(_expire.bind(id))


func _floor_position(at: Vector3) -> Vector3:
	var from := at + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5, 0), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return at + Vector3(0, 0.45, 0)
	return (hit.position as Vector3) + Vector3(0, 0.45, 0)


func _make(id: int, pos: Vector3, server: bool) -> void:
	var pickup := PICKUP.instantiate()
	pickup.id = id
	pickup.server = server
	pickup.amount = heal_amount
	pickup.world = world
	pickup.position = pos
	pickup.taken.connect(_on_taken)
	add_child(pickup)
	_items[id] = pickup


@rpc("authority", "reliable")
func pickup_spawned(id: int, pos: Vector3) -> void:
	if _items.has(id):
		return
	_make(id, pos, false)


@rpc("authority", "reliable")
func pickup_removed(id: int) -> void:
	_remove(id)


func _on_taken(id: int, pid: int) -> void:
	if not multiplayer.is_server() or not _items.has(id):
		return
	var player: Player = world.get_player(pid)
	if player == null or not player.alive or player.hp >= 100:
		return
	world.combat.server_heal(pid, heal_amount)
	if not multiplayer.get_peers().is_empty():
		pickup_removed.rpc(id)
	_remove(id)


func _expire(id: int) -> void:
	if not multiplayer.is_server() or not _items.has(id):
		return
	if not multiplayer.get_peers().is_empty():
		pickup_removed.rpc(id)
	_remove(id)


func _remove(id: int) -> void:
	var pickup = _items.get(id)
	_items.erase(id)
	if pickup and is_instance_valid(pickup):
		pickup.queue_free()
