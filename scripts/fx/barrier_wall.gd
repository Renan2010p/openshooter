extends StaticBody3D
## Energy wall created by the Barrier (scenes/fx/barrier_wall.tscn).
## Blocks shots and movement; the server controls its health.

var barrier_id := 0
var health := 300.0

@onready var visual: Node3D = $Visual


func _ready() -> void:
	set_meta("barrier_id", barrier_id)
	visual.scale = Vector3(1, 0.01, 1)
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Flashes when hit.
func flash() -> void:
	visual.scale = Vector3(1.04, 1.0, 1.4)
	create_tween().tween_property(visual, "scale", Vector3.ONE, 0.12)


func collapse() -> void:
	collision_layer = 0
	var t := create_tween()
	t.tween_property(visual, "scale", Vector3(1, 0.01, 1), 0.2)
	t.tween_callback(queue_free)
