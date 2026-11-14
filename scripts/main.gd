extends Node
## Raiz do jogo (scenes/main.tscn): alterna entre o menu e a partida.
##
## Opções de teste (depois de `--`):
##   --host=normal|private|duel   cria um servidor direto (com --bots=N)
##   --join=IP [--code=12345]     entra num servidor
##   --name=Nome                  nome do jogador nesta janela
##   --quality=0|1|2              qualidade gráfica
##   --screen=Browser:normal      abre uma tela do menu (Locker, Settings...)
##   --autoplay                   o jogador local joga sozinho (IA dos bots)
##   --shot=arquivo.png --wait=N  salva uma captura depois de N segundos e fecha
##   --bench=N                    mede o FPS por N segundos e fecha

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const WORLD_SCENE := preload("res://scenes/game/world.tscn")

var current: Node
var _args := {}


func _ready() -> void:
	Net.joined.connect(_start_world)
	Net.join_failed.connect(func(reason): show_menu(reason))
	Net.disconnected.connect(func(reason): show_menu(reason))
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	# Execuções de teste não mexem nas configurações nem nas estatísticas reais.
	if not _args.is_empty():
		Config.persist = false
	if _args.has("name"):
		Config.player_name = _args["name"]
	if _args.has("quality"):
		Config.quality = int(_args["quality"])

	if _args.has("host"):
		var mode: String = _args["host"]
		host({"name": "Teste", "mode": mode, "map": int(_args.get("map", "0")), "private": mode == "private", "code": "12345" if mode == "private" else "",
			"bots": int(_args.get("bots", "3")), "minutes": 5, "max": 10})
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
		show_menu("Não foi possível criar o servidor (a porta %d já está em uso?)" % Net.PORT)
		return
	_start_world()


## A partida precisa estar em /root/Main/World em todos os computadores (RPCs).
func _start_world() -> void:
	var w: World = WORLD_SCENE.instantiate()
	w.leave_requested.connect(func(): show_menu.call_deferred())
	_swap.call_deferred(w, "World")


# ------------------------------------------------------------------ testes

func _capture(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("captura salva: ", path)
	get_tree().quit()


func _bench(seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await get_tree().create_timer(3.0).timeout
	var t_physics := 0.0
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
		t_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		t_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var secs := (Time.get_ticks_usec() - start) / 1e6
	print("BENCH ms_por_quadro: fisica=%.2f render_cpu=%.2f render_gpu=%.2f total=%.2f" % [
		t_physics / frames, t_cpu / frames, t_gpu / frames, secs * 1000.0 / frames])
	print("BENCH fps_medio=%.1f pior_quadro_ms=%.1f draw_calls=%d objetos=%d" % [
		frames / secs, worst,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	get_tree().quit()
