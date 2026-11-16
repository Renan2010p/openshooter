class_name MineManager
extends Node3D
## Land mines: the server decides when they explode and who takes damage.

const MINE_SCENE := preload("res://scenes/fx/placed_mine.tscn")
const EXPLOSION_SCENE := preload("res://scenes/fx/explosion.tscn")

@export var arm_time := 1.5
@export var trigger_radius := 1.6
@export var blast_radius := 5.0
@export var max_damage := 150.0
@export var max_per_player := 4

@onready var world: World = get_parent()

## id -> {owner, pos, t, node}
var _mines := {}
var _seq := 0


func place(pid: int, pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_place(pid, pos)
	else:
		request_place.rpc_id(1, pos)


@rpc("any_peer", "reliable")
func request_place(pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_place(multiplayer.get_remote_sender_id(), pos)


func _server_place(pid: int, pos: Vector3) -> void:
	var count := 0
	for id in _mines:
		if _mines[id].owner == pid:
			count += 1
	if count >= max_per_player:
		return
	_seq += 1
	spawn_mine.rpc(_seq, pid, pos)


@rpc("authority", "call_local", "reliable")
func spawn_mine(id: int, owner_id: int, pos: Vector3) -> void:
	var node: Node3D = MINE_SCENE.instantiate()
	add_child(node)
	node.global_position = pos
	_mines[id] = {"owner": owner_id, "pos": pos, "t": 0.0, "node": node}
	Sfx.play_at("beep", pos, -2.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for id in _mines.keys():
		var m: Dictionary = _mines[id]
		m.t += delta
		if m.t < arm_time:
			continue
		for p: Player in world.players.get_children():
			if p.alive and p.pid != m.owner and p.global_position.distance_to(m.pos) < trigger_radius:
				_server_explode(id)
				break


func _server_explode(id: int) -> void:
	var m: Dictionary = _mines[id]
	explode.rpc(id)
	for p: Player in world.players.get_children():
		var d := (p.global_position + Vector3(0, 0.8, 0)).distance_to(m.pos)
		if p.alive and d < blast_radius:
			world.combat.server_damage(p.pid, m.owner, int(max_damage * (1.0 - d / blast_radius)) + 10, WeaponDB.MINE, false)


@rpc("authority", "call_local", "reliable")
func explode(id: int) -> void:
	if not _mines.has(id):
		return
	var m: Dictionary = _mines[id]
	m.node.queue_free()
	_mines.erase(id)
	var fx: Node3D = EXPLOSION_SCENE.instantiate()
	world.effects.add_child(fx)
	fx.global_position = m.pos + Vector3(0, 0.5, 0)
	Sfx.play_at("explosion", m.pos, 6.0)
	var lp := world.local_player
	if lp and lp.global_position.distance_to(m.pos) < 15.0:
		world.hud.shake(0.5)


## Explode every mine (end of match).
func clear_all() -> void:
	for id in _mines.keys():
		explode.rpc(id)


## Removes every mine without exploding (map change; runs on every computer).
func clear_all_local() -> void:
	for id in _mines:
		if is_instance_valid(_mines[id].node):
			_mines[id].node.queue_free()
	_mines.clear()
