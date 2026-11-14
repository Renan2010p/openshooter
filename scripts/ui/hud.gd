class_name Hud
extends CanvasLayer
## Interface da partida — scenes/ui/hud.tscn. Os nós são encontrados pelo nome
## único (%Nome), então dá para reorganizar o layout à vontade no editor.

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")

@export var health_colors: Array[Color] = [Color(0.95, 0.2, 0.15), Color(0.95, 0.75, 0.1), Color(0.2, 0.85, 0.3)]
@export var feed_max_lines := 6
@export var feed_line_seconds := 6.0

var world: World
var paused := false

@onready var scope_overlay: ColorRect = %ScopeOverlay
@onready var damage_vignette: ColorRect = %DamageVignette
@onready var crosshair: Crosshair = %Crosshair
@onready var hit_marker: Label = %HitMarker
@onready var damage_indicator: Label = %DamageIndicator
@onready var timer_label: Label = %Timer
@onready var time_bar: ProgressBar = %TimeBar
@onready var leaders: Array[Label] = [%First, %Second, %Third]
@onready var kill_feed: VBoxContainer = %KillFeed
@onready var fps_label: Label = %FpsLabel
@onready var server_info: Label = %ServerInfo
@onready var health_bar: ProgressBar = %HealthBar
@onready var hotbar: HBoxContainer = %Hotbar
@onready var weapon_name: Label = %WeaponName
@onready var ammo_label: Label = %Ammo
@onready var death_label: Label = %DeathLabel
@onready var toast_label: Label = %Toast
@onready var end_label: Label = %EndLabel
@onready var scoreboard: Scoreboard = %Scoreboard
@onready var pause_menu: PauseMenu = %PauseMenu

var _hit_t := 0.0
var _dmg_t := 0.0
var _dir_t := 0.0
var _death_t := 0.0
var _death_by := ""
var _toast_t := 0.0
var _shake := 0.0
var _slow_t := 0.0
var _slots: Array[HotbarSlot] = []
var _health_fill: StyleBoxFlat


func _ready() -> void:
	for i in WeaponDB.count():
		var s: HotbarSlot = SLOT_SCENE.instantiate()
		hotbar.add_child(s)
		s.setup(i + 1, WeaponDB.get_data(i).display_name)
		_slots.append(s)
	_health_fill = (health_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	health_bar.add_theme_stylebox_override("fill", _health_fill)
	pause_menu.resume_pressed.connect(toggle_pause)
	pause_menu.leave_pressed.connect(func(): world.leave_requested.emit())
	pause_menu.visible = false
	scoreboard.visible = false
	var mode_name: String = {"normal": "Normal", "private": "Privado", "duel": "Apenas Duelos"}.get(Net.server_info.get("mode", "normal"), "")
	server_info.text = "%s  •  %s" % [Net.server_info.get("name", ""), mode_name]
	if Net.server_info.get("private", false) and Net.server_info.get("code", "") != "":
		server_info.text += "  •  Código Privado: %s" % Net.server_info.code


# ------------------------------------------------------------------ eventos

func hitmarker(head: bool) -> void:
	_hit_t = 0.2
	hit_marker.add_theme_color_override("font_color", Color(1, 0.25, 0.2) if head else Color.WHITE)


func damage() -> void:
	_dmg_t = 0.5


func damage_from(pos: Vector3) -> void:
	var p := world.local_player
	if p == null:
		return
	var to := pos - p.global_position
	var ang := angle_difference(p.rotation.y, atan2(-to.x, -to.z))
	var center := get_viewport().get_visible_rect().size / 2.0
	damage_indicator.position = center + Vector2(sin(-ang), -cos(ang)) * 120.0 - damage_indicator.size / 2.0
	_dir_t = 1.0


func feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"FeedLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kill_feed.add_child(l)
	if kill_feed.get_child_count() > feed_max_lines:
		kill_feed.get_child(0).queue_free()
	get_tree().create_timer(feed_line_seconds).timeout.connect(l.queue_free)


func show_death(by: String, seconds: float) -> void:
	_death_by = by
	_death_t = seconds


func hide_death() -> void:
	_death_t = 0.0


func toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 2.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func toggle_pause() -> void:
	paused = not paused
	pause_menu.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ atualização

func _process(delta: float) -> void:
	_update_player()
	_update_timers(delta)
	scoreboard.visible = Input.is_action_pressed("scoreboard") or world.match_manager.phase == "end"
	# O resto não precisa mudar a cada quadro: 10 vezes por segundo.
	_slow_t -= delta
	if _slow_t > 0.0:
		return
	_slow_t = 0.1
	_update_match()
	if scoreboard.visible:
		scoreboard.refresh()


func _update_player() -> void:
	var p := world.local_player
	if p == null:
		return
	var w := p.weapons.data()
	var vp := get_viewport().get_visible_rect().size
	crosshair.gap = 6.0 + p.weapons.spread() * 500.0
	crosshair.visible = p.alive and not p.weapons.scoped and w.is_gun()
	scope_overlay.visible = p.weapons.scoped
	(scope_overlay.material as ShaderMaterial).set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	var hp := clampi(p.hp, 0, 100)
	health_bar.value = hp
	_health_fill.bg_color = health_colors[2] if hp > 50 else (health_colors[1] if hp > 25 else health_colors[0])
	weapon_name.text = w.display_name
	if w.is_melee():
		ammo_label.text = "∞"
	elif w.is_mine():
		ammo_label.text = str(p.weapons.mag())
	elif p.weapons.is_reloading():
		ammo_label.text = "recarregando"
	else:
		ammo_label.text = "%d / %d" % [p.weapons.mag(), p.weapons.reserve()]
	for i in _slots.size():
		_slots[i].set_selected(i == p.weapons.index)
	if _shake > 0.0 and p.local and is_instance_valid(p.camera):
		p.camera.h_offset = randf_range(-1, 1) * _shake * 0.15
		p.camera.v_offset = randf_range(-1, 1) * _shake * 0.15


func _update_timers(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta)
	_hit_t = maxf(0.0, _hit_t - delta)
	hit_marker.visible = _hit_t > 0.0
	_dmg_t = maxf(0.0, _dmg_t - delta)
	var alpha := _dmg_t * 0.5
	var p := world.local_player
	if p and p.alive and p.hp < 30:
		alpha = maxf(alpha, 0.15 + 0.08 * sin(Time.get_ticks_msec() / 200.0))
	damage_vignette.color.a = alpha
	_dir_t = maxf(0.0, _dir_t - delta)
	damage_indicator.modulate.a = _dir_t
	_toast_t = maxf(0.0, _toast_t - delta)
	toast_label.modulate.a = minf(1.0, _toast_t * 2.0)
	if _death_t > 0.0:
		_death_t = maxf(0.0, _death_t - delta)
		death_label.text = "Eliminado por %s\nRenascendo em %d..." % [_death_by, ceili(_death_t)]
	death_label.visible = _death_t > 0.0


func _update_match() -> void:
	var mm := world.match_manager
	var t := maxi(0, ceili(mm.time_left))
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	time_bar.value = 100.0 * clampf(mm.time_left / maxf(mm.duration(), 1.0), 0.0, 1.0)
	var ranking := Scoreboard.ranking()
	for i in leaders.size():
		if i < ranking.size():
			var info: Dictionary = Net.players[ranking[i]]
			leaders[i].text = "%s\n%d eliminações" % [info.name, int(info.kills)]
		else:
			leaders[i].text = "Ninguém"
	end_label.visible = mm.phase == "end"
	end_label.text = "FIM DA PARTIDA\nVencedor: %s" % mm.winner
	fps_label.visible = Config.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
