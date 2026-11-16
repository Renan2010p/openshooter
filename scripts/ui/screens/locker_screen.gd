extends MenuScreen
## Locker: name and character colors, with a rotating 3D preview beside them.


func _ready() -> void:
	for key in ["shirt", "pants", "skin"]:
		var picker: ColorPickerButton = get_node("%" + key.capitalize())
		picker.color_changed.connect(func(c: Color):
			Config.set(key, c)
			menu.rebuild_avatar())
	bind_button(%Save, _save)
	bind_button(%Back, func():
		Config.load_cfg()
		menu.rebuild_avatar()
		menu.show_screen("Home"))


func enter(_arg: Variant) -> void:
	%PlayerName.text = Config.player_name
	%Shirt.color = Config.shirt
	%Pants.color = Config.pants
	%Skin.color = Config.skin


func _save() -> void:
	var n: String = %PlayerName.text.strip_edges()
	if n != "":
		Config.player_name = n
	Config.save_cfg()
	menu.set_status("Locker saved.", true)
	menu.show_screen("Home")
