extends MenuScreen
## Settings: input, display, graphics and advanced renderer options.

const FPS_LIMITS := [0, 60, 120, 144]


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
	bind_button(%Save, _save)
	bind_button(%Back, func(): menu.show_screen("Home"))


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
	%MobileCard.visible = Touch.active
	%Info.visible = not Touch.active
	%TouchStick.value = Config.touch_joystick_size * 100.0
	%TouchOpacity.value = Config.touch_opacity * 100.0
	%AimAssist.select(clampi(Config.aim_assist, 0, 2))
	_update_values()


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
	menu.set_status("Settings saved.", true)
	menu.show_screen("Home")
