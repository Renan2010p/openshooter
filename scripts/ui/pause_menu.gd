class_name PauseMenu
extends Control
## In-match menu (ESC): a dark panel on the left (Resume, Settings, Controls,
## Leave match). The scoreboard shows beside it (see Hud). Settings opens the
## same Settings screen as the main menu, on top of the match.

signal resume_pressed
signal leave_pressed

const SETTINGS_SCENE := preload("res://scenes/ui/screens/settings_screen.tscn")

var _settings: Control


## Replaces the keyboard help with the touch-control guide on mobile.
func set_touch_help() -> void:
	%Help.text = "Left stick: move  ·  Right stick: aim / shoot\nTouch the right stick to aim automatically\nPush it past halfway to fire  ·  CROUCH  ·  RELOAD  ·  JUMP\nChat: the speech bubble at the top"


func _ready() -> void:
	for button in [%Resume, %Settings, %Controls, %Leave]:
		UiMotion.attach(button)
	%Resume.pressed.connect(func(): resume_pressed.emit())
	%Leave.pressed.connect(func(): leave_pressed.emit())
	%Controls.toggled.connect(func(on: bool): %HelpCard.visible = on)
	%Settings.pressed.connect(_open_settings)
	visibility_changed.connect(func():
		if not visible:
			_close_settings())


func _open_settings() -> void:
	if is_instance_valid(_settings):
		return
	# Dark backing so the match does not show through the settings.
	_settings = ColorRect.new()
	(_settings as ColorRect).color = Color(0.043, 0.047, 0.063, 0.94)
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	var screen: MenuScreen = SETTINGS_SCENE.instantiate()
	_settings.add_child(screen)
	screen.closed.connect(_close_settings)
	add_child(_settings)
	$Side.visible = false
	screen.enter(null)
	UiMotion.pop_in(_settings)


func _close_settings() -> void:
	if is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	$Side.visible = true
