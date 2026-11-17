class_name GameMap
extends Node3D
## A map (for example scenes/maps/neighborhood.tscn).
##
## Expected structure:
##   Geometry   — [Block] nodes and prop scenes. Merged into one mesh and one collider.
##   Spawns     — Marker3D nodes where players spawn.
##   Waypoints  — Marker3D nodes the bots wander between.
##   Sun, WorldEnvironment — light and sky (adjusted by graphics quality).

@export var display_name := "Map"

@onready var geometry: Node3D = $Geometry
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

## Builds the larger outer district (roads, buildings, towers) around the core.
## Turn it off to work on the original 80 x 80 m layout in isolation.
@export var expand_map := true
## Size (meters) of each map chunk. Chunks that are off-screen or beyond the
## draw distance are not rendered.
@export var chunk_size := 24.0
## Large walls and volumes occlude whatever is behind them.
## Disabled by default: on an Intel HD 4400 it did not improve FPS and caused
## ~67 ms hitches. It may pay off on larger maps or other GPUs.
@export var use_occluders := false

var spawns: Array[Vector3] = []
var waypoints: Array[Vector3] = []
var _chunks: Array[MeshInstance3D] = []


func _ready() -> void:
	if "--log-native" in OS.get_cmdline_user_args():
		var native_on: bool = BlockBaker.native_available() and not "--no-native" in OS.get_cmdline_user_args()
		print("NATIVE MESHER: ", "yes" if native_on else "no")
	# Christmas edition: snowy ground and falling snow (before the expansion,
	# which copies the ground material).
	Holiday.apply_snow(self)
	if expand_map:
		MapExpansion.build(self)
	# Christmas edition: snowmen, trees, gifts and lights, merged into the
	# map by the bake below.
	Holiday.decorate_map(self)
	_tune_lighting()
	if use_occluders and not "--no-occluders" in OS.get_cmdline_user_args():
		BlockBaker.build_occluders(geometry)
	var use_native := BlockBaker.native_available() and not "--no-native" in OS.get_cmdline_user_args()
	if use_native:
		_chunks = BlockBaker.bake_chunked_native(geometry, chunk_size, Config.draw_distance(), Config.detail_distance())
		if _chunks.is_empty():
			BlockBaker.build_collision(geometry)
			_chunks = BlockBaker.bake_chunked(geometry, chunk_size, Config.draw_distance(), Config.detail_distance())
	else:
		BlockBaker.build_collision(geometry)
		_chunks = BlockBaker.bake_chunked(geometry, chunk_size, Config.draw_distance(), Config.detail_distance())
	for m in $Spawns.get_children():
		spawns.append((m as Node3D).global_position)
	for m in $Waypoints.get_children():
		waypoints.append((m as Node3D).global_position)
	_apply_quality()
	Config.changed.connect(_apply_quality)


## Softer, longer shadows and a warmer sun, closer to daylight photography.
func _tune_lighting() -> void:
	if sun == null:
		return
	sun.light_angular_distance = 0.55
	sun.shadow_blur = 1.35
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_split_2 = 0.28
	sun.directional_shadow_split_3 = 0.55


func _apply_quality() -> void:
	Config.apply_quality(sun, world_environment.environment, get_viewport())
	BlockBaker.set_ranges(_chunks, Config.draw_distance(), Config.detail_distance())


func random_waypoint() -> Vector3:
	return waypoints.pick_random() if not waypoints.is_empty() else Vector3.ZERO


## Spawn point farthest from the enemies (with a little randomness).
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
