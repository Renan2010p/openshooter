extends Node
## Troca entre menu e partida.
##
## Opções de teste (depois de `--`):
##   --host=normal|private|duel  cria um servidor direto (com --bots=N)
##   --join=IP                   entra num servidor
##   --name=Nome                 nome do jogador nesta janela
##   --shot=arquivo.png          salva uma captura depois de --wait segundos e fecha

var current: Node


func _ready() -> void:
	Net.joined.connect(_start_world)
	Net.join_failed.connect(func(reason): show_menu(reason))
	Net.disconnected.connect(func(reason): show_menu(reason))
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("name"):
		Config.player_name = args["name"]
	if args.has("quality"):
		Config.quality = int(args["quality"])
	if args.has("host"):
		var mode: String = args["host"]
		_host({"name": "Teste", "mode": mode, "private": mode == "private", "code": "12345" if mode == "private" else "",
			"bots": int(args.get("bots", "3")), "minutes": 5, "max": 10})
	elif args.has("join"):
		show_menu()
		Net.join(args["join"], args.get("code", ""))
	elif args.has("browse"):
		show_menu()
		await get_tree().process_frame
		await get_tree().process_frame
		if args["browse"] == "locker":
			(current as MainMenu).show_locker()
		else:
			(current as MainMenu).show_browser(args["browse"])
	else:
		show_menu()
	if args.has("shot"):
		_capture(args["shot"], float(args.get("wait", "3")))
	if args.has("bench"):
		_bench(float(args.get("bench", "15")))


## Mede FPS sem VSync e imprime draw calls e objetos por quadro.
func _bench(seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await get_tree().create_timer(3.0).timeout
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
	var secs := (Time.get_ticks_usec() - start) / 1e6
	var kinds := {}
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		kinds[n.get_class()] = int(kinds.get(n.get_class(), 0)) + 1
	print("BENCH nos_visuais=", kinds)
	print("BENCH fps_medio=%.1f pior_quadro_ms=%.1f draw_calls=%d objetos=%d primitivas=%d" % [
		frames / secs, worst,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()


func _capture(path: String, wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("captura salva: ", path)
	get_tree().quit()


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
	var m := MainMenu.new()
	m.message = msg
	m.host_requested.connect(_host)
	m.join_requested.connect(func(ip, code): Net.join(ip, code))
	m.quit_requested.connect(func(): get_tree().quit())
	_swap.call_deferred(m, "Menu")


func _host(info: Dictionary) -> void:
	var err := Net.host(info)
	if err != OK:
		show_menu("Não foi possível criar o servidor (a porta %d já está em uso?)" % Net.PORT)
		return
	_start_world()


func _start_world() -> void:
	var w := World.new()
	w.leave_requested.connect(func(): show_menu())
	_swap.call_deferred(w, "World")
