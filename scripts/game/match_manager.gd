class_name MatchManager
extends Node
## Relógio, fim e reinício da partida (decididos pelo servidor).

## Duelo: abates para vencer.
@export var duel_kills := 5
## Segundos mostrando o vencedor antes de recomeçar.
@export var end_screen_time := 8.0

@onready var world: World = get_parent()

var phase := "play"
var time_left := 300.0
var winner := ""
var _end_t := 0.0
var _broadcast_t := 0.0


func _ready() -> void:
	time_left = duration()


func duration() -> float:
	return float(Net.server_info.get("minutes", 5)) * 60.0


func is_duel() -> bool:
	return Net.server_info.get("mode", "") == "duel"


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		if phase == "play":
			time_left = maxf(0.0, time_left - delta)
		return
	if phase == "play":
		time_left -= delta
		if time_left <= 0.0:
			end_match()
	else:
		_end_t -= delta
		if _end_t <= 0.0:
			restart()
	_broadcast_t -= delta
	if _broadcast_t <= 0.0:
		_broadcast_t = 1.0
		set_state.rpc(time_left, phase, winner)


func on_kill_scored(attacker: int) -> void:
	if is_duel() and int(Net.players.get(attacker, {}).get("kills", 0)) >= duel_kills:
		end_match()


func send_state_to(peer: int) -> void:
	set_state.rpc_id(peer, time_left, phase, winner)


func end_match() -> void:
	if phase != "play":
		return
	var best := -1
	var best_id := -1
	for id in Net.players:
		if int(Net.players[id].kills) > best:
			best = int(Net.players[id].kills)
			best_id = id
	winner = world.player_name(best_id) if best > 0 else "ninguém"
	phase = "end"
	_end_t = end_screen_time
	set_state.rpc(0.0, phase, winner)
	match_over.rpc(best_id if best > 0 else -1)


func restart() -> void:
	phase = "play"
	winner = ""
	time_left = duration()
	for id in Net.players:
		Net.players[id].kills = 0
		Net.players[id].deaths = 0
	Net.broadcast_players()
	world.mines.clear_all()
	var taken := []
	for p: Player in world.players.get_children():
		var pos := world.map.best_spawn(taken)
		taken.append(pos)
		world.combat.on_respawn.rpc(p.pid, pos, randf() * TAU)
	set_state.rpc(time_left, phase, winner)


@rpc("authority", "call_local", "unreliable_ordered")
func set_state(t: float, p: String, w: String) -> void:
	time_left = t
	phase = p
	winner = w


@rpc("authority", "call_local", "reliable")
func match_over(winner_id: int) -> void:
	Config.add_stat("matches")
	if winner_id == multiplayer.get_unique_id():
		Config.add_stat("wins")
