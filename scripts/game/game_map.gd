class_name GameMap
extends Node3D
## Mapa (ex.: scenes/maps/bairro.tscn).
##
## Estrutura esperada:
##   Geometry   — [Block]s e cenas de props. Viram um mesh e uma colisão só.
##   Spawns     — Marker3D onde os jogadores nascem.
##   Waypoints  — Marker3D por onde os bots passeiam.
##   Sun, WorldEnvironment — luz e céu (ajustados pela qualidade gráfica).

@export var display_name := "Mapa"

@onready var geometry: Node3D = $Geometry
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var spawns: Array[Vector3] = []
var waypoints: Array[Vector3] = []


func _ready() -> void:
	BlockBaker.build_collision(geometry)
	BlockBaker.bake(geometry)
	for m in $Spawns.get_children():
		spawns.append((m as Node3D).global_position)
	for m in $Waypoints.get_children():
		waypoints.append((m as Node3D).global_position)
	Config.apply_quality(sun, world_environment.environment, get_viewport())
	Config.changed.connect(func(): Config.apply_quality(sun, world_environment.environment, get_viewport()))


func random_waypoint() -> Vector3:
	return waypoints.pick_random() if not waypoints.is_empty() else Vector3.ZERO


## Ponto de nascimento mais longe dos inimigos (com um pouco de sorte).
func best_spawn(avoid: Array) -> Vector3:
	if spawns.is_empty():
		return Vector3(0, 1, 0)
	var best: Vector3 = spawns.pick_random()
	var best_d := -1.0
	for s in spawns:
		var d := 1e9
		for a in avoid:
			d = minf(d, s.distance_to(a))
		d += randf() * 6.0
		if d > best_d:
			best_d = d
			best = s
	return best
