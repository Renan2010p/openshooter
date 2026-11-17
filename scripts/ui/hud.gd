class_name Hud
extends CanvasLayer
## In-match interface — scenes/ui/hud.tscn. Nodes are found by their unique name
## (%Name), so the layout can be rearranged freely in the editor.

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
@onready var timer_label: AnimatedNumber = %Timer
@onready var time_bar: ProgressBar = %TimeBar
@onready var leaders: Array[Label] = [%First, %Second, %Third]
@onready var kill_feed: VBoxContainer = %KillFeed
@onready var fps_label: Label = %FpsLabel
@onready var server_info: Label = %ServerInfo
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_value: AnimatedNumber = %HealthValue
@onready var hotbar: HBoxContainer = %Hotbar
@onready var weapon_name: Label = %WeaponName
@onready var ammo_label: AnimatedNumber = %Ammo
@onready var ammo_reserve: Label = %AmmoReserve
@onready var reload_hint: Label = %ReloadHint
@onready var death_label: Label = %DeathLabel
@onready var toast_label: Label = %Toast
@onready var end_label: Label = %EndLabel
@onready var reward_card: PanelContainer = %RewardCard
@onready var reward_total: Label = %RewardTotal
@onready var reward_label: Label = %RewardLabel
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
var _health_fill: StyleBoxFlat


func _ready() -> void:
	_health_fill = (health_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	health_bar.add_theme_stylebox_override("fill", _health_fill)
	pause_menu.resume_pressed.connect(toggle_pause)
	pause_menu.leave_pressed.connect(func(): world.leave_requested.emit())
	pause_menu.visible = false
	scoreboard.visible = false
	_ignore_informational_ui()
	touch_controls.pause_requested.connect(toggle_pause)
	if Touch.active:
		pause_menu.set_touch_help()
		_layout_mobile()
	var mode_name: String = {"normal": "Normal", "private": "Private", "duel": "Duel Only"}.get(Net.server_info.get("mode", "normal"), "")
	server_info.text = "%s  •  %s" % [Net.server_info.get("name", ""), mode_name]
	if Net.server_info.get("private", false) and Net.server_info.get("code", "") != "":
		server_info.text += "  •  Private Code: %s" % Net.server_info.code


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
			"Root/DeathLabel", "Root/Toast", "Root/FpsLabel", "Root/HitMarker",
			"Root/DamageIndicator", "Root/EndLabel"]:
		var node := get_node_or_null(path)
		if node:
			_make_ignore(node)


func _make_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_ignore(child)


## Re-arranges the HUD around the virtual controls on phones.
func _layout_mobile() -> void:
	hotbar.visible = false
	kill_feed.visible = false
	var bottom_left := $Root/BottomLeft as Control
	bottom_left.anchor_top = 0.0
	bottom_left.anchor_bottom = 0.0
	bottom_left.offset_left = 24.0
	bottom_left.offset_top = 142.0
	bottom_left.offset_right = 344.0
	bottom_left.offset_bottom = 232.0
	var score_hint := $Root/Scoreboard/Content/Hint as Label
	score_hint.text = "TAP SCORE TO TOGGLE"
	var ammo_box := $Root/AmmoBox as Control
	ammo_box.anchor_top = 0.0
	ammo_box.anchor_bottom = 0.0
	ammo_box.offset_left = -340.0
	ammo_box.offset_top = 16.0
	ammo_box.offset_right = -24.0
	ammo_box.offset_bottom = 120.0


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
		s.setup(i + 1, WeaponDB.get_data(loadout[i]).display_name)
		_slots.append(s)


func _on_phase_changed(phase: String) -> void:
	# The XP of the previous match is only shown on its match-over screen.
	if phase != "end":
		Config.last_reward = {}
	var voting := phase == "vote"
	vote_panel.visible = voting
	if voting:
		vote_panel.reset()
		vote_panel.show_state(world.match_manager.time_left, world.match_manager.map_votes, world.match_manager.mode_votes)
		UiMotion.pop_in(vote_panel)
		if not Touch.active:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not paused and not Touch.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## XP earned in the match that just ended, in a card beside the scoreboard:
##   +310 XP
##   Match played      +50
##   6 eliminations    +60
##   Victory          +250
##   LEVEL UP!  Level 4
func _update_reward(end_now: bool) -> void:
	var reward := Config.last_reward
	var show := end_now and not reward.is_empty()
	if show and not reward_card.visible:
		UiMotion.pop_in(reward_card, 0.3)
	reward_card.visible = show
	if not show:
		return
	reward_total.text = "+%d XP" % reward.total
	var text := ""
	for line in reward.lines:
		text += "%s   +%d\n" % [line[0], line[1]]
	if int(reward.level_after) > int(reward.level_before):
		text += "\nLEVEL UP!  Level %d" % reward.level_after
	reward_label.text = text.strip_edges()


func hitmarker(head: bool) -> void:
	_pop_marker(Color(1, 0.25, 0.2) if head else Color.WHITE, 1.35 if head else 1.2, 0.22)


## Bigger, longer red marker when the local player gets the elimination.
func kill_confirmed(head: bool) -> void:
	_pop_marker(Color(1, 0.18, 0.14), 1.9 if head else 1.6, 0.45)
	crosshair.flash(Color(1, 0.3, 0.25))


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


func feed(text: String) -> void:
	if not kill_feed.visible:
		return
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"FeedChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"FeedLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.add_child(l)
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


func show_death(by: String, seconds: float) -> void:
	_death_by = by
	_death_t = seconds


func hide_death() -> void:
	_death_t = 0.0


func toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 2.0
	toast_label.pivot_offset = toast_label.size / 2.0
	toast_label.scale = Vector2(0.85, 0.85)
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_label, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func shake(amount: float) -> void:
	if not Config.screen_shake:
		return
	_shake = maxf(_shake, amount)
	_shake_t = randf() * 100.0


func toggle_pause() -> void:
	paused = not paused
	pause_menu.visible = paused
	if paused:
		UiMotion.pop_in(pause_menu)
	if not Touch.active:
		var free_mouse := paused or world.match_manager.phase == "vote"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	if world == null:
		return
	_update_player()
	_update_timers(delta)
	var show_board := Input.is_action_pressed("scoreboard") or Touch.scoreboard_held or world.match_manager.phase == "end"
	if show_board and not scoreboard.visible:
		UiMotion.pop_in(scoreboard)
	scoreboard.visible = show_board
	modal_dim.visible = paused or scoreboard.visible or vote_panel.visible
	var show_touch := Touch.active and not paused and not vote_panel.visible and world.match_manager.phase != "end"
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
		scoreboard.refresh()


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
	health_bar.value = hp
	health_value.text = str(hp)
	var health_color: Color = health_colors[2] if hp > 50 else (health_colors[1] if hp > 25 else health_colors[0])
	health_value.set_text_color(health_color)
	_health_fill.bg_color = health_color
	weapon_name.text = w.display_name
	reload_hint.visible = p.weapons.is_reloading()
	if w.is_melee():
		ammo_label.text = "∞"
		ammo_reserve.text = ""
	elif w.is_equipment():
		ammo_label.text = str(p.weapons.mag())
		ammo_reserve.text = ""
	else:
		ammo_label.text = str(p.weapons.mag())
		ammo_reserve.text = "/ %d" % p.weapons.reserve()
	if _hooked != p:
		_hooked = p
		p.weapons.loadout_changed.connect(rebuild_hotbar)
		rebuild_hotbar(p.weapons.loadout)
	for i in _slots.size():
		_slots[i].set_selected(_slot_weapons[i] == p.weapons.index)
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
	toast_label.modulate.a = minf(1.0, _toast_t * 2.0)
	if _death_t > 0.0:
		_death_t = maxf(0.0, _death_t - delta)
		death_label.text = "Killed by %s\nRespawning in %d..." % [_death_by, ceili(_death_t)]
	var show_death := _death_t > 0.0
	if show_death and not _death_shown:
		death_label.modulate.a = 0.0
		death_label.pivot_offset = death_label.size / 2.0
		death_label.scale = Vector2(1.15, 1.15)
		var t := create_tween().set_parallel()
		t.tween_property(death_label, "modulate:a", 1.0, 0.35)
		t.tween_property(death_label, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_death_shown = show_death
	death_label.visible = show_death


func _update_match() -> void:
	var mm := world.match_manager
	var t := maxi(0, ceili(mm.time_left))
	timer_label.text = "%02d:%02d" % [t / 60, t % 60]
	time_bar.value = 100.0 * clampf(mm.time_left / maxf(mm.duration(), 1.0), 0.0, 1.0)
	var ranking := Scoreboard.ranking()
	for i in leaders.size():
		if i < ranking.size():
			var info: Dictionary = Net.players[ranking[i]]
			leaders[i].text = "%s  ·  %d" % [info.name, int(info.kills)]
		else:
			leaders[i].text = "Nobody"
	if mm.phase == "vote":
		vote_panel.show_state(mm.time_left, mm.map_votes, mm.mode_votes)
	var mode := world.mode()
	mode_label.text = "Mode: %s  •  Map: %s" % [mode.display_name, MapDB.display_name(world.map_index)]
	if mode.is_gun_game() and world.local_player:
		var level := world.level_of(world.local_player.pid)
		mode_label.text += "  •  Weapon %d of %d" % [level + 1, mode.progression.size()]
	var end_now := mm.phase == "end"
	if end_now and not end_label.visible:
		UiMotion.pop_in(end_label, 0.24)
	end_label.visible = end_now
	end_label.text = "MATCH OVER\nWinner: %s" % mm.winner
	_update_reward(end_now)
	fps_label.visible = Config.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
