extends MenuScreen
## Estatísticas salvas do jogador.


func _ready() -> void:
	bind_button(%Back, func(): menu.show_screen("Home"))


func enter(_arg: Variant) -> void:
	var s := Config.stats
	var kd := float(s.kills) / maxf(1.0, float(s.deaths))
	%Kills.text = str(s.kills)
	%Deaths.text = str(s.deaths)
	%Ratio.text = "%.2f" % kd
	%Headshots.text = str(s.headshots)
	%Matches.text = str(s.matches)
	%Wins.text = str(s.wins)
