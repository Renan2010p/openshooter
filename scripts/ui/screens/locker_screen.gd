extends MenuScreen
## Locker: free character items by category (see Cosmetics), plus name and
## colors. Items are shown as cards with a 3D thumbnail in a scrolling grid
## (see ItemThumbnails). Every change shows on the big 3D character right
## away; "Save look" keeps it, "Discard" throws unsaved changes away.

## The extra tab after the item categories.
const COLORS_TAB := "colors"

## Where the camera looks for each tab (see MainMenu.locker_focus).
const FOCUS := {
	"hat": "head", "hair": "head", "face": "head",
	"top": "body", "back": "body", "legs": "legs", "feet": "feet", COLORS_TAB: "body",
}

## Card size in the item grid (3 per row).
const CARD_SIZE := Vector2(0, 142)
const THUMB_SIZE := Vector2(104, 104)

const ACCENT := Color("#ff8a1f")
const ON_ACCENT := Color("#111111")
const EVENT_RED := Color("#c7161f")
const CARD_BG := Color("#1c1f27")
const CARD_BG_ON := Color("#2a1d10")
const CARD_FONT := preload("res://assets/fonts/BarlowCondensed-Bold.ttf")
const RAIL_FONT := preload("res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf")
const TAG_FONT := preload("res://assets/fonts/Barlow-Bold.ttf")
## Items that belong to the current event get an EVENT chip.
const EVENT_ITEMS := ["santa"]

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
	bind_button(%Discard, func():
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


## One category on the left rail.
func _add_tab(id: String, title: String) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(170, 44)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"MenuBtn"
	button.add_theme_font_override("font", RAIL_FONT)
	button.add_theme_font_size_override("font_size", 21)
	%Tabs.add_child(button)
	_tab_buttons[id] = button
	bind_button(button, func(): _show_tab(id))


func _show_tab(id: String) -> void:
	_tab = id
	# The open tab is solid orange and slanted, like every primary action.
	for tab_id in _tab_buttons:
		(_tab_buttons[tab_id] as Button).theme_type_variation = &"PrimaryButton" if tab_id == id else &"MenuBtn"
	var colors := id == COLORS_TAB
	%SlotTitle.text = "COLORS" if colors else Cosmetics.SLOT_NAMES[id]
	%ItemCount.text = "" if colors else "%d ITEMS" % Cosmetics.ITEMS[id].size()
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
		var card := _make_card(item[1], id in EVENT_ITEMS)
		card.set_meta("item_id", id)
		%Items.add_child(card)
		_highlight(card, Config.look.get(slot) == id)
		bind_button(card, func(): _wear(slot, id))
		# The picture arrives a frame later; the card may be gone by then.
		var picture: TextureRect = card.get_node("Column/Picture")
		_thumbnails.request(slot, id, func(texture: Texture2D):
			if is_instance_valid(picture):
				picture.texture = texture)


## A card: thumbnail on top, name below, a WORN chip (shown when worn) and an
## EVENT chip for event items.
func _make_card(title: String, event_item: bool) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = title

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 6.0
	column.offset_bottom = -6.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
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
	label.add_theme_font_override("font", CARD_FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)

	var worn := _chip("WORN", ACCENT, ON_ACCENT)
	worn.name = "Worn"
	worn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	card.add_child(worn)
	if event_item:
		var event := _chip("EVENT", EVENT_RED, Color.WHITE)
		event.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
		event.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		card.add_child(event)
	return card


func _chip(text: String, background: Color, color: Color) -> Label:
	var chip := Label.new()
	chip.text = text
	chip.add_theme_font_override("font", TAG_FONT)
	chip.add_theme_font_size_override("font_size", 10)
	chip.add_theme_color_override("font_color", color)
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("normal", style)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


func _wear(slot: String, id: String) -> void:
	Config.look[slot] = id
	menu.rebuild_avatar()
	menu.avatar_react(slot)
	for card in %Items.get_children():
		_highlight(card, card.get_meta("item_id", "") == id)


## The worn item: orange frame, warmer background and the WORN chip.
func _highlight(card: Button, on: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG_ON if on else CARD_BG
	if on:
		style.border_color = ACCENT
		style.set_border_width_all(2)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.08)
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var worn := card.get_node_or_null("Worn")
	if worn:
		worn.visible = on


func _save() -> void:
	var n: String = %PlayerName.text.strip_edges()
	if n != "":
		Config.player_name = n
	Config.save_cfg()
	menu.set_status("Look saved.", true)
	menu.show_screen("Home")
