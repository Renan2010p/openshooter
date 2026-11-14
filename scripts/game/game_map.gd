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

## Tamanho (metros) de cada pedaço do mapa. Pedaços fora da tela ou além da
## distância de desenho não são desenhados.
@export var chunk_size := 16.0
## Paredes e volumes grandes escondem o que está atrás deles (oclusão).
## Desligado por padrão: na Intel HD 4400 não aumentou o FPS e causou travadas
## de ~67 ms. Pode valer a pena em mapas maiores ou em outras placas.
@export var use_occluders := false

var spawns: Array[Vector3] = []
var waypoints: Array[Vector3] = []
var _chunks: Array[MeshInstance3D] = []


func _ready() -> void:
	BlockBaker.build_collision(geometry)
	if use_occluders and not "--no-occluders" in OS.get_cmdline_user_args():
		BlockBaker.build_occluders(geometry)
	_chunks = BlockBaker.bake_chunked(geometry, chunk_size, Config.draw_distance(), Config.detail_distance())
	for m in $Spawns.get_children():
		spawns.append((m as Node3D).global_position)
	for m in $Waypoints.get_children():
		waypoints.append((m as Node3D).global_position)
	_apply_quality()
	Config.changed.connect(_apply_quality)


func _apply_quality() -> void:
	Config.apply_quality(sun, world_environment.environment, get_viewport())
	BlockBaker.set_ranges(_chunks, Config.draw_distance(), Config.detail_distance())


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
