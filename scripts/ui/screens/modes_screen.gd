extends MenuScreen
## Mode and map selection: one card per game mode in ModeDB and one picture per
## map in MapDB (plus "Random map"). The choice is saved in Config
## (selected_mode / selected_map), shown on the lobby's mode card and used by
## Play and Create server.

const ACCENT := Color("#ff8a1f")
const ACCENT_HI := Color("#ffb066")
const ON_ACCENT := Color("#111111")
const TEXT := Color("#f2f1ec")
const TEXT_DIM := Color("#a8afbb")
const DISPLAY_FONT := preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
const TAG_FONT := preload("res://assets/fonts/Barlow-Bold.ttf")

var _cards: Array[Button] = []
var _card_parts: Array[Dictionary] = []
var _map_buttons: Array[Button] = []
var _selected := 0
## -1 = random map.
var _map := -1


func _ready() -> void:
	%ModeCount.text = "%d MODES" % ModeDB.count()
	%MapCount.text = "%d MAPS" % MapDB.count()
	# Two cards per row; an odd last card takes the whole row, so the grid
	# never ends with an empty cell.
	var row: HBoxContainer = null
	for i in ModeDB.count():
		if i % 2 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			row.size_flags_vertical = Control.SIZE_EXPAND_FILL
			%Cards.add_child(row)
		var card := _make_card(i)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		_cards.append(card)
	for i in MapDB.count():
		var button := _make_map_button(i)
		%MapGrid.add_child(button)
		_map_buttons.append(button)
	bind_button(%RandomMap, func(): _select_map(-1, true))
	bind_button(%Back, func(): menu.show_screen("Home"))
	bind_button(%Confirm, _confirm)


func enter(_arg: Variant) -> void:
	_select(Config.selected_mode)
	_select_map(Config.selected_map)


# ---------------------------------------------------------------- modes

## A chamfered card: icon, number, rule tag, name, description and a strip of
## the mode's weapons, with its main weapon faded into the right side.
func _make_card(index: int) -> Button:
	var mode := ModeDB.get_mode(index)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 154)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	card.theme_type_variation = &"MenuBtn"

	var watermark := TextureRect.new()
	watermark.name = "Watermark"
	watermark.texture = ModeArt.watermark(mode)
	watermark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	watermark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	watermark.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	watermark.offset_left = -190.0
	watermark.offset_right = -2.0
	watermark.offset_top = -52.0
	watermark.offset_bottom = 52.0
	watermark.pivot_offset = Vector2(94, 52)
	watermark.rotation = -0.12
	watermark.modulate = Color(1, 1, 1, 0.07)
	card.add_child(watermark)

	var icon_back := Panel.new()
	icon_back.name = "IconBack"
	icon_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_back.anchor_top = 0.5
	icon_back.anchor_bottom = 0.5
	icon_back.offset_left = 14.0
	icon_back.offset_right = 64.0
	icon_back.offset_top = -25.0
	icon_back.offset_bottom = 25.0
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(1, 1, 1, 0.08)
	icon_style.border_color = Color(1, 1, 1, 0.16)
	icon_style.set_border_width_all(1)
	icon_style.corner_radius_top_left = 11
	icon_style.corner_radius_bottom_right = 11
	icon_style.corner_detail = 1
	icon_back.add_theme_stylebox_override("panel", icon_style)
	icon_back.modulate = ACCENT
	card.add_child(icon_back)

	var icon := TextureRect.new()
	icon.name = "ModeIcon"
	icon.texture = ModeArt.icon(mode)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = 24.0
	icon.offset_right = 54.0
	icon.offset_top = -15.0
	icon.offset_bottom = 15.0
	icon.pivot_offset = Vector2(15, 15)
	icon.modulate = ACCENT
	card.add_child(icon)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 78.0
	column.offset_right = -18.0
	column.offset_top = 12.0
	column.offset_bottom = -12.0
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	var number := _label("%02d" % (index + 1), TAG_FONT, 12, TEXT_DIM)
	number.name = "Number"
	top.add_child(number)
	var rule := _label(ModeArt.rule(mode), TAG_FONT, 10, TEXT_DIM)
	rule.name = "Rule"
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rule)
	# No "SELECTED" chip: the solid orange card already says it.

	var title := _label(mode.display_name.to_upper(), DISPLAY_FONT, 32, TEXT)
	title.name = "Title"
	column.add_child(title)
	var description := _label(mode.description, null, 13, TEXT_DIM)
	description.name = "Description"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)

	var loadout := HBoxContainer.new()
	loadout.name = "Loadout"
	loadout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loadout.add_theme_constant_override("separation", 5)
	column.add_child(loadout)
	var icons := ModeArt.loadout_icons(mode, 6)
	for texture in icons:
		var weapon_icon := TextureRect.new()
		weapon_icon.texture = texture
		weapon_icon.custom_minimum_size = Vector2(29, 16)
		weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		weapon_icon.modulate = Color(1, 1, 1, 0.5)
		loadout.add_child(weapon_icon)
	var extra := ModeArt.weapons(mode).size() - icons.size()
	if extra > 0:
		var more := _label("+%d" % extra, TAG_FONT, 9, TEXT_DIM)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		loadout.add_child(more)

	_card_parts.append({
		"number": number, "rule": rule, "title": title,
		"description": description, "icon": icon, "icon_back": icon_back,
		"watermark": watermark, "loadout": loadout,
	})
	card.mouse_entered.connect(func(): _hover_card(index, true))
	card.mouse_exited.connect(func(): _hover_card(index, false))
	bind_button(card, func(): _select(index, true))
	return card


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _hover_card(index: int, on: bool) -> void:
	if index == _selected:
		return
	var parts := _card_parts[index]
	(parts.icon as TextureRect).modulate = ACCENT_HI if on else ACCENT
	(parts.icon_back as Panel).modulate = ACCENT_HI if on else ACCENT
	(parts.watermark as TextureRect).modulate = Color(1, 1, 1, 0.12 if on else 0.07)
	_tint_loadout(parts.loadout as HBoxContainer, Color(1, 0.69, 0.4, 0.75) if on else Color(1, 1, 1, 0.5))


func _tint_loadout(strip: HBoxContainer, color: Color) -> void:
	for child in strip.get_children():
		if child is TextureRect:
			(child as TextureRect).modulate = color
		elif child is Label:
			(child as Label).add_theme_color_override("font_color", color)


## The selected card turns solid orange with dark text and a gentle bounce.
func _select(index: int, animate := false) -> void:
	_selected = clampi(index, 0, ModeDB.count() - 1)
	var selected_mode := ModeDB.get_mode(_selected)
	%SetupMode.text = selected_mode.display_name.to_upper()
	%SetupModeIcon.texture = ModeArt.icon(selected_mode)
	for i in _cards.size():
		var card := _cards[i]
		var parts := _card_parts[i]
		var on := i == _selected
		if on:
			var style := (card.get_theme_stylebox("normal", &"MenuBtn") as StyleBoxFlat).duplicate() as StyleBoxFlat
			style.bg_color = ACCENT
			style.border_width_left = 0
			style.shadow_color = Color(1.0, 0.541, 0.122, 0.2)
			style.shadow_size = 8
			card.add_theme_stylebox_override("normal", style)
			card.add_theme_stylebox_override("hover", style)
			card.add_theme_stylebox_override("pressed", style)
		else:
			for state in ["normal", "hover", "pressed"]:
				card.remove_theme_stylebox_override(state)
		var text_color := ON_ACCENT if on else TEXT
		var dim_color := ON_ACCENT if on else TEXT_DIM
		(parts.number as Label).add_theme_color_override("font_color", dim_color)
		(parts.rule as Label).add_theme_color_override("font_color", dim_color)
		(parts.title as Label).add_theme_color_override("font_color", text_color)
		(parts.description as Label).add_theme_color_override("font_color", dim_color)
		(parts.icon as TextureRect).modulate = ON_ACCENT if on else ACCENT
		(parts.icon_back as Panel).modulate = ON_ACCENT if on else ACCENT
		(parts.watermark as TextureRect).modulate = Color(0, 0, 0, 0.16) if on else Color(1, 1, 1, 0.07)
		_tint_loadout(parts.loadout as HBoxContainer, Color(0, 0, 0, 0.55) if on else Color(1, 1, 1, 0.5))
		if on and animate:
			UiMotion.pop(card, 1.012, 0.24)
			UiMotion.pop(parts.icon as Control, 1.18, 0.3)
			UiMotion.pop(parts.icon_back as Control, 1.10, 0.3)
	if animate:
		UiMotion.pop(%SetupCard, 1.012, 0.22)


# ---------------------------------------------------------------- maps

## A map picture with its name over it (and a check mark when selected).
func _make_map_button(index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 94)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, empty)

	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = load("res://assets/ui/maps/%s.png" % MapDB.info(index).id)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(picture)

	var name_label := _label(MapDB.display_name(index).to_upper(), DISPLAY_FONT, 19, TEXT)
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	# Bottom-left corner of the picture.
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_left = 10.0
	name_label.offset_bottom = -6.0
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	button.add_child(name_label)

	# Orange frame + chip when selected.
	var frame := Panel.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.border_color = ACCENT
	frame_style.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	button.add_child(frame)
	var chip := _label("✓", TAG_FONT, 13, ON_ACCENT)
	chip.name = "Chip"
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = ACCENT
	chip_style.corner_radius_bottom_left = 6
	chip_style.content_margin_left = 7
	chip_style.content_margin_right = 7
	chip_style.content_margin_top = 1
	chip_style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal", chip_style)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.add_child(chip)

	button.mouse_entered.connect(func(): _hover_map(index, true))
	button.mouse_exited.connect(func(): _hover_map(index, false))
	bind_button(button, func(): _select_map(index, true))
	return button


func _hover_map(index: int, on: bool) -> void:
	if index == _map:
		return
	var picture := _map_buttons[index].find_child("Picture", true, false) as TextureRect
	picture.pivot_offset = picture.size / 2.0
	var t := picture.create_tween().set_parallel()
	t.tween_property(picture, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(picture, "modulate", Color(0.9, 0.9, 0.92) if on else Color(0.7, 0.7, 0.72), 0.16)


func _select_map(index: int, animate := false) -> void:
	_map = clampi(index, -1, MapDB.count() - 1)
	for i in _map_buttons.size():
		var on := i == _map
		var button := _map_buttons[i]
		var picture := button.find_child("Picture", true, false) as TextureRect
		var frame := button.find_child("Frame", true, false) as Panel
		var chip := button.find_child("Chip", true, false) as Label
		frame.visible = on
		chip.visible = on
		picture.modulate = Color(1, 1, 1) if on else Color(0.7, 0.7, 0.72)
		picture.pivot_offset = picture.size / 2.0
		if on and animate:
			frame.modulate.a = 0.0
			var t := frame.create_tween()
			t.tween_property(frame, "modulate:a", 1.0, 0.18)
			UiMotion.pop(picture, 1.05, 0.3)
			UiMotion.pop_in(chip, 0.18)
		else:
			frame.modulate.a = 1.0
			picture.scale = Vector2.ONE
	%RandomMap.text = "RANDOM MAP  ✓" if _map < 0 else "RANDOM MAP"
	%RandomMap.theme_type_variation = &"PrimaryButton" if _map < 0 else &"GhostButton"
	%SetupMap.text = "RANDOM" if _map < 0 else MapDB.display_name(_map).to_upper()
	var description := "A different map every match." if _map < 0 else \
		"%s — %s" % [MapDB.display_name(_map), MapDB.info(_map).description]
	_set_description(description, animate)
	if animate:
		UiMotion.pop(%SetupCard, 1.012, 0.22)


func _set_description(text: String, animate: bool) -> void:
	if %MapDescription.text == text:
		return
	if not animate:
		%MapDescription.text = text
		%MapDescription.modulate.a = 1.0
		return
	var t := %MapDescription.create_tween()
	t.tween_property(%MapDescription, "modulate:a", 0.0, 0.08)
	t.tween_callback(func(): %MapDescription.text = text)
	t.tween_property(%MapDescription, "modulate:a", 1.0, 0.16)


func _confirm() -> void:
	Config.selected_mode = _selected
	Config.selected_map = _map
	Config.save_cfg()
	menu.show_screen("Home")
