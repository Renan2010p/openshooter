class_name Scoreboard
extends PanelContainer
## Scoreboard (TAB, and beside the pause menu): mode, map and time left, then
## one row per player from best to worst: rank, name (YOU / BOT tag), level,
## eliminations, deaths and K/D. Your row is orange.

const BLACK := preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
const BOLD := preload("res://assets/fonts/Barlow-Bold.ttf")
const SEMIBOLD := preload("res://assets/fonts/Barlow-SemiBold.ttf")
const ACCENT := Color("#ff8a1f")
const TEXT := Color("#f2f1ec")
const DIM := Color("#a8afbb")
## Column widths after the name (LEVEL, ELIMS, DEATHS, K/D) and of the rank.
const COLUMN := 90.0
const RANK := 50.0

## First part of the line under the table (changed on phones).
var hint := "HOLD TAB DURING THE MATCH TO SEE THE SCOREBOARD"

@onready var rows: VBoxContainer = %Rows

var _mine_style := _row_style(true)
var _row_style_plain := _row_style(false)


## Player IDs sorted by kills.
static func ranking() -> Array:
	var ids := Net.players.keys()
	ids.sort_custom(func(a, b): return int(Net.players[a].kills) > int(Net.players[b].kills))
	return ids


func refresh(world: World = null) -> void:
	if world:
		var mode := world.mode()
		var t := maxi(0, ceili(world.match_manager.time_left))
		%SbEyebrow.text = "%s  ·  %s  ·  LAN" % [mode.display_name.to_upper(), MapDB.display_name(world.map_index).to_upper()]
		%SbClock.text = "%02d:%02d" % [t / 60, t % 60]
	var humans := 0
	for id in Net.players:
		if not Net.players[id].get("bot", false):
			humans += 1
	%Hint.text = "%s  ·  SERVER: %s  ·  %d/%d PLAYERS" % [hint, str(Net.server_info.get("name", "")).to_upper(),
		humans, int(Net.server_info.get("max", 12))]
	for c in rows.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var order := ranking()
	for i in order.size():
		var id: int = order[i]
		rows.add_child(_make_row(i + 1, Net.players[id], id == me))


func _make_row(rank: int, info: Dictionary, mine: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 48)
	row.add_theme_stylebox_override("panel", _mine_style if mine else _row_style_plain)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	var rank_label := _cell(str(rank), BLACK, 26, ACCENT if mine else DIM, RANK, HORIZONTAL_ALIGNMENT_LEFT)
	line.add_child(rank_label)
	var name_box := HBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 8)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_child(_cell(str(info.name), SEMIBOLD, 16, TEXT, 0, HORIZONTAL_ALIGNMENT_LEFT))
	var bot: bool = info.get("bot", false)
	if mine or bot:
		name_box.add_child(_cell("YOU" if mine else "BOT", BOLD, 11, ACCENT if mine else DIM, 0, HORIZONTAL_ALIGNMENT_LEFT))
	line.add_child(name_box)

	var kills := int(info.kills)
	var deaths := int(info.deaths)
	var level := "—" if bot else str(int(info.get("xp_level", 1)))
	line.add_child(_cell(level, SEMIBOLD, 16, TEXT, COLUMN, HORIZONTAL_ALIGNMENT_RIGHT))
	line.add_child(_cell(str(kills), BOLD, 16, TEXT, COLUMN, HORIZONTAL_ALIGNMENT_RIGHT))
	line.add_child(_cell(str(deaths), SEMIBOLD, 16, TEXT, COLUMN, HORIZONTAL_ALIGNMENT_RIGHT))
	line.add_child(_cell("%.2f" % (float(kills) / maxf(1.0, deaths)), SEMIBOLD, 16, TEXT, COLUMN, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _cell(text: String, font: Font, size: int, color: Color, min_width: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(min_width, 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _row_style(mine: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.541, 0.122, 0.2) if mine else Color(0.078, 0.086, 0.11, 0.85)
	style.border_width_left = 4
	style.border_color = ACCENT if mine else Color(0, 0, 0, 0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style
