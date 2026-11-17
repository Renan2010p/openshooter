extends MenuScreen
## Lobby (start screen):
##   top bar     player name, level and XP, settings and quit
##   left        Christmas event banner, then Store (soon), Locker, Statistics
##   middle      the player's character (drawn by MainMenu in 3D)
##   top right   game mode card (opens the mode selection)
##   bottom      quick statistics and the big Play button


func _ready() -> void:
	bind_button(%Play, _play)
	bind_button(%ModeCard, func(): menu.show_screen("Modes"))
	bind_button(%Locker, func(): menu.show_screen("Locker"))
	bind_button(%Settings, func(): menu.show_screen("Settings"))
	bind_button(%Stats, func(): menu.show_screen("Stats"))
	bind_button(%Quit, func(): menu.request_quit())
	# The Store is not available yet: its button is disabled ("SOON").
	%Event.visible = Holiday.ENABLED


func enter(_arg: Variant) -> void:
	%PlayerName.text = Config.player_name

	# Level and progress inside the current level.
	var info := Progression.level_info(Config.xp)
	%Level.text = "LV %d" % info.level
	%XpBar.value = float(info.into) / float(info.needed)
	%XpText.text = "%d / %d XP" % [info.into, info.needed]

	# Selected game mode and map.
	var mode := ModeDB.get_mode(Config.selected_mode)
	%ModeName.text = mode.display_name.to_upper()
	%MapName.text = "Random map" if Config.selected_map < 0 else MapDB.display_name(Config.selected_map)

	var s := Config.stats
	var kills := int(s.get("kills", 0))
	var deaths := int(s.get("deaths", 0))
	%QuickKills.text = str(kills)
	%QuickKd.text = "%.2f" % (float(kills) / maxf(1.0, float(deaths)))
	%QuickWins.text = str(int(s.get("wins", 0)))


## Play opens the LAN server list for the selected mode: Duel servers for the
## Duel mode, normal servers for every other mode.
func _play() -> void:
	var mode := ModeDB.get_mode(Config.selected_mode)
	menu.show_screen("Browser", "duel" if mode.id == "duel" else "normal")
