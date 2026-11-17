extends MenuScreen
## Play: the LAN servers playing the game mode picked in the lobby
## (Config.selected_mode), plus the ways to start playing that mode:
##   Play with bots   host a match right away, with bots, on the lobby's map
##   Create server    host with custom settings (Create screen)
##   Join with code   private servers (Private screen)
##   Direct IP        connect to an address

const ROW_SCENE := preload("res://scenes/ui/server_row.tscn")

## Quick play settings (Play with bots).
const QUICK_BOTS := 5
const QUICK_MINUTES := 5
const QUICK_MAX_PLAYERS := 10


func _ready() -> void:
	bind_button(%QuickPlay, _quick_play)
	bind_button(%Create, func(): menu.show_screen("Create"))
	bind_button(%JoinCode, func(): menu.show_screen("Private"))
	bind_button(%Connect, _connect_direct)
	bind_button(%Back, func(): menu.show_screen("Home"))
	%DirectIp.text_submitted.connect(func(_t): _connect_direct())
	Net.servers_changed.connect(_refresh)


func enter(_arg: Variant) -> void:
	var mode := ModeDB.get_mode(Config.selected_mode)
	var duel := mode.id == "duel"
	%Title.text = "%s // LAN" % mode.display_name.to_upper()
	# Quick play card: the lobby's map (its picture) and what it starts.
	var map_name := "Random map"
	if Config.selected_map >= 0:
		map_name = MapDB.display_name(Config.selected_map)
		%QuickMap.texture = load("res://assets/ui/maps/%s.png" % MapDB.info(Config.selected_map).id)
	%QuickMap.visible = Config.selected_map >= 0
	%QuickInfo.text = "%s · %d bot%s · %d minutes" % [map_name, 1 if duel else QUICK_BOTS,
		"" if duel else "s", QUICK_MINUTES]
	_refresh()


func _connect_direct() -> void:
	var ip: String = %DirectIp.text.strip_edges()
	if ip != "":
		menu.request_join(ip)


## Hosts a match at once: the lobby's mode and map, a few bots.
func _quick_play() -> void:
	var mode := ModeDB.get_mode(Config.selected_mode)
	var duel := mode.id == "duel"
	var map := Config.selected_map if Config.selected_map >= 0 else MapDB.random_index()
	menu.request_host({
		"name": "%s's server" % Config.player_name,
		"mode": "duel" if duel else "normal",
		"mode_idx": Config.selected_mode,
		"map": map,
		"private": false,
		"code": "",
		"bots": 1 if duel else QUICK_BOTS,
		"minutes": QUICK_MINUTES,
		"max": 2 if duel else QUICK_MAX_PLAYERS,
		"aim_assist": true,
	})


## Lists the public servers playing the selected mode.
func _refresh() -> void:
	if not visible:
		return
	var list: VBoxContainer = %ServerList
	for c in list.get_children():
		c.queue_free()
	var any := false
	for ip in Net.found:
		var s: Dictionary = Net.found[ip]
		if s.get("private", false) or int(s.get("mode_idx", -1)) != Config.selected_mode:
			continue
		any = true
		var row: ServerRow = ROW_SCENE.instantiate()
		list.add_child(row)
		row.setup(ip, s)
		row.join_pressed.connect(func(addr): menu.request_join(addr))
	%EmptyState.visible = not any
	%Scroll.visible = any
