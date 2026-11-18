class_name MenuScreen
extends Control
## Base class for menu screens. [MainMenu] fills in `menu` and calls
## enter()/leave().

var menu: MainMenu


## Called when the screen opens. `arg` comes from MainMenu.show_screen().
func enter(_arg: Variant) -> void:
	pass


## Called when leaving the screen.
func leave() -> void:
	pass


## Connects the button to the Callable and plays the click sound.
func bind_button(button: BaseButton, action: Callable) -> void:
	UiMotion.attach(button)
	button.pressed.connect(func():
		Sfx.play("switch", -8.0)
		action.call())


## Esc (ui_cancel) presses the screen's Back button (a unique node named
## "Back"), so every screen leaves the same way. Only while this screen is the
## one shown by the main menu (the Settings screen in the pause menu has no
## `menu` and is closed by the pause menu itself).
func _unhandled_input(event: InputEvent) -> void:
	if menu == null or not visible or not event.is_action_pressed("ui_cancel"):
		return
	if menu.current_screen() != name:
		return
	var back := get_node_or_null("%Back") as BaseButton
	if back == null or not back.is_visible_in_tree() or back.disabled:
		return
	get_viewport().set_input_as_handled()
	back.pressed.emit()


## Small "ESC" key cap at the right edge of the Back button (keyboard only).
func add_back_key_hint() -> void:
	var back := get_node_or_null("%Back") as Button
	if back == null or Touch.active or back.has_node("KeyHint"):
		return
	var key := Label.new()
	key.name = "KeyHint"
	key.text = "ESC"
	key.theme_type_variation = &"Caption"
	key.add_theme_font_size_override("font_size", 10)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.08)
	box.border_color = Color(1, 1, 1, 0.22)
	box.set_border_width_all(1)
	box.set_content_margin_all(3)
	box.content_margin_left = 5
	box.content_margin_right = 5
	key.add_theme_stylebox_override("normal", box)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(key)
	key.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	back.custom_minimum_size.x = maxf(back.custom_minimum_size.x, 158.0)
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
