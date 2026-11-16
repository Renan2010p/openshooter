extends Area3D
## A health pickup dropped when a player is eliminated. The server owns the
## collision and the heal; clients only see the floating medkit.

signal taken(id: int, pid: int)

var id := 0
var server := false
var amount := 35
var world: World

var _t := 0.0

@onready var visual: Node3D = $Visual


func _ready() -> void:
	monitoring = server
	monitorable = false
	collision_mask = 2 if server else 0
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if visual:
		visual.rotation.y += delta * 1.4
		visual.position.y = 0.05 + sin(_t * 2.4) * 0.06


func _on_body_entered(body: Node3D) -> void:
	if not server or not multiplayer.is_server():
		return
	var player := body as Player
	if player == null:
		return
	taken.emit(id, player.pid)
