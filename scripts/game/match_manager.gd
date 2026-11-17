class_name MatchManager
extends Node
## Session flow, decided by the server:
##   "vote" — everyone votes on the next map (you can walk, but not shoot); the
##            game mode is the server's and never changes;
##   "play" — the match, with a countdown;
##   "end"  — shows the winner and returns to voting.

signal phase_changed(phase: String)
signal votes_changed(map_votes: Dictionary, mode_votes: Dictionary)

## Voting duration in seconds.
@export var vote_time := 20.0
## If everyone votes, voting ends after this many seconds.
@export var vote_rush_time := 3.0
## "Duel Only" (1v1): kills needed to win.
@export var duel_kills := 5
## Seconds the winner is displayed.
@export var end_screen_time := 8.0

@onready var world: World = get_parent()

## Current phase; whoever changes it notifies everyone through phase_changed.
var phase := "play":
	set(v):
		if v != phase:
			phase = v
			phase_changed.emit(v)
var time_left := 300.0
var winner := ""
var map_votes := {}
var mode_votes := {}
## Server: each player's vote {id: [map, mode]}.
var _votes := {}
var _broadcast_t := 0.0


func _ready() -> void:
	if not multiplayer.is_server():
		return
	# The first match uses the map picked when the server was created; the
	# vote only happens between matches (--vote forces one at the start).
	if Net.server_info.get("vote", false):
		start_vote.call_deferred()
	else:
		time_left = duration()


func duration() -> float:
	return float(Net.server_info.get("minutes", 5)) * 60.0


func is_duel_lobby() -> bool:
	return Net.server_info.get("mode", "") == "duel"


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		time_left = maxf(0.0, time_left - delta)
		return
	time_left -= delta
	if time_left <= 0.0:
		match phase:
			"vote":
				_finish_vote()
			"play":
				end_match()
			"end":
				start_vote()
	_broadcast_t -= delta
	if _broadcast_t <= 0.0:
		_broadcast_t = 1.0
		set_state.rpc(time_left, phase, winner)


func send_state_to(peer: int) -> void:
	set_state.rpc_id(peer, time_left, phase, winner)
	vote_state.rpc_id(peer, map_votes, mode_votes)


@rpc("authority", "call_local", "unreliable_ordered")
func set_state(t: float, p: String, w: String) -> void:
	time_left = t
	winner = w
	phase = p


# ------------------------------------------------------------------ voting

func start_vote() -> void:
	_votes.clear()
	map_votes.clear()
	mode_votes.clear()
	phase = "vote"
	winner = ""
	time_left = vote_time
	world.throwables.clear_all()
	set_state.rpc(time_left, phase, winner)
	vote_state.rpc(map_votes, mode_votes)


## A player's map vote. `mode_idx` is ignored: the server's mode is fixed
## (the parameter stays so the network call keeps its shape).
@rpc("any_peer", "call_local", "reliable")
func cast_vote(map_idx: int, mode_idx: int) -> void:
	if not multiplayer.is_server() or phase != "vote":
		return
	var id := multiplayer.get_remote_sender_id()
	_votes[id] = clampi(map_idx, -1, MapDB.count() - 1)
	map_votes.clear()
	for v in _votes.values():
		if v >= 0:
			map_votes[v] = int(map_votes.get(v, 0)) + 1
	vote_state.rpc(map_votes, mode_votes)
	# Everyone voted: no need to wait.
	var complete := 0
	for v in _votes.values():
		if v >= 0:
			complete += 1
	if complete >= Net.humans() and time_left > vote_rush_time:
		time_left = vote_rush_time


@rpc("authority", "call_local", "reliable")
func vote_state(maps: Dictionary, modes: Dictionary) -> void:
	map_votes = maps
	mode_votes = modes
	votes_changed.emit(map_votes, mode_votes)


## Highest vote wins; ties are broken randomly. With no votes, any option
## except `avoid` (the map just played, so maps rotate).
static func tally(votes: Dictionary, count: int, avoid := -1) -> int:
	var best := 0
	for k in votes:
		best = maxi(best, int(votes[k]))
	var options := []
	for i in count:
		if best == 0:
			if i != avoid or count == 1:
				options.append(i)
		elif int(votes.get(i, 0)) == best:
			options.append(i)
	return options.pick_random()


## Next match: the voted map, and the same mode as always.
func _finish_vote() -> void:
	var new_map := tally(map_votes, MapDB.count(), world.map_index)
	print("[vote] next map: %s, mode: %s" % [MapDB.display_name(new_map), ModeDB.get_mode(world.mode_index).display_name])
	world.set_match.rpc(new_map, world.mode_index)
	_begin_match()


func _begin_match() -> void:
	for id in Net.players:
		Net.players[id].kills = 0
		Net.players[id].deaths = 0
		Net.players[id].level = 0
	Net.broadcast_players()
	var taken := []
	for p: Player in world.players.get_children():
		var pos := world.map.best_spawn(taken)
		taken.append(pos)
		world.combat.on_respawn.rpc(p.pid, pos, randf() * TAU)
	phase = "play"
	winner = ""
	time_left = duration()
	set_state.rpc(time_left, phase, winner)


# ------------------------------------------------------------------ match end

## Called by [Combat] for every kill (suicides do not count).
func on_kill_scored(attacker: int, widx: int) -> void:
	var mode := world.mode()
	if mode.is_gun_game():
		var level := world.level_of(attacker)
		# Grenades and other extras count too; the final kill must use the last weapon.
		if level >= mode.progression.size() - 1:
			if widx == WeaponDB.index_of(mode.progression[-1]):
				end_match(attacker)
			return
		world.set_level.rpc(attacker, level + 1)
		Net.players[attacker]["level"] = level + 1
		Net.broadcast_players()
		return
	if is_duel_lobby() and int(Net.players.get(attacker, {}).get("kills", 0)) >= duel_kills:
		end_match(attacker)


func end_match(winner_id := -1) -> void:
	if phase != "play":
		return
	if winner_id < 0:
		var best := 0
		for id in Net.players:
			if int(Net.players[id].kills) > best:
				best = int(Net.players[id].kills)
				winner_id = id
	winner = world.player_name(winner_id) if winner_id >= 0 else "nobody"
	print("[end] winner: %s" % winner)
	phase = "end"
	time_left = end_screen_time
	world.mines.clear_all()
	set_state.rpc(time_left, phase, winner)
	match_over.rpc(winner_id)


@rpc("authority", "call_local", "reliable")
func match_over(winner_id: int) -> void:
	var me := multiplayer.get_unique_id()
	var info: Dictionary = Net.players.get(me, {})
	Config.record_match(int(info.get("kills", 0)), int(info.get("deaths", 0)), winner_id == me)
	Config.add_stat("matches")
	if winner_id == me:
		Config.add_stat("wins")
	Config.award_match_xp(int(info.get("kills", 0)), winner_id == me)
