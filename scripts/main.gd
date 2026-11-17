extends Node
## Game root (scenes/main.tscn): switches between the menu and a match.
##
## Test options (after `--`):
##   --host=normal|private|duel   start a server directly (with --bots=N)
##   --join=IP [--code=12345]     join a server
##   --name=Player                player name for this window
##   --quality=0|1|2              graphics quality
##   --screen=Browser:normal      open a menu screen (Locker, Settings...)
##   --autoplay                   the local player is driven by bot AI
##   --shot=file.png --wait=N     save a screenshot after N seconds and quit
##   --bench=N                    measure FPS for N seconds
##   --trailer=N                  record trailer segment N (see tools/trailer/) and quit
##   --help                       print the available options and quit

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const WORLD_SCENE := preload("res://scenes/game/world.tscn")
const USAGE := """OpenShooter

Usage:
  godot --path . [-- options]

Options (after the -- separator):
  --host=normal|private|duel   start a server directly
  --join=IP [--code=12345]     join a server
  --name=Player                player name for this window
  --quality=0|1|2              graphics quality (low, medium, high)
  --bots=N                     number of bots on a hosted server
  --minutes=N                  match length of a hosted server (default 5)
  --map=INDEX                  map index for a hosted server
  --screen=Screen[:arg]        open a menu screen directly
  --autoplay                   drive the local player with bot AI
  --shot=FILE.png [--wait=N]   save a screenshot after N seconds
  --bench=N                    measure FPS for N seconds
  --trailer=N                  record trailer segment N (see tools/trailer/)
  --help                       show this help"""

@onready var loading: LoadingScreen = $LoadingScreen

var current: Node
var _args := {}
var _loading := false
var _load_token := 0


func _ready() -> void:
	Net.joined.connect(_start_world)
	Net.join_failed.connect(func(reason): show_menu(reason))
	Net.disconnected.connect(func(reason): show_menu(reason))
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if _args.has("help"):
		print(USAGE)
		get_tree().quit()
		return
	# Test runs must not touch the real settings or statistics.
	if not _args.is_empty():
		Config.persist = false
	if _args.has("name"):
		Config.player_name = _args["name"]
	if _args.has("quality"):
		Config.quality = int(_args["quality"])

	if _args.has("host"):
		var mode: String = _args["host"]
		host({"name": "Test", "mode": mode, "map": int(_args.get("map", "0")), "mode_idx": int(_args.get("mode", "0")), "vote": _args.has("vote"), "private": mode == "private", "code": "12345" if mode == "private" else "",
			"bots": int(_args.get("bots", "3")), "minutes": float(_args.get("minutes", "5")), "max": 10})
	else:
		show_menu()
		if _args.has("join"):
			Net.join(_args["join"], _args.get("code", ""))
		elif _args.has("screen"):
			var parts := (_args["screen"] as String).split(":")
			await get_tree().process_frame
			(current as MainMenu).show_screen(parts[0], parts[1] if parts.size() > 1 else null)
	if _args.has("shot"):
		_capture(_args["shot"], float(_args.get("wait", "3")))
	if _args.has("bench"):
		_bench(float(_args.get("bench", "15")))


func _swap(node: Node, node_name: String) -> void:
	if current:
		remove_child(current)
		current.queue_free()
	current = node
	node.name = node_name
	add_child(node)


func show_menu(msg := "") -> void:
	_load_token += 1
	_loading = false
	if is_instance_valid(loading):
		loading.hide_now()
	if current is World:
		remove_child(current)
		current.queue_free()
		current = null
	Net.leave()
	var m: MainMenu = MENU_SCENE.instantiate()
	m.message = msg
	m.host_requested.connect(host)
	m.join_requested.connect(func(ip, code): Net.join(ip, code))
	m.quit_requested.connect(func(): get_tree().quit())
	_swap(m, "Menu")


func host(info: Dictionary) -> void:
	if Net.host(info) != OK:
		show_menu("Could not start the server (is port %d already in use?)" % Net.PORT)
		return
	_start_world()


## The match must live at /root/Main/World on every computer (RPCs rely on it).
func _start_world() -> void:
	if _loading:
		return
	_loading = true
	_load_token += 1
	var token := _load_token
	var map_idx := clampi(int(Net.server_info.get("map", 0)), 0, MapDB.count() - 1)
	var mode_idx := clampi(int(Net.server_info.get("mode_idx", 0)), 0, ModeDB.count() - 1)
	loading.begin("LOADING MATCH", "%s  ·  %s" % [MapDB.display_name(map_idx), ModeDB.get_mode(mode_idx).display_name])
	await get_tree().process_frame
	var world_resource := await _load_threaded(WORLD_SCENE.resource_path, 0.0, 0.55)
	if token != _load_token:
		return
	var map_resource := await _load_threaded(MapDB.info(map_idx).scene, 0.55, 0.9)
	if token != _load_token:
		return
	if not (world_resource is PackedScene) or not (map_resource is PackedScene):
		_loading = false
		show_menu("Could not load the match files.")
		return
	loading.set_progress(0.94, "BUILDING WORLD")
	await get_tree().process_frame
	var w: World = (world_resource as PackedScene).instantiate()
	w.preloaded_map = map_resource as PackedScene
	w.preloaded_map_idx = map_idx
	w.leave_requested.connect(func(): show_menu.call_deferred())
	_swap(w, "World")
	await get_tree().process_frame
	await get_tree().process_frame
	loading.set_progress(1.0, "READY")
	await get_tree().create_timer(0.3).timeout
	await loading.finish()
	_loading = false
	if _args.has("trailer") and current is World:
		var director := TrailerDirector.new()
		director.world = current
		director.segment = int(_args["trailer"])
		current.add_child(director)


## Loads a resource on the thread pool while updating the progress bar.
func _load_threaded(path: String, from: float, to: float) -> Resource:
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		loading.set_progress(to, "LOADING")
		return load(path)
	var progress := []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var value := 0.0
			if not progress.is_empty():
				value = float(progress[0])
			loading.set_progress(lerpf(from, to, value), "LOADING")
			await get_tree().process_frame
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			loading.set_progress(to, "LOADED")
			return ResourceLoader.load_threaded_get(path)
		else:
			return null
	return null


# ------------------------------------------------------------------ tests

func _capture(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()


func _bench(seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await get_tree().create_timer(3.0).timeout
	var t_physics := 0.0
	var t_process := 0.0
	var t_cpu := 0.0
	var t_gpu := 0.0
	var frames := 0
	var worst := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while (Time.get_ticks_usec() - start) / 1e6 < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		t_physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		t_process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		t_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		t_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var secs := (Time.get_ticks_usec() - start) / 1e6
	print("BENCH ms_per_frame: process=%.2f physics=%.2f render_cpu=%.2f render_gpu=%.2f total=%.2f" % [
		t_process / frames, t_physics / frames, t_cpu / frames, t_gpu / frames, secs * 1000.0 / frames])
	print("BENCH avg_fps=%.1f worst_frame_ms=%.1f draw_calls=%d objects=%d" % [
		frames / secs, worst,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	get_tree().quit()
