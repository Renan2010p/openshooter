class_name World
extends Node3D
## A running match — scenes/game/world.tscn.
## Handles joining and leaving players and bots. The other systems live in its
## children: [Combat] (shots and damage), [MineManager] (mines), [MatchManager]
## (clock and end of match) and the [Hud].

signal leave_requested

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOT_NAMES := ["Bot Joe", "Bot Mia", "Bot Max", "Bot Luna", "Bot Leo", "Bot Nina", "Bot Sam", "Bot Ava"]
const BOT_SHIRTS := [Color(0.8, 0.2, 0.2), Color(0.2, 0.7, 0.3), Color(0.9, 0.6, 0.1), Color(0.5, 0.3, 0.8), Color(0.1, 0.6, 0.7), Color(0.85, 0.85, 0.85)]
const BOT_ID_BASE := 1000

## Match map, chosen by the server (Net.server_info.map) and created in _ready.
var map: GameMap
## Map preloaded by the loading screen, so the match does not load it twice.
var preloaded_map: PackedScene
var preloaded_map_idx := -1
@onready var players: Node3D = $Players
@onready var effects: Node3D = $Effects
@onready var combat: Combat = $Combat
@onready var mines: MineManager = $Mines
@onready var throwables: ThrowableManager = $Throwables
@onready var pickups: PickupManager = $Pickups
@onready var match_manager: MatchManager = $Match
@onready var hud: Hud = $HUD

var local_player: Player
## Test mode: the local player is driven by the bot AI (--autoplay).
var autoplay := "--autoplay" in OS.get_cmdline_user_args()
## Map and mode in use (indices into MapDB and ModeDB).
var map_index := 0
var mode_index := 0


func _ready() -> void:
	map_index = int(Net.server_info.get("map", 0))
	mode_index = int(Net.server_info.get("mode_idx", 0))
	_load_map(map_index)
	hud.setup(self)
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(func(id): remove_player.rpc(id))
		_add_bots(int(Net.server_info.get("bots", 0)))
		server_spawn(1)
		for id in Net.players:
			if Net.players[id].get("bot", false):
				server_spawn(id)
	else:
		client_ready.rpc_id(1)


func _add_bots(count: int) -> void:
	for i in count:
		Net.players[BOT_ID_BASE + i] = {
			"name": BOT_NAMES[i % BOT_NAMES.size()], "shirt": BOT_SHIRTS[i % BOT_SHIRTS.size()],
			"pants": Color(0.2, 0.2, 0.25), "skin": Color(0.9, 0.75, 0.6).darkened(randf() * 0.4),
			"kills": 0, "deaths": 0, "bot": true,
		}
	Net.broadcast_players()


func get_player(id: int) -> Player:
	return players.get_node_or_null(str(id)) as Player


func mode() -> GameModeData:
	return ModeDB.get_mode(mode_index)


## Level in Gun Game (index of the current weapon).
func level_of(pid: int) -> int:
	return int(Net.players.get(pid, {}).get("level", 0))


func loadout_of(pid: int) -> Array[int]:
	return mode().loadout_for(level_of(pid))


func _load_map(idx: int) -> void:
	if map:
		remove_child(map)
		map.queue_free()
	if preloaded_map and idx == preloaded_map_idx:
		map = preloaded_map.instantiate() as GameMap
		preloaded_map = null
	else:
		map = MapDB.instantiate(idx)
	add_child(map)
	move_child(map, 0)


## Applies the vote result everywhere: switches the map (if it changed) and the
## mode, and gives every player the weapons for the new mode.
@rpc("authority", "call_local", "reliable")
func set_match(new_map: int, new_mode: int) -> void:
	mines.clear_all_local()
	throwables.clear_all()
	for fx in effects.get_children():
		fx.queue_free()
	if new_map != map_index:
		map_index = new_map
		_load_map(new_map)
	mode_index = new_mode
	if multiplayer.is_server():
		Net.server_info["map"] = new_map
		Net.server_info["mode_idx"] = new_mode
	for p: Player in players.get_children():
		p.apply_mode()


## Gun Game: a player leveled up and switches weapons.
@rpc("authority", "call_local", "reliable")
func set_level(pid: int, level: int) -> void:
	if Net.players.has(pid):
		Net.players[pid]["level"] = level
	print("[level] %s -> weapon %d" % [player_name(pid), level + 1])
	var p := get_player(pid)
	if p:
		p.apply_mode()


func player_name(id: int) -> String:
	return str(Net.players.get(id, {}).get("name", "Player"))


func alive_positions(except := -1) -> Array:
	var list := []
	for p: Player in players.get_children():
		if p.alive and p.pid != except:
			list.append(p.global_position)
	return list


# ------------------------------------------------------------------ players

## A client finished loading the match: send the current state and spawn it.
@rpc("any_peer", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	for p: Player in players.get_children():
		spawn_player.rpc_id(id, p.pid, p.global_position, p.rotation.y, p.alive)
	match_manager.send_state_to(id)
	server_spawn(id)
	if Net.players.has(id):
		Net.players[id].ready = true
		Net.broadcast_players()


func server_spawn(id: int) -> void:
	spawn_player.rpc(id, map.best_spawn(alive_positions()), randf() * TAU, true)


@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, pos: Vector3, yaw: float, is_alive: bool) -> void:
	if players.has_node(str(id)):
		return
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.pid = id
	p.is_bot = Net.players.get(id, {}).get("bot", false)
	p.world = self
	p.alive = is_alive
	p.position = pos
	p.rotation.y = yaw
	p.set_multiplayer_authority(1 if p.is_bot else id)
	players.add_child(p)
	if p.local:
		local_player = p


@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	var p := get_player(id)
	if p:
		hud.feed("%s left the match" % player_name(id))
		p.queue_free()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
	elif not Touch.active and event is InputEventMouseButton and event.pressed and not hud.paused and match_manager.phase != "vote" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
