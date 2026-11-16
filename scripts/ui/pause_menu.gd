class_name PauseMenu
extends PanelContainer
## In-match menu (ESC).

signal resume_pressed
signal leave_pressed


## Replaces the keyboard help with the touch-control guide on mobile.
func set_touch_help() -> void:
	%Help.text = "Left stick: move  ·  Right stick: aim / shoot\nTouch the right stick to aim automatically\nPush it past halfway to fire  ·  CROUCH  ·  RELOAD  ·  JUMP"


func _ready() -> void:
	UiMotion.attach(%Resume)
	UiMotion.attach(%Leave)
	%Resume.pressed.connect(func(): resume_pressed.emit())
	%Leave.pressed.connect(func(): leave_pressed.emit())
