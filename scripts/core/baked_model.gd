class_name BakedModel
extends Node3D
## Raiz de um modelo pequeno feito de [Block] (armas, mina). Junta tudo num mesh
## ao entrar na árvore. O Marker3D "Muzzle" marca a ponta do cano.

## Brilho e sombra do modelo inteiro.
@export var cast_shadows := true


func _ready() -> void:
	var mi := BlockBaker.bake(self)
	if mi and not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Posição global da ponta do cano (ou da origem, se não houver "Muzzle").
func muzzle_position() -> Vector3:
	var m := get_node_or_null("Muzzle") as Node3D
	return m.global_position if m else global_position


func set_render_layer(layer: int) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = layer
