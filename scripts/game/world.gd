class_name World
extends Node3D
## Partida em andamento — scenes/game/world.tscn.
## Cuida da entrada e saída de jogadores e bots. Os outros sistemas ficam nos
## filhos: [Combat] (tiros e dano), [MineManager] (minas), [MatchManager]
## (relógio e fim de partida) e o [Hud].

signal leave_requested

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOT_NAMES := ["Bot Zé", "Bot Bia", "Bot Caio", "Bot Duda", "Bot Léo", "Bot Malu", "Bot Tito", "Bot Nina"]
const BOT_SHIRTS := [Color(0.8, 0.2, 0.2), Color(0.2, 0.7, 0.3), Color(0.9, 0.6, 0.1), Color(0.5, 0.3, 0.8), Color(0.1, 0.6, 0.7), Color(0.85, 0.85, 0.85)]
const BOT_ID_BASE := 1000

@onready var map: GameMap = $Map
@onready var players: Node3D = $Players
@onready var effects: Node3D = $Effects
@onready var combat: Combat = $Combat
@onready var mines: MineManager = $Mines
@onready var match_manager: MatchManager = $Match
@onready var hud: Hud = $HUD

var local_player: Player
## Teste: o jogador local é controlado pela IA dos bots (--autoplay).
var autoplay := "--autoplay" in OS.get_cmdline_user_args()


func _ready() -> void:
	hud.world = self
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


func player_name(id: int) -> String:
	return str(Net.players.get(id, {}).get("name", "Jogador"))


func alive_positions(except := -1) -> Array:
	var list := []
	for p: Player in players.get_children():
		if p.alive and p.pid != except:
			list.append(p.global_position)
	return list


# ------------------------------------------------------------------ jogadores

## Um cliente terminou de carregar a partida: manda o estado atual e o faz nascer.
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
		hud.feed("%s saiu da partida" % player_name(id))
		p.queue_free()


# ------------------------------------------------------------------ entrada

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
	elif event is InputEventMouseButton and event.pressed and not hud.paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
