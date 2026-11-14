class_name Scoreboard
extends PanelContainer
## Placar (TAB): jogador, abates e mortes, do melhor para o pior.

@onready var grid: GridContainer = %Grid


## IDs dos jogadores ordenados por abates.
static func ranking() -> Array:
	var ids := Net.players.keys()
	ids.sort_custom(func(a, b): return int(Net.players[a].kills) > int(Net.players[b].kills))
	return ids


func refresh() -> void:
	for c in grid.get_children():
		if not c.has_meta("header"):
			c.queue_free()
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	for id in ranking():
		var info: Dictionary = Net.players[id]
		var mine: bool = id == me
		for text in [str(info.name) + ("  ◄" if mine else ""), str(int(info.kills)), str(int(info.deaths))]:
			var l := Label.new()
			l.text = text
			l.theme_type_variation = &"ScoreRowMine" if mine else &"ScoreRow"
			grid.add_child(l)
