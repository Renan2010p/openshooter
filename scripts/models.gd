class_name Models
## Construção dos modelos em blocos: boneco e armas (cano apontando para -Z).

static var _mats := {}


static func mat(c: Color, rough := 0.8, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3, node_name := "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	if node_name != "":
		n.name = node_name
	parent.add_child(n)
	return n


## Boneco em blocos. Devolve um dicionário com as partes que se mexem.
static func avatar(shirt: Color, pants: Color, skin: Color) -> Dictionary:
	var root := Node3D.new()
	var parts := {"root": root}
	var leg_l := pivot(root, Vector3(-0.17, 0.85, 0))
	var leg_r := pivot(root, Vector3(0.17, 0.85, 0))
	for leg in [leg_l, leg_r]:
		box(leg, Vector3(0.32, 0.85, 0.34), Vector3(0, -0.42, 0), mat(pants))
		box(leg, Vector3(0.33, 0.12, 0.38), Vector3(0, -0.8, -0.02), mat(Color(0.12, 0.1, 0.09)))
	box(root, Vector3(0.7, 0.8, 0.4), Vector3(0, 1.25, 0), mat(shirt))
	box(root, Vector3(0.72, 0.08, 0.42), Vector3(0, 0.88, 0), mat(Color(0.15, 0.12, 0.1)))
	var arm_l := pivot(root, Vector3(-0.47, 1.58, 0))
	var arm_r := pivot(root, Vector3(0.47, 1.58, 0))
	for arm in [arm_l, arm_r]:
		box(arm, Vector3(0.26, 0.36, 0.3), Vector3(0, -0.15, 0), mat(shirt))
		box(arm, Vector3(0.24, 0.48, 0.28), Vector3(0, -0.55, 0), mat(skin))
	var head := pivot(root, Vector3(0, 1.66, 0))
	box(head, Vector3(0.48, 0.48, 0.48), Vector3(0, 0.24, 0), mat(skin))
	var dark := mat(Color(0.08, 0.08, 0.08))
	box(head, Vector3(0.07, 0.1, 0.02), Vector3(-0.1, 0.3, -0.245), dark)
	box(head, Vector3(0.07, 0.1, 0.02), Vector3(0.1, 0.3, -0.245), dark)
	box(head, Vector3(0.18, 0.04, 0.02), Vector3(0, 0.15, -0.245), dark)
	parts.merge({"leg_l": leg_l, "leg_r": leg_r, "arm_l": arm_l, "arm_r": arm_r, "head": head})
	bake_tree(root)
	return parts


## Arma em blocos. A origem é o cabo; o cano aponta para -Z. Meta "muzzle" = ponta do cano.
static func weapon(idx: int) -> Node3D:
	var g := Node3D.new()
	var black := mat(Color(0.1, 0.1, 0.11), 0.4, 0.7)
	var gray := mat(Color(0.32, 0.33, 0.35), 0.4, 0.8)
	var wood := mat(Color(0.45, 0.27, 0.13), 0.7)
	var muzzle := Vector3(0, 0.08, -0.5)
	match idx:
		Weapons.KNIFE:
			box(g, Vector3(0.05, 0.06, 0.16), Vector3(0, 0, 0.02), black)
			box(g, Vector3(0.015, 0.06, 0.26), Vector3(0, 0.01, -0.19), mat(Color(0.8, 0.82, 0.85), 0.2, 1.0))
			muzzle = Vector3(0, 0, -0.32)
		Weapons.PISTOL:
			box(g, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.05, 0), black, Vector3(-12, 0, 0))
			box(g, Vector3(0.055, 0.07, 0.24), Vector3(0, 0.05, -0.06), gray)
			muzzle = Vector3(0, 0.05, -0.19)
		Weapons.RIFLE:
			box(g, Vector3(0.07, 0.1, 0.55), Vector3(0, 0.06, -0.15), black)
			box(g, Vector3(0.07, 0.12, 0.3), Vector3(0, 0.0, 0.22), wood)
			box(g, Vector3(0.075, 0.06, 0.22), Vector3(0, 0.04, -0.3), wood)
			box(g, Vector3(0.05, 0.2, 0.08), Vector3(0, -0.1, -0.12), black, Vector3(20, 0, 0))
			box(g, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.06, 0.04), wood, Vector3(-15, 0, 0))
			cyl(g, 0.016, 0.3, Vector3(0, 0.08, -0.55), black, Vector3(90, 0, 0))
			muzzle = Vector3(0, 0.08, -0.7)
		Weapons.SHOTGUN:
			cyl(g, 0.025, 0.75, Vector3(0, 0.08, -0.3), black, Vector3(90, 0, 0))
			box(g, Vector3(0.07, 0.07, 0.3), Vector3(0, 0.03, -0.32), wood)
			box(g, Vector3(0.07, 0.1, 0.2), Vector3(0, 0.05, -0.02), gray)
			box(g, Vector3(0.07, 0.12, 0.3), Vector3(0, -0.0, 0.22), wood)
			muzzle = Vector3(0, 0.08, -0.68)
		Weapons.SNIPER:
			box(g, Vector3(0.07, 0.09, 0.5), Vector3(0, 0.05, -0.1), mat(Color(0.25, 0.3, 0.2), 0.6))
			box(g, Vector3(0.07, 0.13, 0.32), Vector3(0, 0.0, 0.28), mat(Color(0.25, 0.3, 0.2), 0.6))
			cyl(g, 0.014, 0.6, Vector3(0, 0.07, -0.62), black, Vector3(90, 0, 0))
			cyl(g, 0.035, 0.28, Vector3(0, 0.15, -0.08), black, Vector3(90, 0, 0))
			box(g, Vector3(0.04, 0.12, 0.06), Vector3(0, -0.06, 0.06), black, Vector3(-15, 0, 0))
			muzzle = Vector3(0, 0.07, -0.93)
		Weapons.MINE:
			cyl(g, 0.12, 0.05, Vector3(0, 0, -0.1), mat(Color(0.25, 0.28, 0.2), 0.6, 0.3))
			cyl(g, 0.03, 0.03, Vector3(0, 0.035, -0.1), mat(Color(1, 0.1, 0.1), 0.5, 0.0, 2.0))
			muzzle = Vector3(0, 0, -0.1)
	g.set_meta("muzzle", muzzle)
	bake(g)
	return g


## Junta os filhos diretos (MeshInstance3D de cor sólida) de `root` em um único
## mesh com cores por vértice: centenas de draw calls viram 1 ou 2.
## Materiais com textura ou brilho próprio ficam de fora.
static func bake(root: Node3D) -> void:
	var groups := {}
	var baked: Array[Node] = []
	for child in root.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not (mi.mesh is PrimitiveMesh):
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null or m.emission_enabled or m.albedo_texture != null:
			continue
		var key := 1 if m.metallic > 0.3 else 0
		if not groups.has(key):
			groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array(), "metal": m.metallic, "rough": m.roughness}
		var g: Dictionary = groups[key]
		var arr: Array = (mi.mesh as PrimitiveMesh).get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var xf := mi.transform
		var base: int = g.v.size()
		for k in verts.size():
			g.v.append(xf * verts[k])
			g.n.append((xf.basis * norms[k]).normalized())
			g.c.append(m.albedo_color)
		for k in idx:
			g.i.append(base + k)
		baked.append(mi)
	if groups.is_empty():
		return
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
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.metallic = g.metal
		mat.roughness = g.rough
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var out := MeshInstance3D.new()
	out.mesh = mesh
	out.name = "Baked"
	root.add_child(out)
	for n in baked:
		root.remove_child(n)
		n.free()


## Junta as partes de um boneco ou arma, pivô por pivô (as partes móveis continuam móveis).
static func bake_tree(root: Node3D) -> void:
	bake(root)
	for child in root.get_children():
		if child is Node3D and not (child is MeshInstance3D):
			bake_tree(child)


static func set_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer
	for c in node.get_children():
		set_layer(c, layer)
