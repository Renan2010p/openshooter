extends Node3D
## Explosão (scenes/fx/explosion.tscn): bola de fogo que cresce e luz que apaga.

@export var duration := 0.4
@export var final_scale := 8.0

@onready var fireball: MeshInstance3D = $Fireball
@onready var light: OmniLight3D = $Light


func _ready() -> void:
	var t := create_tween().set_parallel()
	t.tween_property(fireball, "scale", Vector3.ONE * final_scale, duration * 0.6)
	t.tween_property(light, "light_energy", 0.0, duration)
	t.chain().tween_callback(queue_free)
