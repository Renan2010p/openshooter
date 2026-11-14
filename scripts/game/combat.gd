class_name Combat
extends Node
## Tiros, dano, mortes e renascimento. Só o servidor decide acertos; os outros
## recebem o resultado e mostram os efeitos.

const TRACER := preload("res://scenes/fx/tracer.tscn")
const IMPACT := preload("res://scenes/fx/impact.tscn")

## Camadas de física: 1 = mundo, 3 = hitboxes dos jogadores.
const SHOT_MASK := 1 | 4

@export var respawn_time := 3.0
@export var world_impact_color := Color(0.75, 0.7, 0.6)
@export var body_impact_color := Color(0.85, 0.1, 0.1)

@onready var world: World = get_parent()


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
	var shooter := world.get_player(pid)
	if shooter == null or not shooter.alive or world.match_manager.phase != "play":
		return
	var w := WeaponDB.get_data(widx)
	if origin.distance_to(shooter.head.global_position) > 3.0:
		origin = shooter.head.global_position
	var space := world.get_world_3d().direct_space_state
	var points := PackedVector3Array()
	var kinds := PackedByteArray()
	var damage := {}
	for i in mini(dirs.size(), 16):
		var to := origin + dirs[i].normalized() * w.max_range
		var q := PhysicsRayQueryParameters3D.create(origin, to, SHOT_MASK, [shooter.get_rid(), shooter.hitbox.get_rid()])
		var r := space.intersect_ray(q)
		if r.is_empty():
			points.append(to)
			kinds.append(0)
			continue
		points.append(r.position)
		if r.collider.has_meta("pid"):
			var vid: int = r.collider.get_meta("pid")
			var is_head: bool = r.shape == 1
			var amount := w.damage * (w.headshot_multiplier if is_head else 1.0)
			if w.damage_falloff:
				amount *= clampf(1.2 - origin.distance_to(r.position) / 30.0, 0.3, 1.0)
			var prev: Array = damage.get(vid, [0.0, false])
			damage[vid] = [prev[0] + amount, prev[1] or is_head]
			kinds.append(3 if is_head else 2)
		else:
			kinds.append(1)
	fx_shot.rpc(pid, widx, points, kinds)
	for vid in damage:
		server_damage(vid, pid, int(round(damage[vid][0])), widx, damage[vid][1])


## Efeitos de um disparo para todos: rastro, impactos e marcador de acerto.
@rpc("authority", "call_local", "unreliable")
func fx_shot(pid: int, widx: int, points: PackedVector3Array, kinds: PackedByteArray) -> void:
	var p := world.get_player(pid)
	if p == null:
		return
	if not p.controlled():
		p.weapons.play_fire_fx()
	var w := WeaponDB.get_data(widx)
	var muzzle := p.weapons.muzzle_position()
	var best := 0
	for i in points.size():
		if not w.is_melee() and (i < 2 or randf() < 0.3):
			var t := TRACER.instantiate()
			world.effects.add_child(t)
			t.setup(muzzle, points[i])
		if kinds[i] >= 1:
			var fx := IMPACT.instantiate()
			world.effects.add_child(fx)
			fx.setup(points[i], world_impact_color if kinds[i] == 1 else body_impact_color)
		best = maxi(best, kinds[i])
	if p.local and best >= 2:
		world.hud.hitmarker(best == 3)
		Sfx.play("headshot" if best == 3 else "hit", -2.0)


# ------------------------------------------------------------------ dano e mortes

func server_damage(vid: int, attacker: int, amount: int, widx: int, head: bool) -> void:
	var v := world.get_player(vid)
	if v == null or not v.alive or world.match_manager.phase != "play":
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
	get_tree().create_timer(respawn_time).timeout.connect(_server_respawn.bind(vid))
	if attacker != vid:
		world.match_manager.on_kill_scored(attacker)


@rpc("authority", "call_local", "reliable")
func on_hit(vid: int, hp: int, attacker: int) -> void:
	var v := world.get_player(vid)
	if v == null:
		return
	v.hp = hp
	v.avatar.flinch()
	if v.local:
		world.hud.damage()
		Sfx.play("hurt", -6.0)
		var a := world.get_player(attacker)
		if a:
			world.hud.damage_from(a.global_position)


@rpc("authority", "call_local", "reliable")
func on_kill(vid: int, attacker: int, widx: int, head: bool) -> void:
	var v := world.get_player(vid)
	if v:
		v.die()
	var wname := WeaponDB.get_data(widx).display_name
	print("[abate] %s -> %s (%s%s)" % [world.player_name(attacker), world.player_name(vid), wname, ", cabeça" if head else ""])
	if attacker == vid:
		world.hud.feed("%s se explodiu" % world.player_name(vid))
	else:
		world.hud.feed("%s  [%s%s]  %s" % [world.player_name(attacker), wname, " • CABEÇA" if head else "", world.player_name(vid)])
	if v and v.local:
		world.hud.show_death(world.player_name(attacker) if attacker != vid else "você mesmo", respawn_time)
		Config.add_stat("deaths")
	var a := world.get_player(attacker)
	if a and a.local and attacker != vid:
		Sfx.play("kill", -4.0)
		world.hud.toast("Você eliminou %s" % world.player_name(vid))
		Config.add_stat("kills")
		if head:
			Config.add_stat("headshots")


func _server_respawn(vid: int) -> void:
	if world.get_player(vid) == null or world.match_manager.phase != "play":
		return
	on_respawn.rpc(vid, world.map.best_spawn(world.alive_positions(vid)), randf() * TAU)


@rpc("authority", "call_local", "reliable")
func on_respawn(vid: int, pos: Vector3, yaw: float) -> void:
	var v := world.get_player(vid)
	if v:
		v.respawn(pos, yaw)
		if v.local:
			world.hud.hide_death()
