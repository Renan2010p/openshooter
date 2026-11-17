extends MenuScreen
## Lobby (start screen):
##   top left     level badge, name, XP bar
##   top right    settings and quit
##   left         Christmas event banner, then Locker, Statistics, Store (soon)
##   middle       the player's character (drawn by MainMenu in 3D)
##   right        game mode card (mode and map, opens the mode selection)
##   bottom       quick statistics and the big Play button


func _ready() -> void:
	bind_button(%Play, _play)
	bind_button(%ModeCard, func(): menu.show_screen("Modes"))
	bind_button(%Locker, func(): menu.show_screen("Locker"))
	bind_button(%Settings, func(): menu.show_screen("Settings"))
	bind_button(%Stats, func(): menu.show_screen("Stats"))
	bind_button(%Quit, func(): menu.request_quit())
	# The Store is not available yet: its row is disabled ("SOON").
	%Event.visible = Holiday.ENABLED


func enter(_arg: Variant) -> void:
	%PlayerName.text = Config.player_name

	# Level badge and progress inside the current level.
	var info := Progression.level_info(Config.xp)
	%Level.text = str(info.level)
	%LevelText.text = "LEVEL %d" % info.level
	%XpBar.value = float(info.into) / float(info.needed)
	%XpText.text = "%d / %d XP" % [info.into, info.needed]

	# Selected game mode and map.
	var mode := ModeDB.get_mode(Config.selected_mode)
	%ModeName.text = mode.display_name.to_upper()
	%PlaySub.text = "%s · LAN" % mode.display_name.to_upper()
	if Config.selected_map >= 0:
		%MapName.text = MapDB.display_name(Config.selected_map)
		%MapThumb.texture = map_thumbnail(Config.selected_map)
		%MapThumb.visible = true
	else:
		%MapName.text = "Random map"
		%MapThumb.visible = false

	var s := Config.stats
	var kills := int(s.get("kills", 0))
	var deaths := int(s.get("deaths", 0))
	%QuickKills.text = str(kills)
	%QuickKd.text = "%.2f" % (float(kills) / maxf(1.0, float(deaths)))
	%QuickWins.text = str(int(s.get("wins", 0)))


## Picture of a map (rendered by tools/render_ui_images.gd).
static func map_thumbnail(map_index: int) -> Texture2D:
	return load("res://assets/ui/maps/%s.png" % MapDB.info(map_index).id)


## Play opens the selected mode's screen: its LAN servers, quick play with
## bots, create server and join with a code.
func _play() -> void:
	menu.show_screen("Browser")
