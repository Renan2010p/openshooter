extends MenuScreen
## Locker: free character items by category (see Cosmetics), plus name and
## colors. Items are shown as cards with a 3D thumbnail in a scrolling grid
## (see ItemThumbnails). Every change shows on the big 3D character right
## away; "Save look" keeps it, "Back" throws unsaved changes away.

## The extra tab after the item categories.
const COLORS_TAB := "colors"

## Where the camera looks for each tab (see MainMenu.locker_focus).
const FOCUS := {
	"hat": "head", "hair": "head", "face": "head",
	"top": "body", "back": "body", "legs": "legs", "feet": "feet", COLORS_TAB: "body",
}

## Card size in the item grid (3 per row).
const CARD_SIZE := Vector2(0, 172)
const THUMB_SIZE := Vector2(128, 128)

var _tab := "hat"
var _tab_buttons := {}
var _thumbnails := ItemThumbnails.new()


func _ready() -> void:
	add_child(_thumbnails)
	for slot in Cosmetics.SLOTS:
		_add_tab(slot, Cosmetics.SLOT_NAMES[slot])
	_add_tab(COLORS_TAB, "COLORS")
	for key in ["shirt", "pants", "skin", "hair"]:
		var picker: ColorPickerButton = get_node("%" + key.capitalize())
		picker.color_changed.connect(func(c: Color):
			Config.set(key, c)
			_thumbnails.clear()  # thumbnails show the player's colors
			menu.rebuild_avatar())
	bind_button(%Save, _save)
	bind_button(%Back, func():
		Config.load_cfg()  # throw away unsaved changes
		menu.rebuild_avatar()
		menu.show_screen("Home"))


## `arg` may name the tab to open (a slot or "colors"); the default is "hat".
func enter(arg: Variant) -> void:
	%PlayerName.text = Config.player_name
	%Shirt.color = Config.shirt
	%Pants.color = Config.pants
	%Skin.color = Config.skin
	%Hair.color = Config.hair
	var tab := str(arg) if arg != null else "hat"
	_show_tab(tab if tab in Cosmetics.SLOTS or tab == COLORS_TAB else "hat")


func leave() -> void:
	menu.locker_focus = "body"
	menu.locker_show_back = false


func _add_tab(id: String, title: String) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(136, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"MenuBtn"
	button.add_theme_font_size_override("font_size", 15)
	%Tabs.add_child(button)
	_tab_buttons[id] = button
	bind_button(button, func(): _show_tab(id))


func _show_tab(id: String) -> void:
	_tab = id
	for tab_id in _tab_buttons:
		_highlight(_tab_buttons[tab_id], tab_id == id)
	var colors := id == COLORS_TAB
	%Colors.visible = colors
	%ItemsScroll.visible = not colors
	menu.locker_focus = FOCUS.get(id, "body")
	menu.locker_show_back = id == "back"
	menu.turn_to_rest()
	if not colors:
		_fill_items(id)


## One card per item of `slot`: its 3D thumbnail and its name. The item worn
## now is highlighted.
func _fill_items(slot: String) -> void:
	for child in %Items.get_children():
		child.queue_free()
	%ItemsScroll.scroll_vertical = 0
	for item in Cosmetics.ITEMS[slot]:
		var id: String = item[0]
		var card := _make_card(item[1])
		card.set_meta("item_id", id)
		%Items.add_child(card)
		_highlight(card, Config.look.get(slot) == id)
		bind_button(card, func(): _wear(slot, id))
		# The picture arrives a frame later; the card may be gone by then.
		var picture: TextureRect = card.get_node("Column/Picture")
		_thumbnails.request(slot, id, func(texture: Texture2D):
			if is_instance_valid(picture):
				picture.texture = texture)


## A card: thumbnail on top, name below.
func _make_card(title: String) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.theme_type_variation = &"MenuBtn"
	card.tooltip_text = title

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 8.0
	column.offset_bottom = -8.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.custom_minimum_size = THUMB_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(picture)

	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"HudLabel"
	label.add_theme_font_size_override("font_size", 15)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	return card


func _wear(slot: String, id: String) -> void:
	Config.look[slot] = id
	menu.rebuild_avatar()
	menu.avatar_react(slot)
	for card in %Items.get_children():
		_highlight(card, card.get_meta("item_id", "") == id)


## Accent border on the selected button.
func _highlight(button: Button, on: bool) -> void:
	if on:
		var style := (button.get_theme_stylebox("normal", &"MenuBtn") as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.border_color = Color("#f5a524")
		style.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")


func _save() -> void:
	var n: String = %PlayerName.text.strip_edges()
	if n != "":
		Config.player_name = n
	Config.save_cfg()
	menu.set_status("Look saved.", true)
	menu.show_screen("Home")
