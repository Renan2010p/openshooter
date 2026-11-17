extends MenuScreen
## Settings: categories on a rail at the left (like the Locker), one page of
## options each on the right. Nothing changes until Save; Discard and Back
## leave without saving.

const FPS_LIMITS := [0, 60, 120, 144]
const RAIL_FONT := preload("res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf")
## Page node, rail title, line under the page title.
const PAGES := [
	["Controls", "CONTROLS", "Aim and camera feel."],
	["Display", "DISPLAY", "Window, frame rate and brightness."],
	["Graphics", "GRAPHICS", "Quality presets change 3D resolution, shadows and draw distance."],
	["Audio", "AUDIO", "Volume."],
	["Mobile", "MOBILE", "Touch controls (phones and tablets)."],
]

var _tab_buttons := {}

## Emitted instead of going back to the lobby when the screen is used outside
## the main menu (from the pause menu, during a match).
signal closed


func _ready() -> void:
	%Quality.add_item("Low (more FPS)", Config.Quality.LOW)
	%Quality.add_item("Medium", Config.Quality.MEDIUM)
	%Quality.add_item("High", Config.Quality.HIGH)
	%FpsLimit.add_item("Unlimited", 0)
	%FpsLimit.add_item("60 FPS", 60)
	%FpsLimit.add_item("120 FPS", 120)
	%FpsLimit.add_item("144 FPS", 144)
	%AimAssist.add_item("Off", Config.AimAssist.OFF)
	%AimAssist.add_item("Light", Config.AimAssist.LIGHT)
	%AimAssist.add_item("Standard", Config.AimAssist.STANDARD)
	%Sensitivity.value_changed.connect(func(_v): _update_values())
	%Fov.value_changed.connect(func(_v): _update_values())
	%Volume.value_changed.connect(func(_v): _update_values())
	%RenderScale.value_changed.connect(func(_v): _update_values())
	%Brightness.value_changed.connect(func(_v): _update_values())
	%TouchStick.value_changed.connect(func(_v): _update_values())
	%TouchOpacity.value_changed.connect(func(_v): _update_values())
	for page in PAGES:
		_add_tab(page[0], page[1])
	bind_button(%Save, _save)
	bind_button(%Discard, _close)
	bind_button(%Back, _close)


func enter(_arg: Variant) -> void:
	%Sensitivity.value = Config.sensitivity
	%Fov.value = Config.fov
	%Volume.value = Config.volume
	%Fullscreen.button_pressed = Config.fullscreen
	%Quality.select(Config.quality)
	%ShowFps.button_pressed = Config.show_fps
	%Vsync.button_pressed = Config.vsync
	%FpsLimit.select(maxi(%FpsLimit.get_item_index(Config.fps_limit), 0))
	%RenderScale.value = Config.render_scale * 100.0
	%Brightness.value = Config.brightness * 100.0
	%ScreenShake.button_pressed = Config.screen_shake
	_tab_buttons["Mobile"].visible = Touch.active
	_show_page("Controls")
	%TouchStick.value = Config.touch_joystick_size * 100.0
	%TouchOpacity.value = Config.touch_opacity * 100.0
	%AimAssist.select(clampi(Config.aim_assist, 0, 2))
	_update_values()


func _add_tab(id: String, title: String) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(190, 44)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"MenuBtn"
	button.add_theme_font_override("font", RAIL_FONT)
	button.add_theme_font_size_override("font_size", 21)
	%Tabs.add_child(button)
	_tab_buttons[id] = button
	bind_button(button, func(): _show_page(id))


## Shows one page; its tab turns solid orange.
func _show_page(id: String) -> void:
	for page in PAGES:
		var on: bool = page[0] == id
		(get_node("%" + page[0]) as Control).visible = on
		(_tab_buttons[page[0]] as Button).theme_type_variation = &"PrimaryButton" if on else &"MenuBtn"
		if on:
			%PageTitle.text = page[1]
			%PageHint.text = page[2]


func _update_values() -> void:
	%SensitivityValue.text = "%.2f" % %Sensitivity.value
	%FovValue.text = "%d°" % int(%Fov.value)
	%VolumeValue.text = "%d%%" % int(round(%Volume.value * 100.0))
	%RenderScaleValue.text = "%d%%" % int(%RenderScale.value)
	%BrightnessValue.text = "%d%%" % int(%Brightness.value)
	%TouchStickValue.text = "%d%%" % int(%TouchStick.value)
	%TouchOpacityValue.text = "%d%%" % int(%TouchOpacity.value)


func _save() -> void:
	Config.sensitivity = %Sensitivity.value
	Config.fov = %Fov.value
	Config.volume = %Volume.value
	Config.fullscreen = %Fullscreen.button_pressed
	Config.quality = %Quality.get_selected_id()
	Config.show_fps = %ShowFps.button_pressed
	Config.vsync = %Vsync.button_pressed
	Config.fps_limit = %FpsLimit.get_selected_id()
	Config.render_scale = %RenderScale.value / 100.0
	Config.brightness = %Brightness.value / 100.0
	Config.screen_shake = %ScreenShake.button_pressed
	Config.touch_joystick_size = %TouchStick.value / 100.0
	Config.touch_opacity = %TouchOpacity.value / 100.0
	Config.aim_assist = %AimAssist.get_selected_id()
	Config.save_cfg()
	Config.apply()
	if menu:
		menu.set_status("Settings saved.", true)
	_close()


func _close() -> void:
	if menu:
		menu.show_screen("Home")
	else:
		closed.emit()
