extends MenuScreen
## Mode and map selection: one numbered card per game mode in ModeDB and one
## picture per map in MapDB (plus "Random map"). The choice is saved in
## Config (selected_mode / selected_map), shown on the lobby's mode card and
## used by Play and Create server.

const ACCENT := Color("#ff8a1f")
const ON_ACCENT := Color("#111111")
const TEXT := Color("#f2f1ec")
const TEXT_DIM := Color("#a8afbb")
const DISPLAY_FONT := preload("res://assets/fonts/BarlowCondensed-BlackItalic.ttf")
const TAG_FONT := preload("res://assets/fonts/Barlow-Bold.ttf")

var _cards: Array[Button] = []
var _map_buttons: Array[Button] = []
var _selected := 0
## -1 = random map.
var _map := -1


func _ready() -> void:
	for i in ModeDB.count():
		var card := _make_card(i)
		%Cards.add_child(card)
		_cards.append(card)
	for i in MapDB.count():
		var button := _make_map_button(i)
		%MapGrid.add_child(button)
		_map_buttons.append(button)
	bind_button(%RandomMap, func(): _select_map(-1))
	bind_button(%Back, func(): menu.show_screen("Home"))
	bind_button(%Confirm, _confirm)


func enter(_arg: Variant) -> void:
	_select(Config.selected_mode)
	_select_map(Config.selected_map)


# ---------------------------------------------------------------- modes

## A chamfered card: number tag (and "SELECTED" chip), name, description.
func _make_card(index: int) -> Button:
	var mode := ModeDB.get_mode(index)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.theme_type_variation = &"MenuBtn"

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 22.0
	column.offset_right = -18.0
	column.offset_top = 14.0
	column.offset_bottom = -14.0
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var number := _label("%02d" % (index + 1), TAG_FONT, 12, TEXT_DIM)
	number.name = "Number"
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(number)
	var chip := _label("SELECTED", TAG_FONT, 10, ACCENT)
	chip.name = "Chip"
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = ON_ACCENT
	chip_style.content_margin_left = 8
	chip_style.content_margin_right = 8
	chip_style.content_margin_top = 2
	chip_style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal", chip_style)
	top.add_child(chip)

	var title := _label(mode.display_name.to_upper(), DISPLAY_FONT, 32, TEXT)
	title.name = "Title"
	column.add_child(title)
	var description := _label(mode.description, null, 13, TEXT_DIM)
	description.name = "Description"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)

	bind_button(card, func(): _select(index))
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


## The selected card turns solid orange with dark text.
func _select(index: int) -> void:
	_selected = clampi(index, 0, ModeDB.count() - 1)
	for i in _cards.size():
		var card := _cards[i]
		var on := i == _selected
		var number: Label = card.find_child("Number", true, false)
		var title: Label = card.find_child("Title", true, false)
		var description: Label = card.find_child("Description", true, false)
		card.find_child("Chip", true, false).visible = on
		if on:
			var style := (card.get_theme_stylebox("normal", &"MenuBtn") as StyleBoxFlat).duplicate() as StyleBoxFlat
			style.bg_color = ACCENT
			style.border_width_left = 0
			card.add_theme_stylebox_override("normal", style)
			card.add_theme_stylebox_override("hover", style)
			card.add_theme_stylebox_override("pressed", style)
		else:
			for state in ["normal", "hover", "pressed"]:
				card.remove_theme_stylebox_override(state)
		number.add_theme_color_override("font_color", ON_ACCENT if on else TEXT_DIM)
		title.add_theme_color_override("font_color", ON_ACCENT if on else TEXT)
		description.add_theme_color_override("font_color", ON_ACCENT if on else TEXT_DIM)


# ---------------------------------------------------------------- maps

## A map picture with its name over it (and a "SELECTED" chip).
func _make_map_button(index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 104)
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
	var chip := _label("SELECTED", TAG_FONT, 10, ON_ACCENT)
	chip.name = "Chip"
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = ACCENT
	chip_style.content_margin_left = 8
	chip_style.content_margin_right = 8
	chip_style.content_margin_top = 2
	chip_style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal", chip_style)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.add_child(chip)

	button.mouse_entered.connect(func(): picture.modulate = Color(1, 1, 1))
	button.mouse_exited.connect(func(): _select_map(_map))
	bind_button(button, func(): _select_map(index))
	return button


func _select_map(index: int) -> void:
	_map = clampi(index, -1, MapDB.count() - 1)
	for i in _map_buttons.size():
		var on := i == _map
		var button := _map_buttons[i]
		button.find_child("Frame", true, false).visible = on
		button.find_child("Chip", true, false).visible = on
		(button.find_child("Picture", true, false) as TextureRect).modulate = Color(1, 1, 1) if on else Color(0.7, 0.7, 0.72)
	%RandomMap.text = "RANDOM MAP  ✓" if _map < 0 else "RANDOM MAP"
	%MapDescription.text = "A different map every match." if _map < 0 else \
		"%s — %s" % [MapDB.display_name(_map), MapDB.info(_map).description]


func _confirm() -> void:
	Config.selected_mode = _selected
	Config.selected_map = _map
	Config.save_cfg()
	menu.show_screen("Home")
