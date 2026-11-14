class_name Hud
extends CanvasLayer
## Interface da partida.

var world: World
var paused := false

var _root: Control
var _cross: Array[ColorRect] = []
var _dot: ColorRect
var _hit: Label
var _hit_t := 0.0
var _hp_fill: ColorRect
var _hp_label: Label
var _ammo: Label
var _wname: Label
var _slots: Array[Label] = []
var _timer: Label
var _timer_bar: ColorRect
var _top: Array[Label] = []
var _feed: VBoxContainer
var _vignette: ColorRect
var _dmg_t := 0.0
var _dir: Label
var _dir_t := 0.0
var _death: Label
var _death_t := 0.0
var _toast: Label
var _toast_t := 0.0
var _board: PanelContainer
var _board_text: Label
var _end: Label
var _scope: ColorRect
var _pause: PanelContainer
var _info: Label
var _fps: Label
var _slow_t := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var scope_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float aspect = 1.777;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float ring = smoothstep(0.42, 0.425, r);
	float line = (abs(p.x) < 0.0015 || abs(p.y) < 0.0015) ? 1.0 : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, max(ring, line * (1.0 - ring)));
}"""
	scope_mat.shader = sh
	_scope = _rect(Color.BLACK)
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope.material = scope_mat
	_scope.visible = false

	_vignette = _rect(Color(0.8, 0, 0, 0))
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for i in 4:
		_cross.append(_rect(Color(1, 1, 1, 0.9)))
	_dot = _rect(Color(1, 1, 1, 0.9))
	_dot.size = Vector2(2, 2)
	_hit = _label("✕", 34, Color.WHITE)
	_hit.visible = false

	# Vida.
	var hp_bg := _rect(Color(0, 0, 0, 0.6))
	hp_bg.position = Vector2(24, 664)
	hp_bg.size = Vector2(300, 30)
	_hp_fill = _rect(Color(0.2, 0.85, 0.3))
	_hp_fill.position = Vector2(27, 667)
	_hp_fill.size = Vector2(294, 24)
	_hp_label = _label("100%", 20, Color.WHITE)
	_hp_label.position = Vector2(34, 664)

	# Munição.
	_ammo = _label("30 / 90", 40, Color.WHITE)
	_ammo.position = Vector2(1060, 640)
	_ammo.size = Vector2(196, 50)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wname = _label("", 18, Color(0.85, 0.85, 0.85))
	_wname.position = Vector2(1060, 620)
	_wname.size = Vector2(196, 24)
	_wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Barra de armas.
	for i in Weapons.LIST.size():
		var bg := _rect(Color(0, 0, 0, 0.55))
		bg.position = Vector2(400 + i * 82, 660)
		bg.size = Vector2(78, 46)
		var l := _label("%d\n%s" % [i + 1, Weapons.LIST[i].name], 14, Color.WHITE)
		l.position = bg.position
		l.size = bg.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_meta("bg", bg)
		_slots.append(l)

	# Relógio e top 3.
	_timer = _label("05:00", 44, Color.WHITE)
	_timer.position = Vector2(540, 6)
	_timer.size = Vector2(200, 54)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tb := _rect(Color(0, 0, 0, 0.5))
	tb.position = Vector2(560, 60)
	tb.size = Vector2(160, 6)
	_timer_bar = _rect(Color.WHITE)
	_timer_bar.position = Vector2(560, 60)
	_timer_bar.size = Vector2(160, 6)
	var medal := [Color(1.0, 0.82, 0.25), Color(0.85, 0.87, 0.9), Color(0.85, 0.55, 0.3)]
	for i in 3:
		var l := _label("", 18, medal[i])
		l.position = Vector2(390 + i * 170, 74)
		l.size = Vector2(160, 48)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_top.append(l)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(880, 16)
	_feed.size = Vector2(380, 200)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)

	_dir = _label("", 40, Color(1, 0.2, 0.2))
	_dir.size = Vector2(60, 60)
	_dir.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death = _label("", 30, Color.WHITE)
	_death.position = Vector2(0, 300)
	_death.size = Vector2(1280, 120)
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = _label("", 20, Color(1, 0.9, 0.5))
	_toast.position = Vector2(0, 450)
	_toast.size = Vector2(1280, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end = _label("", 40, Color(1, 0.85, 0.3))
	_end.position = Vector2(0, 200)
	_end.size = Vector2(1280, 120)
	_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_fps = _label("", 16, Color(0.6, 1.0, 0.6))
	_fps.position = Vector2(24, 16)
	_fps.visible = Config.show_fps
	_info = _label("", 15, Color(0.9, 0.9, 0.9))
	_info.position = Vector2(24, 630)
	var mode_name: String = {"normal": "Normal", "private": "Privado", "duel": "Apenas Duelos"}.get(Net.server_info.get("mode", "normal"), "")
	_info.text = "%s  •  %s" % [Net.server_info.get("name", ""), mode_name]
	if Net.server_info.get("private", false) and Net.server_info.has("code"):
		_info.text += "  •  Código Privado: %s" % Net.server_info.code

	_board = _panel(Vector2(340, 130), Vector2(600, 440))
	_board_text = Label.new()
	_board_text.add_theme_font_size_override("font_size", 20)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace", "DejaVu Sans Mono", "Courier New"])
	_board_text.add_theme_font_override("font", mono)
	_board.add_child(_board_text)
	_board.visible = false

	_pause = _panel(Vector2(490, 220), Vector2(300, 260))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_pause.add_child(box)
	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	for spec in [["Continuar", toggle_pause], ["Sair da partida", func(): world.leave_requested.emit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(260, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(spec[1])
		box.add_child(b)
	var hint := Label.new()
	hint.text = "WASD andar • ESPAÇO pular\nSHIFT correr • CTRL agachar\nR recarregar • 1-6 armas\nbotão direito: mira do fuzil"
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)
	_pause.visible = false


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.9)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	return p


# ------------------------------------------------------------------ eventos

func hitmarker(head: bool) -> void:
	_hit_t = 0.2
	_hit.add_theme_color_override("font_color", Color(1, 0.25, 0.2) if head else Color.WHITE)


func damage() -> void:
	_dmg_t = 0.5


func damage_from(pos: Vector3) -> void:
	var p := world.local_player
	if p == null:
		return
	var to := pos - p.global_position
	var ang := angle_difference(p.rotation.y, atan2(-to.x, -to.z))
	_dir.position = Vector2(640, 360) + Vector2(sin(-ang), -cos(ang)) * 120.0 - Vector2(30, 30)
	_dir.text = "◆"
	_dir_t = 1.0


func feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(380, 0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	_feed.add_child(l)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(6.0).timeout.connect(l.queue_free)


func show_death(by: String, t: float) -> void:
	_death_t = t
	_death.set_meta("by", by)


func hide_death() -> void:
	_death_t = 0.0


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.0


func toggle_pause() -> void:
	paused = not paused
	_pause.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ atualização

func _process(delta: float) -> void:
	var p := world.local_player
	var vp := get_viewport().get_visible_rect().size
	var center := vp / 2.0

	if p:
		var w := Weapons.get_w(p.weapon_idx)
		var gap := 6.0 + p.current_spread() * 500.0
		var specs := [[Vector2(-gap - 10, -1), Vector2(10, 2)], [Vector2(gap, -1), Vector2(10, 2)], [Vector2(-1, -gap - 10), Vector2(2, 10)], [Vector2(-1, gap), Vector2(2, 10)]]
		var show_cross: bool = p.alive and not p.scoped and not w.get("melee", false) and not w.get("mine", false)
		for i in 4:
			_cross[i].position = center + specs[i][0]
			_cross[i].size = specs[i][1]
			_cross[i].visible = show_cross
		_dot.position = center - Vector2(1, 1)
		_dot.visible = p.alive and not p.scoped
		_scope.visible = p.scoped
		(_scope.material as ShaderMaterial).set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
		var hp := clampi(p.hp, 0, 100)
		_hp_fill.size.x = 294.0 * hp / 100.0
		_hp_fill.color = Color(0.2, 0.85, 0.3) if hp > 50 else (Color(0.95, 0.75, 0.1) if hp > 25 else Color(0.95, 0.2, 0.15))
		_hp_label.text = "%d%%" % hp
		_wname.text = w.name
		if w.get("melee", false):
			_ammo.text = "∞"
		elif w.get("mine", false):
			_ammo.text = "%d" % p.ammo[p.weapon_idx][0]
		else:
			_ammo.text = "%d / %d" % [p.ammo[p.weapon_idx][0], p.ammo[p.weapon_idx][1]]
			if p.reload_t > 0.0:
				_ammo.text = "recarregando"
		for i in _slots.size():
			var bg: ColorRect = _slots[i].get_meta("bg")
			bg.color = Color(1, 0.8, 0.2, 0.55) if i == p.weapon_idx else Color(0, 0, 0, 0.55)

	_hit_t = maxf(0.0, _hit_t - delta)
	_hit.visible = _hit_t > 0.0
	_hit.position = center - Vector2(13, 25)
	_dmg_t = maxf(0.0, _dmg_t - delta)
	_vignette.color = Color(0.8, 0, 0, _dmg_t * 0.5)
	if p and p.alive and p.hp < 30:
		_vignette.color.a = maxf(_vignette.color.a, 0.15 + 0.08 * sin(Time.get_ticks_msec() / 200.0))
	_dir_t = maxf(0.0, _dir_t - delta)
	_dir.modulate.a = _dir_t
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast.modulate.a = minf(1.0, _toast_t * 2.0)

	if _death_t > 0.0:
		_death_t = maxf(0.0, _death_t - delta)
		_death.text = "Eliminado por %s\nRenascendo em %d..." % [_death.get_meta("by", "?"), ceili(_death_t)]
	_death.visible = _death_t > 0.0

	# Textos que não precisam mudar a cada quadro: 10 vezes por segundo.
	_slow_t -= delta
	if _slow_t > 0.0:
		return
	_slow_t = 0.1
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	var total := float(Net.server_info.get("minutes", 5)) * 60.0
	var t := maxi(0, ceili(world.time_left))
	_timer.text = "%02d:%02d" % [t / 60, t % 60]
	_timer_bar.size.x = 160.0 * clampf(world.time_left / maxf(total, 1.0), 0.0, 1.0)

	var ranking := Net.players.keys()
	ranking.sort_custom(func(a, b): return int(Net.players[a].kills) > int(Net.players[b].kills))
	for i in 3:
		if i < ranking.size():
			var info: Dictionary = Net.players[ranking[i]]
			_top[i].text = "%s\n%d eliminações" % [info.name, int(info.kills)]
		else:
			_top[i].text = "Ninguém"

	_end.visible = world.phase == "end"
	_end.text = "FIM DA PARTIDA\nVencedor: %s" % world.winner

	_board.visible = Input.is_action_pressed("scoreboard") or world.phase == "end"
	if _board.visible:
		var lines := ["%-22s %6s %6s" % ["JOGADOR", "ABATES", "MORTES"], ""]
		for id in ranking:
			var info: Dictionary = Net.players[id]
			var me := " ◄" if id == multiplayer.get_unique_id() else ""
			lines.append("%-22s %6d %6d%s" % [str(info.name).substr(0, 20), int(info.kills), int(info.deaths), me])
		_board_text.text = "\n".join(lines)
		_board.position.y = 330 if world.phase == "end" else 130
