extends MenuScreen
## Lobby (start screen):
##   top left     level badge, name, XP bar
##   top right    settings and quit
##   left         Christmas event banner, then Locker, Statistics, Store (soon)
##   middle       the player's character (drawn by MainMenu in 3D)
##   right        game mode card (mode and map, opens the mode selection)
##   bottom       quick statistics and the big Play button

var _mode_tween: Tween


func _ready() -> void:
	bind_button(%Play, _play)
	bind_button(%ModeCard, func(): menu.show_screen("Modes"))
	bind_button(%Locker, func(): menu.show_screen("Locker"))
	bind_button(%Settings, func(): menu.show_screen("Settings"))
	bind_button(%Stats, func(): menu.show_screen("Stats"))
	bind_button(%Quit, func(): menu.request_quit())
	# The Store is not available yet: its row is disabled ("SOON").
	%Event.visible = Holiday.ENABLED
	if Holiday.ENABLED:
		_put_hat_on_brand()
	%ModeCard.mouse_entered.connect(func(): _hover_mode_card(true))
	%ModeCard.mouse_exited.connect(func(): _hover_mode_card(false))


func enter(_arg: Variant) -> void:
	%PlayerName.text = Config.player_name

	# Level badge and progress inside the current level.
	var info := Progression.level_info(Config.xp)
	%Level.text = str(info.level)
	%LevelText.text = "LEVEL %d" % info.level
	UiMotion.pop(%Badge, 1.08, 0.38)
	UiMotion.fill_bar(%XpBar, float(info.into) / float(info.needed), 0.65)
	%XpText.text = "%d / %d XP" % [info.into, info.needed]

	# Selected game mode and map.
	var mode := ModeDB.get_mode(Config.selected_mode)
	%ModeName.text = mode.display_name.to_upper()
	%PlaySub.text = "%s · LAN" % mode.display_name.to_upper()
	%ModeIcon.texture = ModeArt.icon(mode)
	%ModeRule.text = "%s · %s" % [ModeArt.rule(mode), ModeArt.hint(mode)]
	%ModeWatermark.texture = ModeArt.watermark(mode)
	_fill_weapon_strip(%ModeWeapons, mode)
	UiMotion.pop(%ModeIcon, 1.16, 0.36)
	if Config.selected_map >= 0:
		%MapName.text = MapDB.display_name(Config.selected_map)
		%MapThumb.texture = map_thumbnail(Config.selected_map)
		%MapThumb.visible = true
		UiMotion.pop(%MapThumb, 1.08, 0.34)
	else:
		%MapName.text = "Random map"
		%MapThumb.visible = false

	var s := Config.stats
	var kills := int(s.get("kills", 0))
	var deaths := int(s.get("deaths", 0))
	var wins := int(s.get("wins", 0))
	# Numbers count up, so returning from a match feels like a reward.
	UiMotion.count_up(%QuickKills, 0, kills, 0.6)
	UiMotion.count_up(%QuickKd, 0.0, float(kills) / maxf(1.0, float(deaths)), 0.7, "%.2f")
	UiMotion.count_up(%QuickWins, 0, wins, 0.65)


## Weapon silhouettes under the mode name (the first few items of the loadout).
func _fill_weapon_strip(strip: HBoxContainer, mode: GameModeData) -> void:
	for child in strip.get_children():
		child.queue_free()
	var icons := ModeArt.loadout_icons(mode, 6)
	for texture in icons:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(31, 17)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color(1, 1, 1, 0.62)
		strip.add_child(icon)
	var extra := ModeArt.weapons(mode).size() - icons.size()
	if extra > 0:
		var more := Label.new()
		more.text = "+%d" % extra
		more.theme_type_variation = &"Caption"
		more.add_theme_font_size_override("font_size", 10)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(more)


## Hovering the mode card reveals its weapon art a little more.
func _hover_mode_card(on: bool) -> void:
	if _mode_tween and _mode_tween.is_valid():
		_mode_tween.kill()
	_mode_tween = create_tween().set_parallel()
	_mode_tween.tween_property(%ModeWatermark, "modulate:a", 0.16 if on else 0.07, 0.22)
	_mode_tween.tween_property(%ModeWeapons, "modulate:a", 1.0 if on else 0.82, 0.2)


## Christmas edition: a Santa hat on the "O" of the OPENSHOOTER wordmark.
func _put_hat_on_brand() -> void:
	var brand := $Content/Brand as RichTextLabel
	var font := brand.get_theme_font("normal_font")
	var font_size := brand.get_theme_font_size("normal_font_size")
	var text_width := font.get_string_size("OPENSHOOTER", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var o_width := font.get_string_size("O", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var hat := TextureRect.new()
	hat.name = "SantaHat"
	hat.texture = load(Holiday.HAT_PATH)
	hat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hat.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	hat.size = Vector2(34, 28)
	hat.pivot_offset = Vector2(14, 23)
	hat.rotation = deg_to_rad(-14.0)
	hat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centred on the O; the italic O leans right, so the hat sits a little
	# to the right of the glyph's box.
	var o_left := (brand.size.x - text_width) / 2.0
	hat.position = Vector2(o_left + o_width / 2.0 - 11.0, -14.0)
	brand.clip_contents = false
	brand.add_child(hat)


## Picture of a map (rendered by tools/render_ui_images.gd).
static func map_thumbnail(map_index: int) -> Texture2D:
	return load("res://assets/ui/maps/%s.png" % MapDB.info(map_index).id)


## Play opens the selected mode's screen: its LAN servers, quick play with
## bots, create server and join with a code.
func _play() -> void:
	menu.show_screen("Browser")
