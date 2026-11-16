class_name Scoreboard
extends PanelContainer
## Scoreboard (TAB): player, kills and deaths, from best to worst.

@onready var rows: VBoxContainer = %Rows


## Player IDs sorted by kills.
static func ranking() -> Array:
	var ids := Net.players.keys()
	ids.sort_custom(func(a, b): return int(Net.players[a].kills) > int(Net.players[b].kills))
	return ids


func refresh() -> void:
	for c in rows.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var order := ranking()
	for i in order.size():
		var id: int = order[i]
		var info: Dictionary = Net.players[id]
		var mine: bool = id == me
		var row := PanelContainer.new()
		row.theme_type_variation = &"ScoreRowPanel" if i % 2 == 0 else &"ScoreRowPanelAlt"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := &"ScoreRowMine" if mine else &"ScoreRow"
		var name_label := _cell(str(info.name) + ("  ◄" if mine else ""), style, 0, HORIZONTAL_ALIGNMENT_LEFT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(_cell(str(int(info.kills)), style, 76, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(_cell(str(int(info.deaths)), &"ScoreRow", 76, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(line)
		rows.add_child(row)


func _cell(text: String, variation: StringName, min_width: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.custom_minimum_size = Vector2(min_width, 0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
