extends MenuScreen
## The player's saved statistics and performance chart.

## Small icon in the corner of each card.
const CARD_ICONS := {
	"KillsCard": preload("res://assets/ui/icons/kill.svg"),
	"DeathsCard": preload("res://assets/ui/icons/death.svg"),
	"RatioCard": preload("res://assets/ui/icons/ratio.svg"),
	"HeadshotsCard": preload("res://assets/ui/icons/headshot.svg"),
	"MatchesCard": preload("res://assets/ui/icons/match.svg"),
	"WinsCard": preload("res://assets/ui/icons/win.svg"),
	"WinRateCard": preload("res://assets/ui/icons/percent.svg"),
	"BestMatchCard": preload("res://assets/ui/icons/best.svg"),
}

@onready var chart: StatsChart = %Chart


func _ready() -> void:
	bind_button(%Back, func(): menu.show_screen("Home"))
	# Icons are added in code: the cards keep their original layout, and the
	# picture simply sits in the top-right corner. The card is a container, so
	# the corner comes from the shrink flags (anchors are ignored there); the
	# number stays the focus, the icon is small and quiet. The SVGs import at
	# 2x so they stay sharp.
	var grid := $Content/Grid
	for card_name in CARD_ICONS:
		var card := grid.get_node_or_null(card_name) as Control
		if card == null:
			continue
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = CARD_ICONS[card_name]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color(0.659, 0.686, 0.733, 0.55)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_END
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.add_child(icon)


func enter(_arg: Variant) -> void:
	var s := Config.stats
	var kills := int(s.get("kills", 0))
	var deaths := int(s.get("deaths", 0))
	var matches := int(s.get("matches", 0))
	var wins := int(s.get("wins", 0))
	var headshots := int(s.get("headshots", 0))
	var history: Array = s.get("history", [])
	var best := 0
	for entry in history:
		best = maxi(best, int(entry.get("kills", 0)))
	UiMotion.count_up(%Kills, 0, kills, 0.55)
	UiMotion.count_up(%Deaths, 0, deaths, 0.55)
	UiMotion.count_up(%Ratio, 0.0, float(kills) / maxf(1.0, float(deaths)), 0.65, "%.2f")
	UiMotion.count_up(%Headshots, 0, headshots, 0.6)
	UiMotion.count_up(%Matches, 0, matches, 0.6)
	UiMotion.count_up(%Wins, 0, wins, 0.6)
	UiMotion.count_up(%WinRate, 0.0, 100.0 * float(wins) / maxf(1.0, float(matches)), 0.7, "%d%%")
	UiMotion.count_up(%BestMatch, 0, best, 0.65)
	chart.set_history(history)
