class_name VotePanel
extends Control
## Match-over screen (scenes/ui/vote_panel.tscn), shown through the end of a
## match and the vote that follows:
##   orange banner     VICTORY (or your place) with mode and map
##   experience card   XP earned, how, and your level progress
##   mini scoreboard   the top players (and you)
##   map vote          one picture per map; the vote opens after the end screen
##
## The game mode belongs to the server and does not change between matches.

## `mode_idx` is always -1 (kept so the network call stays the same).
signal voted(map_idx: int, mode_idx: int)

const BLACK := preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
const XBOLD := preload("res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf")
const BOLD := preload("res://assets/fonts/Barlow-Bold.ttf")
const SEMIBOLD := preload("res://assets/fonts/Barlow-SemiBold.ttf")
const ACCENT := Color("#ff8a1f")
const DIM := Color("#a8afbb")
## Rows in the mini scoreboard.
const BOARD_ROWS := 3

var _map_buttons: Array[Button] = []
var _map := -1
var _current_map := -1
var _reward_hash := 0
var _world: World


func _ready() -> void:
	for i in MapDB.count():
		var b := _map_card(i)
		b.pressed.connect(func(): _pick_map(i))
		%MapGrid.add_child(b)
		_map_buttons.append(b)


## Starts the screen for the match that just ended.
func reset(world: World) -> void:
	_world = world
	_map = -1
	_current_map = world.map_index
	_reward_hash = 0
	var mode := world.mode()
	%Eyebrow.text = "MATCH OVER  ·  %s  ·  %s" % [mode.display_name.to_upper(), MapDB.display_name(world.map_index).to_upper()]
	%VoteHint.text = "MODE STAYS %s  ·  NO VOTES: A DIFFERENT MAP" % mode.display_name.to_upper()
	_update_result()


func _pick_map(i: int) -> void:
	if _world == null or _world.match_manager.phase != "vote":
		return
	_map = i
	Sfx.play("switch", -8.0)
	voted.emit(_map, -1)


## Called about 10 times a second: timer, votes, XP (it arrives over the
## network a moment after the match ends) and the mini scoreboard.
func show_state(seconds: float, map_votes: Dictionary, _mode_votes: Dictionary) -> void:
	var voting := _world != null and _world.match_manager.phase == "vote"
	var t := ceili(seconds)
	%VoteTimer.text = ("%d:%02d" % [t / 60, t % 60]) if voting else "OPENS IN %d" % t
	for i in _map_buttons.size():
		var card := _map_buttons[i]
		card.disabled = not voting
		(card.get_node("Votes") as Label).text = str(int(map_votes.get(i, 0)))
		(card.get_node("Mine") as Control).visible = i == _map
		(card.get_node("Frame") as Control).visible = i == _map
		var current := i == _current_map
		(card.get_node("Current") as Control).visible = current
		(card.get_node("Picture") as CanvasItem).modulate = Color(0.45, 0.45, 0.45) if current else (
			Color(0.75, 0.75, 0.75) if i == _map else Color(0.6, 0.6, 0.6))
	_update_result()
	_update_board()


func _update_result() -> void:
	var reward := Config.last_reward
	var won: bool = reward.get("won", false)
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var place := Scoreboard.ranking().find(me) + 1
	%Result.text = "VICTORY" if won else ("#%d PLACE" % place if place > 0 else "MATCH OVER")
	var reward_id := reward.hash()
	if reward_id == _reward_hash:
		return
	_reward_hash = reward_id
	%XpCard.visible = not reward.is_empty()
	if reward.is_empty():
		return
	%XpTotal.text = "+%d XP" % int(reward.total)
	for c in %XpLines.get_children():
		c.queue_free()
	for line in reward.lines:
		var row := HBoxContainer.new()
		var label := _label(str(line[0]), SEMIBOLD, 15, Color("#f2f1ec"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_label("+%d" % int(line[1]), BOLD, 15, ACCENT if str(line[0]) == "Victory" else Color("#f2f1ec")))
		%XpLines.add_child(row)
	var info := Progression.level_info(Config.xp)
	%XpLevel.text = str(info.level)
	var up := int(reward.level_after) > int(reward.level_before)
	%XpLevelText.text = "LEVEL UP!" if up else "LEVEL %d" % info.level
	%XpProgress.text = "%d / %d XP" % [info.into, info.needed]
	%XpBar.value = 100.0 * info.into / maxf(1.0, info.needed)


## Top players; your row replaces the last one when you are not among them.
func _update_board() -> void:
	for c in %MiniRows.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	var order := Scoreboard.ranking()
	var shown := order.slice(0, BOARD_ROWS)
	var my_place := order.find(me)
	if my_place >= BOARD_ROWS and not shown.is_empty():
		shown[shown.size() - 1] = me
	for id in shown:
		var info: Dictionary = Net.players[id]
		var mine: bool = id == me
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 36)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.541, 0.122, 0.18) if mine else Color(0.078, 0.086, 0.11, 0.85)
		style.border_width_left = 4
		style.border_color = ACCENT if mine else Color(0, 0, 0, 0)
		style.content_margin_left = 14
		style.content_margin_right = 14
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		row.add_child(line)
		var rank := _label(str(order.find(id) + 1), XBOLD, 20, ACCENT if mine else DIM)
		rank.custom_minimum_size.x = 36
		line.add_child(rank)
		var name_label := _label(str(info.name), SEMIBOLD, 15, Color("#f2f1ec"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var kills := _label(str(int(info.kills)), BOLD, 15, Color("#f2f1ec"))
		kills.custom_minimum_size.x = 60
		kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(kills)
		var deaths := _label(str(int(info.deaths)), SEMIBOLD, 15, Color("#f2f1ec"))
		deaths.custom_minimum_size.x = 70
		deaths.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(deaths)
		%MiniRows.add_child(row)


## A map card: the map's picture, its name, the vote count, a YOUR VOTE chip
## and frame, and a CURRENT chip for the map just played.
func _map_card(i: int) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color("#14161c")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		card.add_theme_stylebox_override(state, flat)
	UiMotion.attach(card)

	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = load("res://assets/ui/maps/%s.png" % MapDB.info(i).id)
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(picture)

	var title := _label(MapDB.display_name(i).to_upper(), XBOLD, 19, Color("#f2f1ec"))
	title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	title.grow_vertical = Control.GROW_DIRECTION_BEGIN
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("outline_size", 4)
	card.add_child(title)

	var votes := _label("0", XBOLD, 19, Color("#f2f1ec"))
	votes.name = "Votes"
	votes.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	votes.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	votes.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.add_child(votes)

	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = ACCENT
	border.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", border)
	frame.visible = false
	card.add_child(frame)

	var mine := _chip("YOUR VOTE", ACCENT, Color("#111111"))
	mine.name = "Mine"
	mine.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	mine.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mine.visible = false
	card.add_child(mine)

	var current := _chip("CURRENT", Color(0, 0, 0, 0.75), DIM)
	current.name = "Current"
	current.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	current.visible = false
	card.add_child(current)
	return card


func _chip(text: String, background: Color, color: Color) -> Label:
	var chip := _label(text, BOLD, 10, color)
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override("normal", style)
	return chip


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
