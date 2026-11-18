extends Node
## Player preferences, graphics quality and statistics (user://config.cfg).
## Key bindings live in Project → Project Settings → Input Map.

signal changed

const PATH := "user://config.cfg"

enum Quality { LOW, MEDIUM, HIGH }
## Soft magnetic aim for touch players. No auto-fire.
enum AimAssist { OFF, LIGHT, STANDARD }

var player_name := ""
var sensitivity := 0.25
var fov := 80.0
var volume := 0.8
## Music level (0..1), under the master volume. See the Music autoload.
var music_volume := 0.6
var fullscreen := false
var quality: int = Quality.MEDIUM
var show_fps := false
var vsync := true
var fps_limit := 0
var render_scale := 1.0
var brightness := 1.05
var screen_shake := true
## Mobile touch controls.
var touch_joystick_size := 1.35
var touch_opacity := 1.0
var aim_assist: int = AimAssist.LIGHT
var shirt := Color(0.2, 0.45, 0.85)
var pants := Color(0.18, 0.18, 0.22)
var skin := Color(0.96, 0.8, 0.64)
var hair := Cosmetics.DEFAULT_HAIR
## Locker items, {slot: item id}; see Cosmetics.
var look := Cosmetics.defaults()
var stats := {"kills": 0, "deaths": 0, "matches": 0, "wins": 0, "headshots": 0, "history": []}
## Total experience; see Progression for the rules.
var xp := 0
## XP earned in the last finished match ({"total", "lines", "level_before",
## "level_after"}); shown on the match-over screen. Not saved.
var last_reward := {}
## Game mode (index into ModeDB) and map (index into MapDB, -1 = random)
## picked in the lobby; used when creating a server.
var selected_mode := 0
var selected_map := -1
## False during test runs (--host, --name, --bench...): nothing is persisted.
var persist := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_cfg()
	apply()


func load_cfg() -> void:
	var c := ConfigFile.new()
	var loaded := c.load(PATH) == OK
	if loaded:
		player_name = c.get_value("player", "name", "")
		sensitivity = c.get_value("player", "sensitivity", sensitivity)
		fov = c.get_value("player", "fov", fov)
		volume = c.get_value("player", "volume", volume)
		music_volume = clampf(c.get_value("player", "music_volume", music_volume), 0.0, 1.0)
		fullscreen = c.get_value("player", "fullscreen", fullscreen)
		quality = c.get_value("player", "quality", quality)
		show_fps = c.get_value("player", "show_fps", show_fps)
		vsync = c.get_value("player", "vsync", vsync)
		fps_limit = c.get_value("player", "fps_limit", fps_limit)
		render_scale = c.get_value("player", "render_scale", render_scale)
		brightness = c.get_value("player", "brightness", brightness)
		screen_shake = c.get_value("player", "screen_shake", screen_shake)
		touch_joystick_size = clampf(c.get_value("player", "touch_joystick_size", touch_joystick_size), 0.8, 2.0)
		touch_opacity = clampf(c.get_value("player", "touch_opacity", touch_opacity), 0.4, 1.0)
		aim_assist = clampi(c.get_value("player", "aim_assist", aim_assist), 0, 2)
		shirt = c.get_value("look", "shirt", shirt)
		pants = c.get_value("look", "pants", pants)
		skin = c.get_value("look", "skin", skin)
		hair = c.get_value("look", "hair", hair)
		look = Cosmetics.sanitize(c.get_value("look", "items", look))
		stats.merge(c.get_value("stats", "all", {}), true)
		# Saves from before 1.1.0 have no XP: start from what the statistics
		# are worth, so nobody begins again at level 1.
		xp = c.get_value("progress", "xp", Progression.xp_from_stats(stats))
		selected_mode = clampi(c.get_value("lobby", "mode", selected_mode), 0, ModeDB.count() - 1)
		selected_map = clampi(c.get_value("lobby", "map", selected_map), -1, MapDB.count() - 1)
	if not loaded and OS.has_feature("mobile"):
		quality = Quality.LOW
	if player_name == "":
		player_name = "Player%d" % (randi() % 9000 + 1000)


func save_cfg() -> void:
	if not persist:
		changed.emit()
		return
	var c := ConfigFile.new()
	for key in ["name", "sensitivity", "fov", "volume", "music_volume", "fullscreen", "quality", "show_fps",
			"vsync", "fps_limit", "render_scale", "brightness", "screen_shake",
			"touch_joystick_size", "touch_opacity", "aim_assist"]:
		c.set_value("player", key, player_name if key == "name" else get(key))
	for key in ["shirt", "pants", "skin", "hair"]:
		c.set_value("look", key, get(key))
	c.set_value("look", "items", look)
	c.set_value("stats", "all", stats)
	c.set_value("progress", "xp", xp)
	c.set_value("lobby", "mode", selected_mode)
	c.set_value("lobby", "map", selected_map)
	c.save(PATH)
	changed.emit()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	if not OS.has_feature("mobile"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit


## How far the map and players are drawn (meters), by quality level.
const DRAW_DISTANCE := [65.0, 95.0, 140.0]
## How far small details are drawn (meters), by quality level.
const DETAIL_DISTANCE := [26.0, 46.0, 72.0]


func draw_distance() -> float:
	return DRAW_DISTANCE[clampi(quality, 0, 2)]


func detail_distance() -> float:
	return DETAIL_DISTANCE[clampi(quality, 0, 2)]


## Adjusts the rendering cost of a map to the selected quality level.
func apply_quality(sun: DirectionalLight3D, env: Environment, vp: Viewport) -> void:
	if sun:
		sun.shadow_enabled = quality >= Quality.MEDIUM
		sun.directional_shadow_max_distance = 34.0 if quality == Quality.MEDIUM else 58.0
	if env:
		# Global brightness control (Settings → Advanced).
		env.adjustment_enabled = true
		env.adjustment_brightness = brightness
		# Depth fog: clear up close and total at the draw distance, so whatever
		# stops being drawn fades into it without popping.
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = draw_distance() * 0.5
		env.fog_depth_end = draw_distance()
		env.fog_depth_curve = 1.5
		env.fog_density = 1.0
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		var base_scale: float = [0.6, 0.8, 1.0][clampi(quality, 0, 2)]
		vp.scaling_3d_scale = clampf(base_scale * render_scale, 0.35, 1.0)
		vp.msaa_3d = Viewport.MSAA_2X if quality >= Quality.HIGH else Viewport.MSAA_DISABLED


## Data sent to the server when joining a match.
func profile() -> Dictionary:
	return {"name": player_name.substr(0, 20), "shirt": shirt, "pants": pants, "skin": skin,
		"hair": hair, "look": look, "version": Net.GAME_VERSION,
		"xp_level": int(Progression.level_info(xp).level)}


func add_stat(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount
	save_cfg()


## Gives the XP for a finished match and remembers it in `last_reward`.
func award_match_xp(kills: int, won: bool) -> void:
	var reward := Progression.match_reward(kills, won)
	reward["level_before"] = Progression.level_info(xp).level
	xp += int(reward.total)
	reward["level_after"] = Progression.level_info(xp).level
	reward["won"] = won
	last_reward = reward
	save_cfg()


## Adds one match to the local performance history (last 12 matches).
func record_match(kills: int, deaths: int, won: bool) -> void:
	var history: Array = stats.get("history", [])
	history.append({"kills": kills, "deaths": deaths, "won": won})
	while history.size() > 12:
		history.pop_front()
	stats["history"] = history
	save_cfg()
