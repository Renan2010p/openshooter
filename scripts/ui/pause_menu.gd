class_name PauseMenu
extends PanelContainer
## Menu de pausa da partida (ESC).

signal resume_pressed
signal leave_pressed


func _ready() -> void:
	%Resume.pressed.connect(func(): resume_pressed.emit())
	%Leave.pressed.connect(func(): leave_pressed.emit())
