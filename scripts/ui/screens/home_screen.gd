extends MenuScreen
## Start screen: Play, Locker, Settings, Statistics and Quit.


func _ready() -> void:
	bind_button(%Play, func(): menu.show_screen("Modes"))
	bind_button(%Locker, func(): menu.show_screen("Locker"))
	bind_button(%Settings, func(): menu.show_screen("Settings"))
	bind_button(%Stats, func(): menu.show_screen("Stats"))
	bind_button(%Quit, func(): menu.request_quit())


func enter(_arg: Variant) -> void:
	%PlayerName.text = Config.player_name
	var s := Config.stats
	var kills := int(s.get("kills", 0))
	var deaths := int(s.get("deaths", 0))
	%QuickKills.text = str(kills)
	%QuickKd.text = "%.2f" % (float(kills) / maxf(1.0, float(deaths)))
	%QuickMatches.text = str(int(s.get("matches", 0)))
