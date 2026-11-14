extends MeshInstance3D
## Marca de impacto (scenes/fx/impact.tscn): um cubinho que encolhe e some.

@export var lifetime := 0.35


func setup(pos: Vector3, color: Color) -> void:
	global_position = pos
	var m := material_override.duplicate() as StandardMaterial3D
	m.albedo_color = color
	material_override = m
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ZERO, lifetime)
	t.tween_callback(queue_free)
