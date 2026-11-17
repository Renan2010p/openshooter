extends MenuScreen
## Mode selection: one card per game mode in ModeDB, plus the map. The choice
## is saved in Config (selected_mode / selected_map), shown on the lobby's
## mode card and used when creating a server.

## Item id of "Random" in the map list (real maps use their MapDB index).
const RANDOM_ID := 1000

var _cards: Array[Button] = []
var _selected := 0


func _ready() -> void:
	%Map.add_item("Random", RANDOM_ID)
	for i in MapDB.count():
		%Map.add_item(MapDB.display_name(i), i)
	%Map.item_selected.connect(func(_i): _update_map_description())
	for i in ModeDB.count():
		var card := _make_card(i)
		%Cards.add_child(card)
		_cards.append(card)
	bind_button(%Back, func(): menu.show_screen("Home"))
	bind_button(%Private, func(): menu.show_screen("Private"))
	bind_button(%Confirm, _confirm)


func enter(_arg: Variant) -> void:
	_select(Config.selected_mode)
	var map_id := Config.selected_map if Config.selected_map >= 0 else RANDOM_ID
	%Map.select(%Map.get_item_index(map_id))
	_update_map_description()


## A big button with the mode's name and description.
func _make_card(index: int) -> Button:
	var mode := ModeDB.get_mode(index)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 112)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.theme_type_variation = &"MenuBtn"

	var text := VBoxContainer.new()
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 22.0
	text.offset_right = -22.0
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(text)

	var title := Label.new()
	title.text = mode.display_name.to_upper()
	title.theme_type_variation = &"TitleSmall"
	text.add_child(title)

	var description := Label.new()
	description.text = mode.description
	description.theme_type_variation = &"HintLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(description)

	bind_button(card, func(): _select(index))
	return card


## Highlights the selected card with an accent border.
func _select(index: int) -> void:
	_selected = clampi(index, 0, ModeDB.count() - 1)
	for i in _cards.size():
		var card := _cards[i]
		if i == _selected:
			var style := (card.get_theme_stylebox("normal", &"MenuBtn") as StyleBoxFlat).duplicate() as StyleBoxFlat
			style.border_color = Color("#f5a524")
			style.set_border_width_all(2)
			card.add_theme_stylebox_override("normal", style)
			card.add_theme_stylebox_override("hover", style)
		else:
			card.remove_theme_stylebox_override("normal")
			card.remove_theme_stylebox_override("hover")


func _update_map_description() -> void:
	var id: int = %Map.get_selected_id()
	%MapDescription.text = "A different map every match." if id == RANDOM_ID else MapDB.info(id).description


func _confirm() -> void:
	Config.selected_mode = _selected
	var id: int = %Map.get_selected_id()
	Config.selected_map = -1 if id == RANDOM_ID else id
	Config.save_cfg()
	menu.show_screen("Home")
