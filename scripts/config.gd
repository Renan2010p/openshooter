extends Node
## Preferências do jogador, estatísticas, controles e sons.

const PATH := "user://config.cfg"

var player_name := ""
var sensitivity := 0.25
var fov := 80.0
var volume := 0.8
var fullscreen := false
## 0 = baixa, 1 = média, 2 = alta.
var quality := 1
var show_fps := false
var shirt := Color(0.2, 0.45, 0.85)
var pants := Color(0.18, 0.18, 0.22)
var skin := Color(0.96, 0.8, 0.64)
var stats := {"kills": 0, "deaths": 0, "matches": 0, "wins": 0, "headshots": 0}

var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_cfg()
	apply()


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "crouch": [KEY_CTRL, KEY_C], "sprint": [KEY_SHIFT],
		"reload": [KEY_R], "scoreboard": [KEY_TAB],
		"slot1": [KEY_1], "slot2": [KEY_2], "slot3": [KEY_3],
		"slot4": [KEY_4], "slot5": [KEY_5], "slot6": [KEY_6],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var m := InputEventMouseButton.new()
			m.button_index = pair[1]
			InputMap.action_add_event(pair[0], m)


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		player_name = c.get_value("player", "name", "")
		sensitivity = c.get_value("player", "sensitivity", sensitivity)
		fov = c.get_value("player", "fov", fov)
		volume = c.get_value("player", "volume", volume)
		fullscreen = c.get_value("player", "fullscreen", fullscreen)
		quality = c.get_value("player", "quality", quality)
		show_fps = c.get_value("player", "show_fps", show_fps)
		shirt = c.get_value("look", "shirt", shirt)
		pants = c.get_value("look", "pants", pants)
		skin = c.get_value("look", "skin", skin)
		stats.merge(c.get_value("stats", "all", {}), true)
	if player_name == "":
		player_name = "Jogador%d" % (randi() % 9000 + 1000)


func save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("player", "name", player_name)
	c.set_value("player", "sensitivity", sensitivity)
	c.set_value("player", "fov", fov)
	c.set_value("player", "volume", volume)
	c.set_value("player", "fullscreen", fullscreen)
	c.set_value("player", "quality", quality)
	c.set_value("player", "show_fps", show_fps)
	c.set_value("look", "shirt", shirt)
	c.set_value("look", "pants", pants)
	c.set_value("look", "skin", skin)
	c.set_value("stats", "all", stats)
	c.save(PATH)


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Ajusta o custo gráfico do mapa atual conforme a qualidade escolhida.
func apply_quality(map: GameMap) -> void:
	var vp := map.get_viewport()
	if map.sun:
		map.sun.shadow_enabled = quality >= 1
		map.sun.directional_shadow_max_distance = 25.0 if quality == 1 else 45.0
	if map.env:
		map.env.fog_enabled = quality >= 1
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.6, 0.8, 1.0][clampi(quality, 0, 2)]
		vp.msaa_3d = Viewport.MSAA_2X if quality >= 2 else Viewport.MSAA_DISABLED


func profile() -> Dictionary:
	return {"name": player_name.substr(0, 20), "shirt": shirt, "pants": pants, "skin": skin}


func add_stat(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount
	save_cfg()


# ------------------------------------------------------------------ sons

func stream(sound: String) -> AudioStream:
	if not _cache.has(sound):
		var path := "res://audio/%s.wav" % sound
		_cache[sound] = load(path) if ResourceLoader.exists(path) else null
	return _cache[sound]


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := stream(sound)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s := stream(sound)
	var root := get_tree().current_scene
	if s == null or root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = 120.0
	root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
