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
