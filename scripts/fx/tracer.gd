extends MeshInstance3D
## Rastro de bala (scenes/fx/tracer.tscn): um traço fino que some rápido.

@export var lifetime := 0.05
@export var thickness := 0.025


func setup(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		queue_free()
		return
	global_position = (from + to) / 2.0
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	look_at(to, up)
	scale = Vector3(thickness, thickness, length)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
