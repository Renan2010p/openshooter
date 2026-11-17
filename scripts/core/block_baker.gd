class_name BlockBaker
## Merges multiple [Block] nodes into vertex-colored meshes and builds their
## collision shapes inside a single StaticBody3D.
##
## - bake(): everything into one mesh (weapons, character: small objects).
## - bake_chunked(): maps. Splits geometry into cells so Godot can skip what is
##   off-screen or too far away, and moves small details into a mesh that only
##   appears up close and casts no shadows.
## - build_occluders(): large walls hide whatever is behind them.
##
## Blocks remain in the tree (drawing nothing), so child nodes such as
## Marker3D are unaffected.

## Blocks larger than this (on any axis) are not split into cells: they go into
## an always-drawn "global" mesh (ground, map boundary walls).
const HUGE := 30.0


## Blocks under `root`. With `recursive = false`, only direct children.
static func collect(root: Node, recursive := true) -> Array[Block]:
	var out: Array[Block] = []
	for child in root.get_children():
		if child is Block:
			out.append(child)
		if recursive and child.get_child_count() > 0:
			out.append_array(collect(child, true))
	return out


## Is the block visible? Checks the block and every parent up to `root` (a
## hidden parent, such as the left hand of a one-handed weapon, also hides it).
static func is_shown(root: Node, b: Node) -> bool:
	var n := b
	while n != null and n != root:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## Transform of `node` relative to `root` (works outside the tree too).
static func relative(root: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Creates a MeshInstance3D named "BakedMesh" under `root` with all blocks merged.
static func bake(root: Node3D, recursive := true, blocks: Array[Block] = []) -> MeshInstance3D:
	if blocks.is_empty():
		blocks = collect(root, recursive)
	var todo: Array[Block] = []
	for b in blocks:
		if not b.has_meta("baked") and b.visible:
			b.set_meta("baked", true)
			todo.append(b)
	var mesh := _mesh_from(root, todo, Vector3.ZERO)
	if mesh == null:
		return null
	var out := MeshInstance3D.new()
	out.name = "BakedMesh"
	out.mesh = mesh
	root.add_child(out)
	return out


## Merges map blocks into cells of `cell` meters. Each cell becomes up to two
## MeshInstance3D nodes: the main mesh (hidden beyond `far` meters) and the
## details mesh (hidden beyond `detail_far` meters and casting no shadows).
## Returns every created MeshInstance3D so distances can be adjusted later.
static func bake_chunked(root: Node3D, cell: float, far: float, detail_far: float) -> Array[MeshInstance3D]:
	var cells := {}
	for b in collect(root, true):
		if b.has_meta("baked") or not is_shown(root, b):
			continue
		b.set_meta("baked", true)
		var xf := relative(root, b)
		var huge := maxf(b.size.x, maxf(b.size.y, b.size.z)) > HUGE
		var key: Vector3i
		if huge:
			key = Vector3i(0, 0, -999999)
		else:
			key = Vector3i(floori(xf.origin.x / cell), floori(xf.origin.z / cell), 1 if b.is_detail() else 0)
		if not cells.has(key):
			cells[key] = [] as Array[Block]
		(cells[key] as Array[Block]).append(b)
	var out: Array[MeshInstance3D] = []
	var container := Node3D.new()
	container.name = "BakedChunks"
	root.add_child(container)
	for key: Vector3i in cells:
		var huge := key.z == -999999
		var detail := key.z == 1
		var origin := Vector3.ZERO if huge else Vector3((key.x + 0.5) * cell, 0, (key.y + 0.5) * cell)
		var mesh := _mesh_from(root, cells[key], origin)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Global" if huge else ("Details_%d_%d" % [key.x, key.y] if detail else "Cell_%d_%d" % [key.x, key.y])
		mi.mesh = mesh
		mi.position = origin
		if not huge:
			mi.set_meta("detail", detail)
			mi.visibility_range_end = detail_far if detail else far
			mi.visibility_range_end_margin = 4.0
		if detail:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(mi)
		out.append(mi)
	return out


## Total time spent inside NativeOps.bake_map() (microseconds), for benchmarks.
static var native_bake_usec := 0

## True when the optional native extension is loaded.
static func native_available() -> bool:
	return ClassDB.class_exists("NativeOps")


## Native version of bake_chunked(): the merge and chunking happen in the
## extension, and each chunk becomes ONE surface with the shared map shader.
## That keeps draw calls low on mobile. Falls back to GDScript on any problem.
static func bake_chunked_native(root: Node3D, cell: float, far: float, detail_far: float) -> Array[MeshInstance3D]:
	var todo: Array[Block] = []
	for b in collect(root, true):
		if b.has_meta("baked") or not is_shown(root, b):
			continue
		todo.append(b)
	if todo.is_empty():
		return []
	var data := PackedFloat32Array()
	data.resize(todo.size() * 24)
	var i := 0
	for b in todo:
		var xf := relative(root, b)
		var bs := xf.basis
		data[i] = bs.x.x
		data[i + 1] = bs.x.y
		data[i + 2] = bs.x.z
		data[i + 3] = bs.y.x
		data[i + 4] = bs.y.y
		data[i + 5] = bs.y.z
		data[i + 6] = bs.z.x
		data[i + 7] = bs.z.y
		data[i + 8] = bs.z.z
		data[i + 9] = xf.origin.x
		data[i + 10] = xf.origin.y
		data[i + 11] = xf.origin.z
		data[i + 12] = b.size.x
		data[i + 13] = b.size.y
		data[i + 14] = b.size.z
		data[i + 15] = b.color.r
		data[i + 16] = b.color.g
		data[i + 17] = b.color.b
		data[i + 18] = b.metallic
		data[i + 19] = b.roughness
		data[i + 20] = b.emission
		data[i + 21] = float(b.shape)
		data[i + 22] = 1.0 if b.collide else 0.0
		var huge := maxf(b.size.x, maxf(b.size.y, b.size.z)) > HUGE
		data[i + 23] = (1.0 if b.is_detail() else 0.0) + (2.0 if huge else 0.0)
		i += 24
	var ops = ClassDB.instantiate("NativeOps")
	if ops == null:
		return bake_chunked(root, cell, far, detail_far)
	var t0 := Time.get_ticks_usec()
	var result: Array = ops.bake_map(data, todo.size(), cell)
	native_bake_usec += Time.get_ticks_usec() - t0
	if result.is_empty():
		return bake_chunked(root, cell, far, detail_far)
	for b in todo:
		b.set_meta("baked", true)
	var material := map_material()
	var out: Array[MeshInstance3D] = []
	var container := Node3D.new()
	container.name = "BakedChunks"
	root.add_child(container)
	for item in result:
		var vertices: PackedVector3Array = item["vertices"]
		if vertices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = item["normals"]
		arrays[Mesh.ARRAY_COLOR] = item["colors"]
		arrays[Mesh.ARRAY_TEX_UV2] = item["uv2"]
		arrays[Mesh.ARRAY_INDEX] = item["indices"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var mi := MeshInstance3D.new()
		var huge: bool = item["huge"]
		var detail: bool = item["detail"]
		mi.name = "Global" if huge else ("Details" if detail else "Chunk")
		mi.mesh = mesh
		mi.position = item["origin"]
		if not huge:
			mi.visibility_range_end = detail_far if detail else far
			mi.visibility_range_end_margin = 4.0
		if detail:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(mi)
		out.append(mi)
	# Collision: one concave mesh per chunk instead of one box per block.
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var shapes := 0
	for item in result:
		var faces: PackedVector3Array = item["collision"]
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		shapes += 1
	if shapes == 0:
		body.queue_free()
	return out


static var _map_material: ShaderMaterial

## One material for the whole map: color, roughness, metallic and emission are
## packed per vertex, so a chunk needs a single surface (and a single draw call).
static func map_material() -> ShaderMaterial:
	if _map_material == null:
		_map_material = ShaderMaterial.new()
		_map_material.shader = load("res://resources/materials/map_surface.gdshader")
	return _map_material


## Adjusts the draw distances of meshes created by bake_chunked().
static func set_ranges(meshes: Array[MeshInstance3D], far: float, detail_far: float) -> void:
	for mi in meshes:
		if is_instance_valid(mi) and mi.has_meta("detail"):
			mi.visibility_range_end = detail_far if mi.get_meta("detail") else far


## Large walls and volumes become occluders: whatever is behind them is not
## drawn. Only solid, tall and wide blocks (walls, containers, houses).
static func build_occluders(root: Node3D) -> int:
	var container := Node3D.new()
	container.name = "Occluders"
	root.add_child(container)
	var n := 0
	for b in collect(root, true):
		if not b.collide or not is_shown(root, b) or b.shape != Block.Shape.BOX:
			continue
		if b.size.y < 2.0 or maxf(b.size.x, b.size.z) < 2.5 or maxf(b.size.x, maxf(b.size.y, b.size.z)) > HUGE:
			continue
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		# Slightly smaller than the block, so it never hides something peeking
		# around the edge.
		box.size = b.size * 0.95
		occ.occluder = box
		occ.transform = relative(root, b)
		container.add_child(occ)
		n += 1
	return n


## Collision for every block with `collide = true`, in a single StaticBody3D.
static func build_collision(root: Node3D, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = layer
	body.collision_mask = 0
	for b in collect(root, true):
		if not b.collide:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = b.make_shape()
		cs.transform = relative(root, b)
		body.add_child(cs)
	root.add_child(body)
	return body


## Builds an ArrayMesh from the blocks, with vertices relative to `origin`.
static func _mesh_from(root: Node, blocks: Array, origin: Vector3) -> ArrayMesh:
	var groups := {}
	for b: Block in blocks:
		var key: String
		if b.emission > 0.0:
			key = "e|%s|%s" % [b.color.to_html(), b.emission]
		else:
			key = "m" if b.metallic > 0.3 else "d"
		if not groups.has(key):
			groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array(), "block": b}
		var g: Dictionary = groups[key]
		var arr: Array = b.make_mesh().get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var xf := relative(root, b)
		xf.origin -= origin
		var base: int = g.v.size()
		for k in verts.size():
			g.v.append(xf * verts[k])
			g.n.append((xf.basis * norms[k]).normalized())
			g.c.append(b.color)
		for k in idx:
			g.i.append(base + k)
	if groups.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for key in groups:
		var g: Dictionary = groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_INDEX] = g.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var src: Block = g.block
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.metallic = src.metallic if key == "m" else 0.0
		mat.roughness = src.roughness if key == "m" else 0.85
		if key.begins_with("e|"):
			mat.emission_enabled = true
			mat.emission = src.color
			mat.emission_energy_multiplier = src.emission
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh
