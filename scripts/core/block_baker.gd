class_name BlockBaker
## Junta vários [Block] em um único mesh com cores por vértice e, se pedido,
## cria as colisões deles num único StaticBody3D.
##
## Os blocos continuam na árvore (sem desenhar nada), então nós filhos como
## Marker3D não são afetados.


## Blocos sob `root`. Com `recursive = false`, só os filhos diretos.
static func collect(root: Node, recursive := true) -> Array[Block]:
	var out: Array[Block] = []
	for child in root.get_children():
		if child is Block:
			out.append(child)
		if recursive and child.get_child_count() > 0:
			out.append_array(collect(child, true))
	return out


## Transformação de `node` relativa a `root` (funciona fora da árvore também).
static func relative(root: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Cria um MeshInstance3D "BakedMesh" filho de `root` com todos os blocos juntos.
static func bake(root: Node3D, recursive := true, blocks: Array[Block] = []) -> MeshInstance3D:
	if blocks.is_empty():
		blocks = collect(root, recursive)
	var groups := {}
	for b in blocks:
		if b.has_meta("baked") or not b.visible:
			continue
		b.set_meta("baked", true)
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
	var out := MeshInstance3D.new()
	out.name = "BakedMesh"
	out.mesh = mesh
	root.add_child(out)
	return out


## Colisões de todos os blocos com `collide = true`, num único StaticBody3D.
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
