extends Node3D
## Poison cloud (scenes/fx/poison_cloud.tscn). Visual only: damage is handled by
## the server ([ThrowableManager]). Grows, spins slowly and fades at the end.

var duration := 6.0
var radius := 4.5

@onready var puffs: Node3D = $Puffs

var _t := 0.0


func _ready() -> void:
	puffs.scale = Vector3.ONE * 0.2


func _process(delta: float) -> void:
	_t += delta
	var grow := clampf(_t / 0.6, 0.0, 1.0)
	var fade := clampf((duration - _t) / 0.8, 0.0, 1.0)
	puffs.scale = Vector3.ONE * (radius / 4.0) * grow * (0.6 + 0.4 * fade)
	puffs.rotate_y(delta * 0.3)
	for p in puffs.get_children():
		p.position.y += sin(_t * 1.5 + p.get_index()) * delta * 0.15
	if _t >= duration:
		queue_free()
