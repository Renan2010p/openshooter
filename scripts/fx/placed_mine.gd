extends Node3D
## Mine placed on the ground (scenes/fx/placed_mine.tscn): the LED blinks.

@export var blink_interval := 0.6

@onready var led: MeshInstance3D = $Led

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	led.visible = fmod(_t, blink_interval) < blink_interval * 0.4
