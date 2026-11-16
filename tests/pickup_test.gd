extends Node
func _ready() -> void:
	Config.persist = false
	Config.quality = Config.Quality.LOW
	await get_tree().process_frame
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.server_info = {"name": "Test", "mode": "normal", "map": 0, "mode_idx": 0, "bots": 1, "minutes": 5, "max": 10, "vote": false, "private": false, "code": "", "aim_assist": true}
	Net.players[1] = {"name": "Operator", "shirt": Color.BLUE, "pants": Color.DARK_GRAY, "skin": Color.BISQUE, "kills": 0, "deaths": 0, "bot": false, "ready": true}
	var world: World = load("res://scenes/game/world.tscn").instantiate()
	world.name = "World"
	add_child(world)
	await get_tree().create_timer(1.0).timeout
	var p: Player = world.local_player
	p.hp = 40
	world.pickups.spawn_health(p.global_position)
	await get_tree().create_timer(0.3).timeout

	await get_tree().create_timer(0.7).timeout
	print("PICKUP after_collect hp=", p.hp, " count=", world.pickups.get_child_count())
	var bot: Player = world.get_player(1000)
	if bot:
		world.combat.server_damage(1000, 1, 999, 0, false)
		await get_tree().create_timer(0.5).timeout
		print("PICKUP after_kill count=", world.pickups.get_child_count())
	get_tree().quit()
