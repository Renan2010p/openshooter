extends SceneTree
## Measures how long each map takes to load and bake, and checks that the
## native mesher produces the same geometry every run.
##
##   godot --headless --path . -s res://tests/bake_bench.gd               # native mesher
##   godot --headless --path . -s res://tests/bake_bench.gd -- --no-native # GDScript mesher
##   ... -- --runs=5 --dump=FILE.txt   (dump writes a geometry checksum per map)

const MAPS := [
	"res://scenes/maps/neighborhood.tscn",
	"res://scenes/maps/harbor.tscn",
	"res://scenes/maps/desert.tscn",
	"res://scenes/maps/arctic.tscn",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var runs := int(args.get("runs", "3"))
	var native := BlockBaker.native_available() and not args.has("no-native")
	var ping := ""
	if native:
		ping = ClassDB.instantiate("NativeOps").ping()
	print("BAKE mesher=%s %s" % ["native" if native else "gdscript", ping])
	var dump := ""
	var total_best := 0.0
	var native_best := 0.0
	for path in MAPS:
		var packed: PackedScene = load(path)
		var times: Array[float] = []
		var native_times: Array[float] = []
		var sum := ""
		for r in runs:
			var map: Node3D = packed.instantiate()
			BlockBaker.native_bake_usec = 0
			var t0 := Time.get_ticks_usec()
			root.add_child(map)  # _ready(): expansion + bake
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			native_times.append(BlockBaker.native_bake_usec / 1000.0)
			if r == 0:
				sum = _checksum(map)
			root.remove_child(map)
			map.free()
		times.sort()
		native_times.sort()
		total_best += times[0]
		native_best += native_times[0]
		print("BAKE %-14s load best=%6.1f ms median=%6.1f ms | bake_map best=%5.1f ms | %s" % [path.get_file().get_basename(), times[0], times[times.size() / 2], native_times[0], sum])
		dump += "%s %s\n" % [path.get_file(), sum]
	print("BAKE total load best=%.1f ms, bake_map best=%.1f ms" % [total_best, native_best])
	if args.has("dump"):
		var f := FileAccess.open(args["dump"], FileAccess.WRITE)
		f.store_string(dump)
	quit()


## Vertex/index/collision counts plus a rounded position sum for every baked
## chunk, so two meshers can be compared.
func _checksum(map: Node) -> String:
	var verts := 0
	var idx := 0
	var faces := 0
	var acc := Vector3.ZERO
	var chunks := map.find_child("BakedChunks", true, false)
	if chunks:
		for mi in chunks.get_children():
			var mesh: ArrayMesh = (mi as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				verts += v.size()
				idx += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
				for p in v:
					acc += p + (mi as Node3D).position
	for body in map.find_children("Collision", "StaticBody3D", true, false):
		for cs in body.get_children():
			if (cs as CollisionShape3D).shape is ConcavePolygonShape3D:
				faces += ((cs as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size()
	return "verts=%d idx=%d col=%d sum=(%.1f,%.1f,%.1f)" % [verts, idx, faces, acc.x, acc.y, acc.z]
