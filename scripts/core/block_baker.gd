class_name BlockBaker
## Junta vários [Block] em meshes com cores por vértice e cria as colisões deles
## num único StaticBody3D.
##
## - bake(): tudo num mesh só (armas, boneco: coisas pequenas).
## - bake_chunked(): mapas. Divide em pedaços (células) para o Godot poder pular
##   o que está fora da tela ou longe demais, e separa os detalhes pequenos num
##   mesh que só aparece de perto e não faz sombra.
## - build_occluders(): paredes grandes escondem o que está atrás delas.
##
## Os blocos continuam na árvore (sem desenhar nada), então nós filhos como
## Marker3D não são afetados.

## Blocos maiores que isto (em qualquer eixo) não entram em células: ficam num
## mesh "global" sempre desenhado (chão, muros do mapa).
const HUGE := 30.0


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


## Junta os blocos do mapa em células de `cell` metros. Cada célula vira até dois
## MeshInstance3D: o principal (some depois de `far` metros) e o de detalhes
## (some depois de `detail_far` metros e não projeta sombra).
## Devolve todos os MeshInstance3D criados, para ajustar as distâncias depois.
static func bake_chunked(root: Node3D, cell: float, far: float, detail_far: float) -> Array[MeshInstance3D]:
	var cells := {}
	for b in collect(root, true):
		if b.has_meta("baked") or not b.visible:
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
		mi.name = "Global" if huge else ("Detalhes_%d_%d" % [key.x, key.y] if detail else "Celula_%d_%d" % [key.x, key.y])
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


## Ajusta as distâncias de desenho de meshes criados por bake_chunked().
static func set_ranges(meshes: Array[MeshInstance3D], far: float, detail_far: float) -> void:
	for mi in meshes:
		if is_instance_valid(mi) and mi.has_meta("detail"):
			mi.visibility_range_end = detail_far if mi.get_meta("detail") else far


## Paredes e volumes grandes viram oclusores: o que estiver atrás deles não é
## desenhado. Só blocos sólidos, altos e largos (paredes, contêineres, casas).
static func build_occluders(root: Node3D) -> int:
	var container := Node3D.new()
	container.name = "Occluders"
	root.add_child(container)
	var n := 0
	for b in collect(root, true):
		if not b.collide or not b.visible or b.shape != Block.Shape.BOX:
			continue
		if b.size.y < 2.0 or maxf(b.size.x, b.size.z) < 2.5 or maxf(b.size.x, maxf(b.size.y, b.size.z)) > HUGE:
			continue
		var occ := OccluderInstance3D.new()
		var box := BoxOccluder3D.new()
		# Um pouco menor que o bloco, para nunca esconder algo que aparece pela borda.
		box.size = b.size * 0.95
		occ.occluder = box
		occ.transform = relative(root, b)
		container.add_child(occ)
		n += 1
	return n


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


## Monta um ArrayMesh com os blocos, com vértices relativos a `origin`.
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
