extends Node3D
## Explosion (scenes/fx/explosion.tscn): a fireball that bursts out, lingers and
## collapses while the light fades out.

@export var duration := 0.5
@export var final_scale := 8.0

@onready var fireball: MeshInstance3D = $Fireball
@onready var light: OmniLight3D = $Light


func _ready() -> void:
	fireball.scale = Vector3.ONE * 0.2
	fireball.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	var t := create_tween().set_parallel()
	t.tween_property(fireball, "scale", Vector3.ONE * final_scale, duration * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(fireball, "rotation:y", fireball.rotation.y + 1.2, duration)
	t.tween_property(light, "light_energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(fireball, "scale", Vector3.ZERO, duration * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)
