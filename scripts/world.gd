class_name World
extends Node3D
## A partida. O servidor decide acertos, dano, mortes, minas e o relógio.

signal leave_requested

const RESPAWN_TIME := 3.0
const END_TIME := 8.0
const DUEL_KILLS := 5
const MINE_ARM := 1.5
const MINE_TRIGGER := 1.6
const MINE_RADIUS := 5.0

var map: GameMap
var players_node: Node3D
var hud: Hud
var local_player: Player
var phase := "play"
var time_left := 300.0
var winner := ""
var _end_t := 0.0
var _state_t := 0.0
var _mine_seq := 0
var mines := {}
var _shake := 0.0
## Teste: o jogador local é controlado pela IA dos bots.
var autoplay := "autoplay" in OS.get_cmdline_user_args() or "--autoplay" in OS.get_cmdline_user_args()


func _ready() -> void:
	map = GameMap.new()
	add_child(map)
	map.build()
	players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	if multiplayer.is_server():
		time_left = float(Net.server_info.get("minutes", 5)) * 60.0
		multiplayer.peer_disconnected.connect(_on_peer_left)
		var colors := [Color(0.8, 0.2, 0.2), Color(0.2, 0.7, 0.3), Color(0.9, 0.6, 0.1), Color(0.5, 0.3, 0.8), Color(0.1, 0.6, 0.7), Color(0.85, 0.85, 0.85)]
		var names := ["Bot Zé", "Bot Bia", "Bot Caio", "Bot Duda", "Bot Léo", "Bot Malu", "Bot Tito", "Bot Nina"]
		for i in int(Net.server_info.get("bots", 0)):
			Net.players[1000 + i] = {"name": names[i % names.size()], "shirt": colors[i % colors.size()], "pants": Color(0.2, 0.2, 0.25),
				"skin": Color(0.9, 0.75, 0.6).darkened(randf() * 0.4), "kills": 0, "deaths": 0, "bot": true}
		Net.broadcast_players()
		_server_spawn(1)
		for i in int(Net.server_info.get("bots", 0)):
			_server_spawn(1000 + i)
	else:
		client_ready.rpc_id(1)


func get_player(id: int) -> Player:
	return players_node.get_node_or_null(str(id)) as Player


func positions_alive(except := -1) -> Array:
	var list := []
	for p in players_node.get_children():
		if p.alive and p.pid != except:
			list.append(p.global_position)
	return list


# ------------------------------------------------------------------ entrada de jogadores

@rpc("any_peer", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	for p in players_node.get_children():
		spawn_player.rpc_id(id, p.pid, p.global_position, p.rotation.y, p.alive)
	match_state.rpc_id(id, time_left, phase, winner)
	_server_spawn(id)
	# A partir de agora os outros podem mandar a posição para ele.
	if Net.players.has(id):
		Net.players[id].ready = true
		Net.broadcast_players()


func _server_spawn(id: int) -> void:
	var pos := map.best_spawn(positions_alive())
	spawn_player.rpc(id, pos, randf() * TAU, true)


@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, pos: Vector3, yaw: float, is_alive: bool) -> void:
	if players_node.has_node(str(id)):
		return
	var p := Player.new()
	p.name = str(id)
	p.pid = id
	p.is_bot = Net.players.get(id, {}).get("bot", false)
	p.world = self
	p.alive = is_alive
	p.position = pos
	p.rotation.y = yaw
	p.set_multiplayer_authority(1 if p.is_bot else id)
	players_node.add_child(p)
	if p.local:
		local_player = p


func _on_peer_left(id: int) -> void:
	remove_player.rpc(id)


@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	var p := get_player(id)
	if p:
		hud.feed("%s saiu da partida" % _name(id))
		p.queue_free()


func _name(id: int) -> String:
	return str(Net.players.get(id, {}).get("name", "Jogador"))


# ------------------------------------------------------------------ tiros

func fire(pid: int, origin: Vector3, dirs: PackedVector3Array, widx: int) -> void:
	if multiplayer.is_server():
		_server_fire(pid, origin, dirs, widx)
	else:
		request_fire.rpc_id(1, origin, dirs, widx)


@rpc("any_peer", "reliable")
func request_fire(origin: Vector3, dirs: PackedVector3Array, widx: int) -> void:
	if multiplayer.is_server():
		_server_fire(multiplayer.get_remote_sender_id(), origin, dirs, widx)


func _server_fire(pid: int, origin: Vector3, dirs: PackedVector3Array, widx: int) -> void:
	var shooter := get_player(pid)
	if shooter == null or not shooter.alive or phase != "play":
		return
	var w := Weapons.get_w(widx)
	if origin.distance_to(shooter.head.global_position) > 3.0:
		origin = shooter.head.global_position
	var space := get_world_3d().direct_space_state
	var points := PackedVector3Array()
	var kinds := PackedByteArray()
	var damage := {}
	for i in mini(dirs.size(), 12):
		var to := origin + dirs[i].normalized() * float(w.get("range", 100.0))
		var q := PhysicsRayQueryParameters3D.create(origin, to, 1 | 4, [shooter.get_rid(), shooter.hitbox.get_rid()])
		var r := space.intersect_ray(q)
		if r.is_empty():
			points.append(to)
			kinds.append(0)
			continue
		points.append(r.position)
		if r.collider.has_meta("pid"):
			var vid: int = r.collider.get_meta("pid")
			var is_head: bool = r.shape == 1
			var amount: float = float(w.damage) * (float(w.get("head", 1.0)) if is_head else 1.0)
			if widx == Weapons.SHOTGUN:
				amount *= clampf(1.2 - origin.distance_to(r.position) / 30.0, 0.3, 1.0)
			var prev: Array = damage.get(vid, [0.0, false])
			damage[vid] = [prev[0] + amount, prev[1] or is_head]
			kinds.append(3 if is_head else 2)
		else:
			kinds.append(1)
	fx_shot.rpc(pid, widx, points, kinds)
	for vid in damage:
		_server_damage(vid, pid, int(round(damage[vid][0])), widx, damage[vid][1])


@rpc("authority", "call_local", "unreliable")
func fx_shot(pid: int, widx: int, points: PackedVector3Array, kinds: PackedByteArray) -> void:
	var p := get_player(pid)
	if p == null:
		return
	if not p.controlled():
		p._fire_fx()
	var w := Weapons.get_w(widx)
	var muzzle := p.muzzle_pos()
	var best := 0
	for i in points.size():
		if not w.get("melee", false) and (i < 2 or randf() < 0.3):
			_tracer(muzzle, points[i])
		if kinds[i] == 1:
			_impact(points[i], Color(0.75, 0.7, 0.6))
		elif kinds[i] >= 2:
			_impact(points[i], Color(0.85, 0.1, 0.1))
		best = maxi(best, kinds[i])
	if p.local and best >= 2:
		hud.hitmarker(best == 3)
		Config.play("headshot" if best == 3 else "hit", -2.0)


func _tracer(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, len)
	mi.mesh = bm
	mi.material_override = Models.mat(Color(1.0, 0.85, 0.4), 0.5, 0.0, 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (a + b) / 2.0
	mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


func _impact(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.12
	mi.mesh = bm
	mi.material_override = Models.mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3.ZERO, 0.35)
	t.tween_callback(mi.queue_free)


# ------------------------------------------------------------------ dano e mortes

func _server_damage(vid: int, attacker: int, amount: int, widx: int, head: bool) -> void:
	var v := get_player(vid)
	if v == null or not v.alive or phase != "play":
		return
	var hp := v.hp - amount
	if hp > 0:
		on_hit.rpc(vid, hp, attacker)
		return
	if Net.players.has(vid):
		Net.players[vid].deaths = int(Net.players[vid].deaths) + 1
	if attacker != vid and Net.players.has(attacker):
		Net.players[attacker].kills = int(Net.players[attacker].kills) + 1
	Net.broadcast_players()
	on_kill.rpc(vid, attacker, widx, head)
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_server_respawn.bind(vid))
	if Net.server_info.get("mode", "") == "duel" and attacker != vid and int(Net.players.get(attacker, {}).get("kills", 0)) >= DUEL_KILLS:
		_end_match()


@rpc("authority", "call_local", "reliable")
func on_hit(vid: int, hp: int, attacker: int) -> void:
	var v := get_player(vid)
	if v == null:
		return
	v.hp = hp
	if v.local:
		hud.damage()
		Config.play("hurt", -6.0)
		var a := get_player(attacker)
		if a:
			hud.damage_from(a.global_position)


@rpc("authority", "call_local", "reliable")
func on_kill(vid: int, attacker: int, widx: int, head: bool) -> void:
	var v := get_player(vid)
	if v:
		v.die()
	var wname: String = Weapons.get_w(widx).name
	print("[abate] %s -> %s (%s%s)" % [_name(attacker), _name(vid), wname, ", cabeça" if head else ""])
	if attacker == vid:
		hud.feed("%s se explodiu" % _name(vid))
	else:
		hud.feed("%s  [%s%s]  %s" % [_name(attacker), wname, " • CABEÇA" if head else "", _name(vid)])
	if v and v.local:
		hud.show_death(_name(attacker) if attacker != vid else "você mesmo", RESPAWN_TIME)
		Config.add_stat("deaths")
	var a := get_player(attacker)
	if a and a.local and attacker != vid:
		Config.play("kill", -4.0)
		hud.toast("Você eliminou %s" % _name(vid))
		Config.add_stat("kills")
		if head:
			Config.add_stat("headshots")


func _server_respawn(vid: int) -> void:
	if get_player(vid) == null or phase != "play":
		return
	on_respawn.rpc(vid, map.best_spawn(positions_alive(vid)), randf() * TAU)


@rpc("authority", "call_local", "reliable")
func on_respawn(vid: int, pos: Vector3, yaw: float) -> void:
	var v := get_player(vid)
	if v:
		v.respawn(pos, yaw)
		if v.local:
			hud.hide_death()


# ------------------------------------------------------------------ minas

func place_mine(pid: int, pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_mine(pid, pos)
	else:
		request_mine.rpc_id(1, pos)


@rpc("any_peer", "reliable")
func request_mine(pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_mine(multiplayer.get_remote_sender_id(), pos)


func _server_mine(pid: int, pos: Vector3) -> void:
	var count := 0
	for id in mines:
		if mines[id].owner == pid:
			count += 1
	if count >= 4:
		return
	_mine_seq += 1
	spawn_mine.rpc(_mine_seq, pid, pos)


@rpc("authority", "call_local", "reliable")
func spawn_mine(id: int, owner: int, pos: Vector3) -> void:
	var n := Models.weapon(Weapons.MINE)
	add_child(n)
	n.global_position = pos + Vector3(0, 0.03, 0.1)
	mines[id] = {"owner": owner, "pos": pos, "t": 0.0, "node": n}
	Config.play_at("beep", pos, -2.0)


func _server_mines(delta: float) -> void:
	for id in mines.keys():
		var m: Dictionary = mines[id]
		m.t += delta
		if m.t < MINE_ARM:
			continue
		for p in players_node.get_children():
			if p.alive and p.pid != m.owner and p.global_position.distance_to(m.pos) < MINE_TRIGGER:
				_server_explode(id)
				break


func _server_explode(id: int) -> void:
	var m: Dictionary = mines[id]
	mine_explode.rpc(id)
	for p in players_node.get_children():
		var d: float = (p.global_position + Vector3(0, 0.8, 0)).distance_to(m.pos)
		if p.alive and d < MINE_RADIUS:
			_server_damage(p.pid, m.owner, int(140.0 * (1.0 - d / MINE_RADIUS)) + 10, Weapons.MINE, false)


@rpc("authority", "call_local", "reliable")
func mine_explode(id: int) -> void:
	if not mines.has(id):
		return
	var m: Dictionary = mines[id]
	m.node.queue_free()
	mines.erase(id)
	Config.play_at("explosion", m.pos, 6.0)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	ball.mesh = sm
	ball.material_override = Models.mat(Color(1.0, 0.55, 0.15), 0.5, 0.0, 4.0)
	add_child(ball)
	ball.global_position = m.pos + Vector3(0, 0.5, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 6.0
	light.omni_range = 10.0
	ball.add_child(light)
	var t := ball.create_tween()
	t.tween_property(ball, "scale", Vector3.ONE * 8.0, 0.25)
	t.parallel().tween_property(light, "light_energy", 0.0, 0.4)
	t.tween_callback(ball.queue_free)
	if local_player and local_player.global_position.distance_to(m.pos) < 15.0:
		_shake = 0.5


# ------------------------------------------------------------------ partida

func _process(delta: float) -> void:
	if _shake > 0.0 and local_player and local_player.cam:
		_shake = maxf(0.0, _shake - delta)
		local_player.cam.h_offset = randf_range(-1, 1) * _shake * 0.15
		local_player.cam.v_offset = randf_range(-1, 1) * _shake * 0.15
	if not multiplayer.is_server():
		if phase == "play":
			time_left = maxf(0.0, time_left - delta)
		return
	_server_mines(delta)
	if phase == "play":
		time_left -= delta
		if time_left <= 0.0:
			_end_match()
	else:
		_end_t -= delta
		if _end_t <= 0.0:
			_restart_match()
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0
		match_state.rpc(time_left, phase, winner)


func _end_match() -> void:
	if phase != "play":
		return
	var best := -1
	var best_id := 0
	for id in Net.players:
		if int(Net.players[id].kills) > best:
			best = int(Net.players[id].kills)
			best_id = id
	winner = _name(best_id) if best > 0 else "ninguém"
	phase = "end"
	_end_t = END_TIME
	match_state.rpc(0.0, phase, winner)
	match_over.rpc(best_id if best > 0 else -1)


@rpc("authority", "call_local", "reliable")
func match_over(winner_id: int) -> void:
	Config.add_stat("matches")
	if winner_id == multiplayer.get_unique_id():
		Config.add_stat("wins")


func _restart_match() -> void:
	phase = "play"
	winner = ""
	time_left = float(Net.server_info.get("minutes", 5)) * 60.0
	for id in Net.players:
		Net.players[id].kills = 0
		Net.players[id].deaths = 0
	Net.broadcast_players()
	for id in mines.keys():
		mine_explode.rpc(id)
	var taken := []
	for p in players_node.get_children():
		var pos := map.best_spawn(taken)
		taken.append(pos)
		on_respawn.rpc(p.pid, pos, randf() * TAU)
	match_state.rpc(time_left, phase, winner)


@rpc("authority", "call_local", "unreliable_ordered")
func match_state(t: float, p: String, w: String) -> void:
	time_left = t
	phase = p
	winner = w


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		hud.toggle_pause()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not hud.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
