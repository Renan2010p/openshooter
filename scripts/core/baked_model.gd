class_name BakedModel
extends Node3D
## Root of a small model built from [Block] nodes (weapons, mines). Merges
## everything into one mesh when it enters the tree. The "Muzzle" Marker3D
## marks the tip of the barrel.

## Brightness and shadow settings for the whole model.
@export var cast_shadows := true


func _ready() -> void:
	var mi := BlockBaker.bake(self)
	if mi and not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Global position of the muzzle (or the model origin when there is no "Muzzle").
func muzzle_position() -> Vector3:
	var m := get_node_or_null("Muzzle") as Node3D
	return m.global_position if m else global_position


func set_render_layer(layer: int) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = layer
