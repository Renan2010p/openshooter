extends MeshInstance3D
## Bullet tracer (scenes/fx/tracer.tscn): a thin streak that thins out quickly.

@export var lifetime := 0.06
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
	# Thins out and pulls toward the target instead of vanishing in one frame.
	var t := create_tween().set_parallel()
	t.tween_property(self, "scale", Vector3(0.0, 0.0, length * 0.6), lifetime).set_ease(Tween.EASE_IN)
	t.tween_property(self, "global_position", global_position.lerp(to, 0.2), lifetime)
	t.chain().tween_callback(queue_free)
