class_name MainMenu
extends Node3D
## Menu principal com o mapa girando ao fundo.

signal host_requested(info: Dictionary)
signal join_requested(ip: String, code: String)
signal quit_requested

var message := ""

var _cam: Camera3D
var _t := 0.0
var _ui: Control
var _panel: Control
var _status: Label
var _avatar_root: Node3D
var _screen := ""
var _private_code := ""
var _pending_code := ""
var _pending_t := 0.0


func _ready() -> void:
	var map := GameMap.new()
	add_child(map)
	map.build()
	_cam = Camera3D.new()
	_cam.fov = 65
	add_child(_cam)
	_cam.current = true
	_avatar_root = Node3D.new()
	_avatar_root.position = Vector3(0, 0, 18)
	add_child(_avatar_root)
	_rebuild_avatar()

	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	_status = _text(_ui, message, 18, Color(1, 0.6, 0.5))
	_status.position = Vector2(0, 680)
	_status.size = Vector2(1280, 30)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.start_listening()
	Net.servers_changed.connect(_on_servers_changed)
	show_main()


func _exit_tree() -> void:
	Net.stop_listening()


func _process(delta: float) -> void:
	_t += delta
	if _screen == "locker":
		_cam.global_position = _cam.global_position.lerp(Vector3(-1.6, 1.5, 23.2), minf(1.0, delta * 3.0))
		_cam.look_at(Vector3(-1.75, 1.1, 18))
		_avatar_root.rotation.y += delta * 0.6
	else:
		var a := _t * 0.05
		_cam.global_position = Vector3(sin(a) * 30.0, 12.0, cos(a) * 30.0)
		_cam.look_at(Vector3(0, 1, 0))
	if _pending_code != "":
		_pending_t -= delta
		_try_private_join()
		if _pending_t <= 0.0 and _pending_code != "":
			_pending_code = ""
			set_status("Nenhum servidor privado com esse código foi encontrado na rede.")


func set_status(text: String, ok := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(0.6, 1, 0.6) if ok else Color(1, 0.6, 0.5))


# ------------------------------------------------------------------ helpers de UI

func _style(color: Color, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


func _text(parent: Control, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable, size := Vector2(300, 56), font := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_stylebox_override("normal", _style(Color(0.04, 0.04, 0.05, 0.92)))
	b.add_theme_stylebox_override("hover", _style(Color(0.16, 0.16, 0.18, 0.95)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.25, 0.22, 0.12, 0.95)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		Config.play("switch", -8.0)
		cb.call())
	parent.add_child(b)
	return b


func _clear() -> void:
	if _panel:
		_panel.queue_free()
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_panel)
	_ui.move_child(_status, -1)


func _title(text: String) -> void:
	var l := _text(_panel, text, 46)
	l.position = Vector2(0, 40)
	l.size = Vector2(1280, 70)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _card(pos: Vector2, size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.06, 0.92), 10))
	_panel.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	return v


func _field(parent: Control, label: String, control: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	l.add_theme_font_size_override("font_size", 20)
	h.add_child(l)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 240)
	h.add_child(control)
	parent.add_child(h)


# ------------------------------------------------------------------ telas

func show_main() -> void:
	_screen = "main"
	_clear()
	var t := _text(_panel, "LINHA DE FOGO", 64)
	t.position = Vector2(60, 60)
	var s := _text(_panel, "tiroteio em LAN", 22, Color(1, 0.8, 0.3))
	s.position = Vector2(64, 140)
	var v := VBoxContainer.new()
	v.position = Vector2(60, 230)
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_button(v, "▶  Jogar", show_modes)
	_button(v, "▣  Armário", show_locker)
	_button(v, "⚙  Configurações", show_settings)
	_button(v, "ℹ  Estatísticas", show_stats)
	_button(v, "✕  Sair", func(): quit_requested.emit())
	var who := _text(_panel, Config.player_name, 20)
	who.position = Vector2(1000, 24)
	who.size = Vector2(250, 30)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func show_modes() -> void:
	_screen = "modes"
	_clear()
	_title("SELECIONE O MODO DE JOGO")
	var v := VBoxContainer.new()
	v.position = Vector2(390, 170)
	v.add_theme_constant_override("separation", 18)
	_panel.add_child(v)
	_button(v, "Normal", show_browser.bind("normal"), Vector2(500, 90), 36)
	_button(v, "Privado", show_private, Vector2(500, 90), 36)
	_button(v, "Apenas Duelos", show_browser.bind("duel"), Vector2(500, 90), 36)
	_button(v, "Voltar", show_main, Vector2(500, 56), 24)


func show_browser(mode: String) -> void:
	_screen = "browser:" + mode
	_clear()
	_title("SERVIDORES NA REDE — " + ("NORMAL" if mode == "normal" else "APENAS DUELOS"))
	var v := _card(Vector2(240, 130), Vector2(800, 520))
	var list := VBoxContainer.new()
	list.name = "List"
	list.custom_minimum_size = Vector2(760, 280)
	list.add_theme_constant_override("separation", 6)
	v.add_child(list)
	_fill_list(list, mode)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	_button(h, "Criar servidor", show_create.bind(mode), Vector2(250, 50), 22)
	var ip := LineEdit.new()
	ip.placeholder_text = "IP direto (ex.: 192.168.0.10)"
	ip.custom_minimum_size = Vector2(300, 50)
	h.add_child(ip)
	_button(h, "Conectar", func():
		if ip.text.strip_edges() != "":
			set_status("Conectando a %s..." % ip.text, true)
			join_requested.emit(ip.text.strip_edges(), ""), Vector2(150, 50), 22)
	_button(v, "Voltar", show_modes, Vector2(200, 46), 22)


func _fill_list(list: VBoxContainer, mode: String) -> void:
	for c in list.get_children():
		c.queue_free()
	var any := false
	for ip in Net.found:
		var s: Dictionary = Net.found[ip]
		if s.get("private", false) or s.get("mode", "") != mode:
			continue
		any = true
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = "%s   (%s)   %d/%d jogadores   %d bots" % [s.name, ip, int(s.players), int(s.max), int(s.get("bots", 0))]
		l.custom_minimum_size = Vector2(590, 0)
		l.add_theme_font_size_override("font_size", 18)
		h.add_child(l)
		_button(h, "Entrar", func():
			set_status("Conectando a %s..." % ip, true)
			join_requested.emit(ip, ""), Vector2(140, 42), 20)
		list.add_child(h)
	if not any:
		var l := Label.new()
		l.text = "Procurando servidores na rede local...\nNenhum encontrado ainda. Crie um ou conecte por IP."
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		list.add_child(l)


func _on_servers_changed() -> void:
	if _screen.begins_with("browser:") and _panel:
		var list := _panel.find_child("List", true, false) as VBoxContainer
		if list:
			_fill_list(list, _screen.split(":")[1])


func show_private() -> void:
	_screen = "private"
	_clear()
	_title("JOGO PRIVADO")
	var v := _card(Vector2(440, 150), Vector2(400, 420))
	var code := LineEdit.new()
	code.placeholder_text = "00000"
	code.max_length = 5
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 36)
	code.custom_minimum_size = Vector2(360, 64)
	v.add_child(code)
	_button(v, "Entrar no Servidor", func():
		var c := code.text.strip_edges()
		if c.length() != 5 or not c.is_valid_int():
			set_status("O código tem 5 números.")
			return
		_pending_code = c
		_pending_t = 4.0
		set_status("Procurando o servidor %s na rede..." % c, true), Vector2(360, 60), 26)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	v.add_child(spacer)
	_button(v, "Criar Servidor Privado", show_create.bind("private"), Vector2(360, 60), 26)
	_button(v, "Voltar", show_modes, Vector2(160, 46), 22)


func _try_private_join() -> void:
	var h := Net.code_hash(_pending_code)
	for ip in Net.found:
		if Net.found[ip].get("hash", "") == h:
			var c := _pending_code
			_pending_code = ""
			set_status("Servidor encontrado! Conectando...", true)
			join_requested.emit(ip, c)
			return


func show_create(mode: String) -> void:
	_screen = "create"
	_clear()
	_title("CRIAR SERVIDOR")
	var v := _card(Vector2(340, 140), Vector2(600, 460))
	var name_edit := LineEdit.new()
	name_edit.text = "Servidor de %s" % Config.player_name
	_field(v, "Nome", name_edit)
	var bots := SpinBox.new()
	bots.min_value = 0
	bots.max_value = 1 if mode == "duel" else 8
	bots.value = 1 if mode == "duel" else 3
	_field(v, "Bots", bots)
	var minutes := OptionButton.new()
	for m in [3, 5, 10, 15]:
		minutes.add_item("%d minutos" % m, m)
	minutes.select(1)
	_field(v, "Duração", minutes)
	var max_p := SpinBox.new()
	max_p.min_value = 2
	max_p.max_value = 16
	max_p.value = 2 if mode == "duel" else 10
	max_p.editable = mode != "duel"
	_field(v, "Máx. jogadores", max_p)
	_private_code = "%05d" % (randi() % 100000)
	if mode == "private":
		var l := Label.new()
		l.text = "Código Privado: %s" % _private_code
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		v.add_child(l)
	if mode == "duel":
		var l := Label.new()
		l.text = "Duelo 1 contra 1: vence quem fizer %d abates primeiro." % World.DUEL_KILLS
		l.add_theme_font_size_override("font_size", 16)
		v.add_child(l)
	_button(v, "Criar", func():
		host_requested.emit({
			"name": name_edit.text.substr(0, 32), "mode": mode, "private": mode == "private",
			"code": _private_code if mode == "private" else "", "bots": int(bots.value),
			"minutes": minutes.get_selected_id(), "max": int(max_p.value),
		}), Vector2(300, 56), 26)
	_button(v, "Voltar", show_private if mode == "private" else show_browser.bind(mode), Vector2(160, 46), 22)


func _rebuild_avatar() -> void:
	for c in _avatar_root.get_children():
		c.queue_free()
	var parts := Models.avatar(Config.shirt, Config.pants, Config.skin)
	_avatar_root.add_child(parts.root)
	var g := Models.weapon(Weapons.RIFLE)
	g.position = Vector3(0, -0.72, -0.05)
	g.rotation.x = -PI / 2.0
	parts.arm_r.add_child(g)
	parts.arm_r.rotation.x = PI / 2.0
	parts.arm_l.rotation = Vector3(PI / 2.0, -0.45, 0)


func show_locker() -> void:
	_screen = "locker"
	_clear()
	_title("ARMÁRIO")
	var v := _card(Vector2(60, 140), Vector2(470, 400))
	var name_edit := LineEdit.new()
	name_edit.text = Config.player_name
	name_edit.max_length = 20
	_field(v, "Nome", name_edit)
	var pickers := {}
	for spec in [["Camisa", "shirt"], ["Calça", "pants"], ["Pele", "skin"]]:
		var cp := ColorPickerButton.new()
		cp.color = Config.get(spec[1])
		cp.custom_minimum_size = Vector2(160, 40)
		cp.color_changed.connect(func(c):
			Config.set(spec[1], c)
			_rebuild_avatar())
		_field(v, spec[0], cp)
	_button(v, "Salvar", func():
		if name_edit.text.strip_edges() != "":
			Config.player_name = name_edit.text.strip_edges()
		Config.save_cfg()
		set_status("Armário salvo.", true)
		show_main(), Vector2(200, 50), 24)


func show_settings() -> void:
	_screen = "settings"
	_clear()
	_title("CONFIGURAÇÕES")
	var v := _card(Vector2(340, 130), Vector2(600, 480))
	var sens := HSlider.new()
	sens.min_value = 0.05
	sens.max_value = 1.0
	sens.step = 0.01
	sens.value = Config.sensitivity
	_field(v, "Sensibilidade do mouse", sens)
	var fov := HSlider.new()
	fov.min_value = 60
	fov.max_value = 110
	fov.value = Config.fov
	_field(v, "Campo de visão", fov)
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.01
	vol.value = Config.volume
	_field(v, "Volume", vol)
	var full := CheckBox.new()
	full.button_pressed = Config.fullscreen
	_field(v, "Tela cheia", full)
	var quality := OptionButton.new()
	quality.add_item("Baixa (mais FPS)", 0)
	quality.add_item("Média", 1)
	quality.add_item("Alta", 2)
	quality.select(Config.quality)
	_field(v, "Qualidade gráfica", quality)
	var fps := CheckBox.new()
	fps.button_pressed = Config.show_fps
	_field(v, "Mostrar FPS", fps)
	_button(v, "Salvar", func():
		Config.sensitivity = sens.value
		Config.fov = fov.value
		Config.volume = vol.value
		Config.fullscreen = full.button_pressed
		Config.quality = quality.get_selected_id()
		Config.show_fps = fps.button_pressed
		Config.save_cfg()
		Config.apply()
		set_status("Configurações salvas.", true)
		show_main(), Vector2(200, 50), 24)


func show_stats() -> void:
	_screen = "stats"
	_clear()
	_title("ESTATÍSTICAS")
	var v := _card(Vector2(440, 160), Vector2(400, 340))
	var s := Config.stats
	var kd := float(s.kills) / maxf(1.0, float(s.deaths))
	for line in ["Abates: %d" % s.kills, "Mortes: %d" % s.deaths, "Abates/Mortes: %.2f" % kd,
			"Tiros na cabeça: %d" % s.headshots, "Partidas: %d" % s.matches, "Vitórias: %d" % s.wins]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 24)
		v.add_child(l)
	_button(v, "Voltar", show_main, Vector2(160, 46), 22)
