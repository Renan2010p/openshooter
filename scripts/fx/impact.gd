extends MeshInstance3D
## Impact mark (scenes/fx/impact.tscn): a small cube that pops, spins and
## shrinks away.

@export var lifetime := 0.35

## One material per impact color, shared by every impact (duplicating a
## material per shot breaks batching and allocates on every hit).
static var _materials := {}


func setup(pos: Vector3, color: Color) -> void:
	global_position = pos
	if not _materials.has(color):
		var m := (material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = color
		_materials[color] = m
	material_override = _materials[color]
	rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	scale = Vector3.ONE * 0.4
	var spin := rotation + Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	var t := create_tween().set_parallel()
	t.tween_property(self, "scale", Vector3.ONE * 1.25, lifetime * 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation", spin, lifetime)
	t.chain().tween_property(self, "scale", Vector3.ZERO, lifetime * 0.82).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)
