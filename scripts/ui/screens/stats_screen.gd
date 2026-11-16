extends MenuScreen
## The player's saved statistics and performance chart.

@onready var chart: StatsChart = %Chart


func _ready() -> void:
	bind_button(%Back, func(): menu.show_screen("Home"))


func enter(_arg: Variant) -> void:
	var s := Config.stats
	var kills := int(s.get("kills", 0))
	var deaths := int(s.get("deaths", 0))
	var matches := int(s.get("matches", 0))
	var wins := int(s.get("wins", 0))
	var history: Array = s.get("history", [])
	var best := 0
	for entry in history:
		best = maxi(best, int(entry.get("kills", 0)))
	%Kills.text = str(kills)
	%Deaths.text = str(deaths)
	%Ratio.text = "%.2f" % (float(kills) / maxf(1.0, float(deaths)))
	%Headshots.text = str(int(s.get("headshots", 0)))
	%Matches.text = str(matches)
	%Wins.text = str(wins)
	%WinRate.text = "%d%%" % int(round(100.0 * float(wins) / maxf(1.0, float(matches))))
	%BestMatch.text = str(best)
	chart.set_history(history)
