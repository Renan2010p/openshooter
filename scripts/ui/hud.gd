class_name Hud
extends CanvasLayer
## In-match interface — scenes/ui/hud.tscn. Nodes are found by their unique name
## (%Name), so the layout can be rearranged freely in the editor.

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")
const FEED_FONT := preload("res://assets/fonts/Barlow-Bold.ttf")

## Health bar color: low, medium, high.
@export var health_colors: Array[Color] = [Color("#c7161f"), Color("#ff8a1f"), Color("#a9d8ff")]
@export var feed_max_lines := 6
@export var feed_line_seconds := 6.0

var world: World
var paused := false
## In-match chat (built in code, see _build_chat()).
var chat: ChatBox

@onready var scope_overlay: ColorRect = %ScopeOverlay
@onready var damage_vignette: ColorRect = %DamageVignette
@onready var crosshair: Crosshair = %Crosshair
@onready var hit_marker: Label = %HitMarker
@onready var damage_indicator: Label = %DamageIndicator
@onready var timer_label: AnimatedNumber = %Timer
@onready var time_bar: ProgressBar = %TimeBar
@onready var leaders: Array[Label] = [%First, %Second, %Third]
@onready var map_label: Label = %MapLabel
@onready var rank_label: Label = %RankLabel
@onready var kill_feed: VBoxContainer = %KillFeed
@onready var fps_label: Label = %FpsLabel
@onready var server_info: Label = %ServerInfo
@onready var health_bar: SegmentBar = %HealthBar
@onready var health_value: AnimatedNumber = %HealthValue
@onready var hotbar: HBoxContainer = %Hotbar
@onready var weapon_name: Label = %WeaponName
@onready var weapon_icon: TextureRect = %WeaponIcon
@onready var ammo_label: AnimatedNumber = %Ammo
@onready var ammo_reserve: Label = %AmmoReserve
@onready var reload_hint: Label = %ReloadHint
@onready var reload_key: Label = %Key
@onready var ammo_bar: ProgressBar = %AmmoBar
@onready var death_screen: Control = %DeathScreen
@onready var respawn_ring: CountdownRing = %RespawnRing
@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %Toast
@onready var toast_accent: Label = %ToastAccent
@onready var scoreboard: Scoreboard = %Scoreboard
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var vote_panel: VotePanel = %VotePanel
@onready var mode_label: Label = %ModeLabel
@onready var modal_dim: ColorRect = %ModalDim
@onready var touch_controls: TouchControls = %TouchControls

var _hit_tween: Tween
var _toast_tween: Tween
var _shake_t := 0.0
var _scope_aspect := -1.0
var _death_shown := false
var _dmg_t := 0.0
var _dir_t := 0.0
var _death_t := 0.0
var _death_by := ""
var _toast_t := 0.0
var _shake := 0.0
var _slow_t := 0.0
var _slots: Array[HotbarSlot] = []
var _slot_weapons: Array[int] = []
var _hooked: Player
var _death_total := 1.0
var _key_on := _key_style(true)
var _key_off := _key_style(false)
var _shown_weapon := -1


func _ready() -> void:
	timer_label.set_text_color(Color.WHITE)
	# The tilted ELIMINATED band turns around its own centre.
	var band: Control = %Band
	band.resized.connect(func(): band.pivot_offset = band.size / 2.0)
	pause_menu.resume_pressed.connect(toggle_pause)
	pause_menu.leave_pressed.connect(func(): world.leave_requested.emit())
	pause_menu.visible = false
	scoreboard.visible = false
	_ignore_informational_ui()
	touch_controls.pause_requested.connect(toggle_pause)
	_build_chat()
	touch_controls.chat_requested.connect(chat.open)
	if Touch.active:
		pause_menu.set_touch_help()
		_layout_mobile()
	server_info.text = "%s · LV %d" % [Config.player_name.to_upper(), int(Progression.level_info(Config.xp).level)]
	if Net.server_info.get("private", false) and Net.server_info.get("code", "") != "":
		server_info.text += "  ·  CODE %s" % Net.server_info.code


## Chat over the game: bottom left above the health on a computer, under the
## top-left buttons on a phone (the move stick takes the bottom left there).
func _build_chat() -> void:
	chat = ChatBox.new()
	chat.name = "Chat"
	$Root.add_child(chat)
	if Touch.active:
		chat.set_anchors_preset(Control.PRESET_TOP_LEFT)
		chat.offset_left = 20.0
		chat.offset_top = 96.0
		chat.offset_right = 440.0
		chat.offset_bottom = 330.0
	else:
		chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		chat.offset_left = 22.0
		chat.offset_top = -380.0
		chat.offset_right = 482.0
		chat.offset_bottom = -132.0
	chat.can_open = func() -> bool: return not paused
	chat.typing_changed.connect(_on_chat_typing)


## Typing frees the mouse (the player stops); closing gives it back to the game
## unless a menu still needs it.
func _on_chat_typing(on: bool) -> void:
	if Touch.active:
		return
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not paused and not vote_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Called by [World] when it is ready (children become ready before the parent).
func setup(w: World) -> void:
	world = w
	vote_panel.voted.connect(func(map_idx, mode_idx): world.match_manager.cast_vote.rpc_id(1, map_idx, mode_idx))
	world.match_manager.phase_changed.connect(_on_phase_changed)
	world.match_manager.votes_changed.connect(func(m, d): vote_panel.show_state(world.match_manager.time_left, m, d))
	# Read the phase only on the next frame (voting may start before that).
	(func(): _on_phase_changed(world.match_manager.phase)).call_deferred()


## Informational HUD nodes must not steal touches from the look area.
func _ignore_informational_ui() -> void:
	for path in ["Root/TopBar", "Root/BottomLeft", "Root/AmmoBox", "Root/Hotbar",
			"Root/DeathScreen", "Root/ToastBox", "Root/FpsLabel", "Root/HitMarker",
			"Root/DamageIndicator"]:
		var node := get_node_or_null(path)
		if node:
			_make_ignore(node)


func _make_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_ignore(child)


## Phone layout (the touch controls bring their own weapon switcher):
## small health at the top left beside the pause and scoreboard buttons, the
## clock alone at the top with a one-line rank chip, the kill feed top right.
func _layout_mobile() -> void:
	hotbar.visible = false
	$Root/AmmoBox.visible = false
	for path in ["Root/TopBar/Clock/ModePlate", "Root/TopBar/Clock/RankPlate", "Root/TopBar/TimeBar",
			"Root/TopBar/Leaders", "Root/BottomLeft/ServerInfo", "Root/BottomLeft/HealthHeader/Plus"]:
		(get_node(path) as CanvasItem).visible = false
	%MobileChip.visible = true
	var bottom_left := $Root/BottomLeft as Control
	bottom_left.anchor_top = 0.0
	bottom_left.anchor_bottom = 0.0
	bottom_left.offset_left = 200.0
	bottom_left.offset_top = 10.0
	bottom_left.offset_right = 520.0
	bottom_left.offset_bottom = 90.0
	bottom_left.scale = Vector2(0.58, 0.58)
	scoreboard.hint = "TAP THE MENU BUTTON TO TOGGLE"


# ------------------------------------------------------------------ events

## Builds the weapon hotbar from what the mode gives the player.
func rebuild_hotbar(loadout: Array[int]) -> void:
	if Touch.active:
		return
	for c in hotbar.get_children():
		c.queue_free()
	_slots.clear()
	_slot_weapons = loadout.duplicate()
	for i in loadout.size():
		var s: HotbarSlot = SLOT_SCENE.instantiate()
		hotbar.add_child(s)
		s.setup(i + 1, loadout[i])
		_slots.append(s)

func _on_phase_changed(phase: String) -> void:
	# The XP of the previous match stays on its match-over screen.
	if phase == "play":
		Config.last_reward = {}
	# Match over: results first, then the vote, on the same screen.
	var over := phase == "end" or phase == "vote"
	if over and not vote_panel.visible:
		vote_panel.reset(world)
		UiMotion.pop_in(vote_panel)
	vote_panel.visible = over
	# Music only on the match-over screen; silence while playing.
	if over:
		Music.play("results")
	else:
		Music.stop()
	if over:
		vote_panel.show_state(world.match_manager.time_left, world.match_manager.map_votes, world.match_manager.mode_votes)
		hide_death()
		if not Touch.active:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not paused and not Touch.active and not chat.typing:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func hitmarker(head: bool) -> void:
	_pop_marker(Color("#ff8a1f") if head else Color.WHITE, 1.35 if head else 1.2, 0.22)


## Elimination by the local player: orange diamond around the crosshair.
func kill_confirmed(_head: bool) -> void:
	# The orange diamond replaces the hit cross for eliminations.
	hit_marker.visible = false
	crosshair.flash(Color("#ff8a1f"))
	crosshair.kill_mark()


func _pop_marker(color: Color, start_scale: float, duration: float) -> void:
	hit_marker.add_theme_color_override("font_color", color)
	hit_marker.pivot_offset = hit_marker.size / 2.0
	hit_marker.visible = true
	hit_marker.modulate.a = 1.0
	hit_marker.scale = Vector2.ONE * start_scale
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = create_tween().set_parallel()
	_hit_tween.tween_property(hit_marker, "scale", Vector2.ONE * 0.9, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(hit_marker, "modulate:a", 0.0, duration * 0.6).set_delay(duration * 0.4)
	_hit_tween.chain().tween_callback(func(): hit_marker.visible = false)


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


## A plain line in the kill feed ("X left the match").
func feed(text: String) -> void:
	if not kill_feed.visible:
		return
	var chip := _feed_chip(false)
	chip.get_child(0).add_child(_feed_label(text, Color("#f2f1ec")))
	_push_feed(chip)


## An elimination in the kill feed: attacker, weapon silhouette, victim.
## `mine` (the local player got it) gets the orange bar and name.
func feed_kill(attacker: String, victim: String, weapon: int, head: bool, mine: bool) -> void:
	if not kill_feed.visible:
		return
	var chip := _feed_chip(mine)
	var row := chip.get_child(0)
	row.add_child(_feed_label(attacker, Color("#ff8a1f") if mine else Color("#f2f1ec")))
	var icon := TextureRect.new()
	icon.texture = weapon_texture(weapon)
	icon.custom_minimum_size = Vector2(44, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	if head:
		var tag := _feed_label("HS", Color("#ff8a1f"))
		tag.add_theme_font_size_override("font_size", 11)
		row.add_child(tag)
	row.add_child(_feed_label(victim, Color("#f2f1ec")))
	_push_feed(chip)


## The key chip of "R RELOAD": solid when it matters, outlined otherwise.
static func _key_style(on: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	style.bg_color = Color("#ff8a1f") if on else Color(0, 0, 0, 0)
	style.border_color = Color("#a8afbb")
	style.set_border_width_all(0 if on else 1)
	return style


## The silhouette picture of a weapon (assets/ui/weapons, white: tint it).
static func weapon_texture(weapon: int) -> Texture2D:
	return load("res://assets/ui/weapons/%s.png" % WeaponDB.get_data(weapon).resource_path.get_file().get_basename())


func _feed_chip(mine: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"FeedChipMine" if mine else &"FeedChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.custom_minimum_size = Vector2(0, 32)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	return chip


func _feed_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FEED_FONT)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _push_feed(chip: PanelContainer) -> void:
	kill_feed.add_child(chip)
	if kill_feed.get_child_count() > feed_max_lines:
		kill_feed.get_child(0).queue_free()
	# Enter: grows in from the right edge with a fade. Exit: fades out.
	chip.modulate.a = 0.0
	chip.scale = Vector2(1.12, 1.12)
	chip.resized.connect(func(): chip.pivot_offset = Vector2(chip.size.x, chip.size.y / 2.0))
	var t := chip.create_tween()
	t.tween_property(chip, "modulate:a", 1.0, 0.16)
	t.parallel().tween_property(chip, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(maxf(0.0, feed_line_seconds - 0.5))
	t.tween_property(chip, "modulate:a", 0.0, 0.34)
	t.tween_callback(chip.queue_free)


## The ELIMINATED screen: who, with what, and the respawn countdown.
## `weapon` < 0 means no weapon (fell, blew up).
func show_death(by: String, seconds: float, weapon := -1, head := false) -> void:
	_death_by = by
	_death_t = seconds
	_death_total = maxf(seconds, 0.1)
	%DeathBy.text = by.to_upper()
	var icon: TextureRect = %DeathWeapon
	icon.visible = weapon >= 0
	var detail := ""
	if weapon >= 0:
		icon.texture = weapon_texture(weapon)
		detail = WeaponDB.get_data(weapon).display_name
	if head:
		detail += " · Headshot"
	%DeathDetail.text = detail


func hide_death() -> void:
	_death_t = 0.0


## A short message under the crosshair; `accent` follows it in orange
## ("ELIMINATED" + "BOT MIA · HEADSHOT").
func toast(text: String, accent := "") -> void:
	toast_label.text = text.to_upper()
	toast_accent.text = accent.to_upper()
	toast_accent.visible = accent != ""
	_toast_t = 2.0
	toast_panel.pivot_offset = toast_panel.size / 2.0
	toast_panel.scale = Vector2(0.85, 0.85)
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func shake(amount: float) -> void:
	if not Config.screen_shake:
		return
	_shake = maxf(_shake, amount)
	_shake_t = randf() * 100.0


func toggle_pause() -> void:
	chat.close()
	paused = not paused
	pause_menu.visible = paused
	if paused:
		UiMotion.pop_in(pause_menu)
	if not Touch.active:
		var free_mouse := paused or vote_panel.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	if world == null:
		return
	_update_player()
	_update_timers(delta)
	# TAB shows the scoreboard; the pause menu shows it beside its panel.
	var playing := world.match_manager.phase == "play"
	var show_board := playing and (paused or Input.is_action_pressed("scoreboard") or Touch.scoreboard_held)
	if show_board and not scoreboard.visible:
		UiMotion.pop_in(scoreboard)
		scoreboard.refresh(world)
	scoreboard.visible = show_board
	# Beside the pause panel, or centred on its own.
	scoreboard.offset_left = 420.0 if paused else 180.0
	scoreboard.offset_right = -40.0 if paused else -180.0
	modal_dim.visible = paused or scoreboard.visible or vote_panel.visible
	# Panels over the match: the gameplay HUD steps back behind them.
	var hud_alpha := 0.0 if modal_dim.visible else 1.0
	for node: CanvasItem in [$Root/TopBar, $Root/Hotbar, $Root/AmmoBox, $Root/BottomLeft, kill_feed, crosshair]:
		node.modulate.a = hud_alpha
	# On top of the match screens, but not over the pause menu.
	chat.visible = not paused
	var show_touch := Touch.active and not paused and not vote_panel.visible and world.match_manager.phase != "end" \
		and not chat.typing
	if touch_controls.visible != show_touch:
		touch_controls.visible = show_touch
		if not show_touch:
			touch_controls.reset()
	# The rest does not need to change every frame: 10 times per second.
	_slow_t -= delta
	if _slow_t > 0.0:
		return
	_slow_t = 0.1
	_update_match()
	if scoreboard.visible:
		scoreboard.refresh(world)


func _update_player() -> void:
	var p := world.local_player
	if p == null:
		return
	var w := p.weapons.data()
	var vp := get_viewport().get_visible_rect().size
	# Smooth crosshair: eases toward the current spread and blooms on each shot.
	var target_gap := 6.0 + p.weapons.spread() * 500.0 + p.weapons.kick * 7.0
	var dt := get_process_delta_time()
	crosshair.gap = lerpf(crosshair.gap, target_gap, minf(1.0, dt * 18.0))
	crosshair.visible = p.alive and not p.weapons.aiming and w.is_gun()
	scope_overlay.visible = p.weapons.scoped
	var aspect := vp.x / maxf(vp.y, 1.0)
	if scope_overlay.visible and aspect != _scope_aspect:
		_scope_aspect = aspect
		(scope_overlay.material as ShaderMaterial).set_shader_parameter("aspect", aspect)
	var hp := clampi(p.hp, 0, 100)
	health_bar.value = hp / 100.0
	health_value.text = str(hp)
	var health_color: Color = health_colors[2] if hp > 50 else (health_colors[1] if hp > 25 else health_colors[0])
	health_value.set_text_color(Color("#f2f1ec") if hp > 25 else health_color)
	health_bar.color = health_color
	weapon_name.text = w.display_name.to_upper()
	if _shown_weapon != p.weapons.index:
		_shown_weapon = p.weapons.index
		weapon_icon.texture = weapon_texture(p.weapons.index)
	# Magazine bar, and "R RELOAD": grey normally, orange when the magazine
	# runs low; "RELOADING" while it reloads.
	var reloading := p.weapons.is_reloading()
	var gun := w.is_gun()
	var low := gun and p.weapons.mag() <= maxi(1, w.magazine / 4) and p.weapons.reserve() > 0
	ammo_bar.visible = gun
	reload_hint.get_parent().visible = gun
	if gun:
		ammo_bar.value = 100.0 * p.weapons.mag() / maxf(1.0, w.magazine)
	reload_key.visible = not reloading
	reload_hint.text = "RELOADING" if reloading else "RELOAD"
	var alert := low or reloading
	reload_hint.add_theme_color_override("font_color", Color("#ff8a1f") if alert else Color("#a8afbb"))
	reload_key.add_theme_stylebox_override("normal", _key_on if low else _key_off)
	reload_key.add_theme_color_override("font_color", Color("#111111") if low else Color("#c4c9d2"))
	if w.is_melee():
		ammo_label.text = "∞"
		ammo_reserve.text = ""
	elif w.is_equipment():
		ammo_label.text = str(p.weapons.mag())
		ammo_reserve.text = ""
	else:
		ammo_label.text = str(p.weapons.mag())
		ammo_reserve.text = "/ %d" % p.weapons.reserve()
	if Touch.active:
		if w.is_melee():
			touch_controls.set_weapon(p.weapons.index, -1, -1)
		else:
			touch_controls.set_weapon(p.weapons.index, p.weapons.mag(), -1 if w.is_equipment() else p.weapons.reserve())
	if _hooked != p:
		_hooked = p
		p.weapons.loadout_changed.connect(rebuild_hotbar)
		rebuild_hotbar(p.weapons.loadout)
	for i in _slots.size():
		_slots[i].set_selected(_slot_weapons[i] == p.weapons.index)
		var slot_data := WeaponDB.get_data(_slot_weapons[i])
		_slots[i].set_count(p.weapons.ammo[_slot_weapons[i]][0] if slot_data.is_equipment() else -1)
	if p.local and is_instance_valid(p.camera):
		if _shake > 0.0:
			# Smooth, decaying shake (layered sines) instead of per-frame noise.
			_shake_t += dt * 38.0
			var amp := _shake * _shake * 0.3
			p.camera.h_offset = (sin(_shake_t) + 0.5 * sin(_shake_t * 2.3 + 1.7)) * amp
			p.camera.v_offset = (cos(_shake_t * 1.3) + 0.5 * sin(_shake_t * 2.9)) * amp
		elif p.camera.h_offset != 0.0 or p.camera.v_offset != 0.0:
			p.camera.h_offset = 0.0
			p.camera.v_offset = 0.0


func _update_timers(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta)
	_dmg_t = maxf(0.0, _dmg_t - delta)
	var alpha := _dmg_t * 0.5
	var p := world.local_player
	if p and p.alive and p.hp < 30:
		alpha = maxf(alpha, 0.15 + 0.08 * sin(Time.get_ticks_msec() / 200.0))
	damage_vignette.color.a = alpha
	_dir_t = maxf(0.0, _dir_t - delta)
	damage_indicator.modulate.a = _dir_t
	_toast_t = maxf(0.0, _toast_t - delta)
	toast_panel.modulate.a = minf(1.0, _toast_t * 2.0)
	if _death_t > 0.0:
		_death_t = maxf(0.0, _death_t - delta)
		respawn_ring.total = _death_total
		respawn_ring.left = _death_t
	var show_death := _death_t > 0.0
	if show_death and not _death_shown:
		var band: Control = %Band
		death_screen.modulate.a = 0.0
		band.scale = Vector2(1.0, 0.2)
		var t := create_tween().set_parallel()
		t.tween_property(death_screen, "modulate:a", 1.0, 0.3)
		t.tween_property(band, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_death_shown = show_death
	death_screen.visible = show_death
	# While dead, only the death screen (and the top bar) shows.
	for path in ["Root/BottomLeft", "Root/AmmoBox", "Root/Hotbar"]:
		# On phones the hotbar and the ammo block stay hidden (touch controls).
		(get_node(path) as Control).visible = not show_death and (path == "Root/BottomLeft" or not Touch.active)


func _update_match() -> void:
	var mm := world.match_manager
	var t := maxi(0, ceili(mm.time_left))
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	time_bar.value = 100.0 * clampf(mm.time_left / maxf(mm.duration(), 1.0), 0.0, 1.0)
	var ranking := Scoreboard.ranking()
	for i in leaders.size():
		var chip := leaders[i].get_parent() as Control
		chip.visible = i < ranking.size()
		if chip.visible:
			var info: Dictionary = Net.players[ranking[i]]
			leaders[i].text = "%d  %s · %d" % [i + 1, str(info.name).to_upper(), int(info.kills)]
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var rank := ranking.find(me) + 1
	var my_kills := int(Net.players[me].kills) if Net.players.has(me) else 0
	rank_label.text = "#%d · %d ELIMS" % [maxi(rank, 1), my_kills]
	%MobileInfo.text = "#%d · %d ELIMS · %s" % [maxi(rank, 1), my_kills, world.mode().display_name.to_upper()]
	if vote_panel.visible:
		vote_panel.show_state(mm.time_left, mm.map_votes, mm.mode_votes)
	var mode := world.mode()
	mode_label.text = mode.display_name.to_upper()
	map_label.text = MapDB.display_name(world.map_index)
	if mode.is_gun_game() and world.local_player:
		var level := world.level_of(world.local_player.pid)
		map_label.text += " · Weapon %d/%d" % [level + 1, mode.progression.size()]
	fps_label.visible = Config.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
