extends Node3D
## Mina colocada no chão (scenes/fx/placed_mine.tscn): o LED pisca.

@export var blink_interval := 0.6

@onready var led: MeshInstance3D = $Led

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	led.visible = fmod(_t, blink_interval) < blink_interval * 0.4
