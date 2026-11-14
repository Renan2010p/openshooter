extends MenuScreen
## Configurações: mouse, campo de visão, volume, tela cheia, qualidade e FPS.


func _ready() -> void:
	%Quality.add_item("Baixa (mais FPS)", Config.Quality.LOW)
	%Quality.add_item("Média", Config.Quality.MEDIUM)
	%Quality.add_item("Alta", Config.Quality.HIGH)
	bind_button(%Save, _save)
	bind_button(%Back, func(): menu.show_screen("Home"))


func enter(_arg: Variant) -> void:
	%Sensitivity.value = Config.sensitivity
	%Fov.value = Config.fov
	%Volume.value = Config.volume
	%Fullscreen.button_pressed = Config.fullscreen
	%Quality.select(Config.quality)
	%ShowFps.button_pressed = Config.show_fps


func _save() -> void:
	Config.sensitivity = %Sensitivity.value
	Config.fov = %Fov.value
	Config.volume = %Volume.value
	Config.fullscreen = %Fullscreen.button_pressed
	Config.quality = %Quality.get_selected_id()
	Config.show_fps = %ShowFps.button_pressed
	Config.save_cfg()
	Config.apply()
	menu.set_status("Configurações salvas.", true)
	menu.show_screen("Home")
