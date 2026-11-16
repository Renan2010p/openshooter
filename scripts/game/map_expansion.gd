class_name MapExpansion
## Builds a larger outer district around each 80 x 80 m core map.
##
## The core map stays exactly as designed in the editor. Around it this class
## adds a themed belt (roughly 152 x 152 m total) with:
##   - extended ground and a boundary berm;
##   - two ring roads, sidewalks, crossings, manholes and road paint;
##   - enterable buildings with windows, awnings, signs, roofs and rooftop props;
##   - scaffold towers with ramps for vertical play;
##   - utility poles, street lamps and themed props for cover and detail;
##   - extra spawn points and bot waypoints.
##
## Everything is made of [Block] nodes, so [BlockBaker] merges it into the same
## chunked meshes and collision as the core map. Generation is deterministic:
## the same map always gets the same district.

const CORE := 40.0
const EXTENT := 76.0
const RING := 70.0
const WALL := 0.3
const DOOR_W := 1.75
const DOOR_H := 2.25

const THEME_PROPS := {
	"neighborhood": [
		"res://scenes/props/car.tscn",
		"res://scenes/props/tree.tscn",
		"res://scenes/props/pine_tree.tscn",
		"res://scenes/props/fence.tscn",
		"res://scenes/props/bench.tscn",
		"res://scenes/props/dumpster.tscn",
		"res://scenes/props/crate_stack.tscn",
		"res://scenes/props/barrels.tscn",
		"res://scenes/props/pallet.tscn",
	],
	"harbor": [
		"res://scenes/props/blue_container.tscn",
		"res://scenes/props/red_container.tscn",
		"res://scenes/props/green_container.tscn",
		"res://scenes/props/orange_container.tscn",
		"res://scenes/props/forklift.tscn",
		"res://scenes/props/crane.tscn",
		"res://scenes/props/pallet.tscn",
		"res://scenes/props/barrels.tscn",
		"res://scenes/props/crate_stack.tscn",
		"res://scenes/props/fuel_tank.tscn",
		"res://scenes/props/dumpster.tscn",
		"res://scenes/props/fence.tscn",
	],
	"desert": [
		"res://scenes/props/adobe_house.tscn",
		"res://scenes/props/adobe_house_terrace.tscn",
		"res://scenes/props/tent_1.tscn",
		"res://scenes/props/tent_2.tscn",
		"res://scenes/props/tent_3.tscn",
		"res://scenes/props/palm_tree.tscn",
		"res://scenes/props/cactus.tscn",
		"res://scenes/props/rocks.tscn",
		"res://scenes/props/well.tscn",
		"res://scenes/props/ruin.tscn",
		"res://scenes/props/crate_stack.tscn",
		"res://scenes/props/barrels.tscn",
		"res://scenes/props/sandbags.tscn",
	],
	"arctic": [
		"res://scenes/props/bunker.tscn",
		"res://scenes/props/watchtower.tscn",
		"res://scenes/props/radar.tscn",
		"res://scenes/props/tent_1.tscn",
		"res://scenes/props/pine_tree.tscn",
		"res://scenes/props/snow_pile.tscn",
		"res://scenes/props/crate_stack.tscn",
		"res://scenes/props/barrels.tscn",
		"res://scenes/props/rocks.tscn",
		"res://scenes/props/sandbags.tscn",
		"res://scenes/props/fuel_tank.tscn",
		"res://scenes/props/fence.tscn",
	],
}

const PROP_RADIUS := {
	"res://scenes/props/car.tscn": 2.6,
	"res://scenes/props/tree.tscn": 1.6,
	"res://scenes/props/pine_tree.tscn": 1.6,
	"res://scenes/props/fence.tscn": 3.0,
	"res://scenes/props/bench.tscn": 1.0,
	"res://scenes/props/dumpster.tscn": 1.4,
	"res://scenes/props/crate_stack.tscn": 1.8,
	"res://scenes/props/barrels.tscn": 1.6,
	"res://scenes/props/pallet.tscn": 1.4,
	"res://scenes/props/blue_container.tscn": 3.4,
	"res://scenes/props/red_container.tscn": 3.4,
	"res://scenes/props/green_container.tscn": 3.4,
	"res://scenes/props/orange_container.tscn": 3.4,
	"res://scenes/props/forklift.tscn": 2.2,
	"res://scenes/props/crane.tscn": 6.0,
	"res://scenes/props/fuel_tank.tscn": 3.0,
	"res://scenes/props/adobe_house.tscn": 5.5,
	"res://scenes/props/adobe_house_terrace.tscn": 5.5,
	"res://scenes/props/tent_1.tscn": 3.2,
	"res://scenes/props/tent_2.tscn": 3.2,
	"res://scenes/props/tent_3.tscn": 3.2,
	"res://scenes/props/palm_tree.tscn": 1.8,
	"res://scenes/props/cactus.tscn": 1.2,
	"res://scenes/props/rocks.tscn": 2.2,
	"res://scenes/props/well.tscn": 2.2,
	"res://scenes/props/ruin.tscn": 4.0,
	"res://scenes/props/sandbags.tscn": 2.0,
	"res://scenes/props/bunker.tscn": 5.0,
	"res://scenes/props/watchtower.tscn": 4.0,
	"res://scenes/props/radar.tscn": 3.5,
	"res://scenes/props/snow_pile.tscn": 2.0,
}

static var _prop_cache := {}


## Adds the outer district to `map`, before the map is baked.
static func build(map: GameMap) -> void:
	var theme := map.get_scene_file_path().get_file().get_basename()
	if theme == "":
		theme = "neighborhood"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme) + 20261115
	var root := Node3D.new()
	root.name = "OuterDistrict"
	map.geometry.add_child(root)
	var pal := _palette(theme)
	_ground(map, root)
	_open_core_walls(map)
	_gate_posts(root, pal)
	_boundary(root, rng, pal)
	_roads(root, rng, pal, theme)
	var lots := _buildings(root, rng, pal, theme)
	_towers(root, pal)
	_street_lamps(root, pal, theme)
	_power_line(root, pal)
	_scatter(root, rng, theme, lots)
	_markers(map)


static func _palette(theme: String) -> Dictionary:
	match theme:
		"harbor":
			return {
				"walls": [Color(0.52, 0.56, 0.6), Color(0.46, 0.5, 0.55), Color(0.58, 0.54, 0.48)],
				"trim": Color(0.7, 0.72, 0.74),
				"roof": Color(0.36, 0.39, 0.42),
				"glass": Color(0.2, 0.29, 0.36),
				"accent": [Color(0.82, 0.45, 0.16), Color(0.18, 0.42, 0.55), Color(0.65, 0.24, 0.2)],
				"road": Color(0.19, 0.2, 0.21),
				"walk": Color(0.58, 0.59, 0.58),
				"line": Color(0.88, 0.84, 0.55),
				"berm": Color(0.42, 0.45, 0.47),
				"metal": true,
			}
		"desert":
			return {
				"walls": [Color(0.78, 0.62, 0.44), Color(0.72, 0.56, 0.39), Color(0.82, 0.68, 0.5)],
				"trim": Color(0.88, 0.76, 0.58),
				"roof": Color(0.6, 0.47, 0.34),
				"glass": Color(0.22, 0.29, 0.33),
				"accent": [Color(0.72, 0.3, 0.2), Color(0.3, 0.46, 0.42), Color(0.78, 0.62, 0.24)],
				"road": Color(0.6, 0.5, 0.37),
				"walk": Color(0.7, 0.6, 0.46),
				"line": Color(0.85, 0.78, 0.6),
				"berm": Color(0.66, 0.52, 0.38),
				"metal": false,
			}
		"arctic":
			return {
				"walls": [Color(0.46, 0.51, 0.56), Color(0.39, 0.44, 0.49), Color(0.52, 0.57, 0.62)],
				"trim": Color(0.7, 0.74, 0.78),
				"roof": Color(0.32, 0.36, 0.41),
				"glass": Color(0.14, 0.22, 0.3),
				"accent": [Color(0.66, 0.18, 0.14), Color(0.14, 0.36, 0.5), Color(0.76, 0.54, 0.14)],
				"road": Color(0.24, 0.26, 0.29),
				"walk": Color(0.64, 0.68, 0.73),
				"line": Color(0.86, 0.86, 0.84),
				"berm": Color(0.72, 0.77, 0.82),
				"metal": true,
			}
		_:
			return {
				"walls": [Color(0.74, 0.68, 0.57), Color(0.65, 0.58, 0.5), Color(0.56, 0.62, 0.64), Color(0.7, 0.55, 0.46)],
				"trim": Color(0.87, 0.85, 0.8),
				"roof": Color(0.34, 0.3, 0.27),
				"glass": Color(0.19, 0.27, 0.34),
				"accent": [Color(0.62, 0.22, 0.18), Color(0.2, 0.42, 0.44), Color(0.72, 0.56, 0.2)],
				"road": Color(0.18, 0.19, 0.2),
				"walk": Color(0.56, 0.56, 0.53),
				"line": Color(0.9, 0.85, 0.55),
				"berm": Color(0.45, 0.44, 0.41),
				"metal": false,
			}


static func _shade(c: Color, f: float) -> Color:
	return Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0), c.a)


static func _block(parent: Node3D, pos: Vector3, size: Vector3, color: Color,
		collide := true, lod := Block.Lod.AUTO, rot := Vector3.ZERO,
		metallic := 0.0, roughness := 0.85) -> Block:
	var b := Block.new()
	b.position = pos
	b.size = size
	b.color = color
	b.collide = collide
	b.lod = lod
	b.rotation = rot
	b.metallic = metallic
	b.roughness = roughness
	parent.add_child(b)
	return b


static func _cyl(parent: Node3D, pos: Vector3, diameter: float, height: float,
		color: Color, collide := false, metallic := 0.0, roughness := 0.7) -> Block:
	var b := _block(parent, pos, Vector3(diameter, height, diameter), color, collide,
		Block.Lod.AUTO, Vector3.ZERO, metallic, roughness)
	b.shape = Block.Shape.CYLINDER
	return b


static func _ground(map: GameMap, root: Node3D) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(EXTENT * 2.0 + 4.0, EXTENT * 2.0 + 4.0)
	plane.mesh = mesh
	plane.position.y = -0.02
	var core := map.get_node_or_null("Ground") as MeshInstance3D
	if core and core.material_override:
		plane.material_override = core.material_override
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plane)
	var col := _block(root, Vector3(0, -0.55, 0),
		Vector3(EXTENT * 2.0 + 4.0, 1.0, EXTENT * 2.0 + 4.0), Color.BLACK, true)
	col.visible = false


## Cuts a wide gate in the four core-map walls where the new roads continue,
## keeping the original perimeter look around the rest of the core.
static func _open_core_walls(map: GameMap) -> void:
	var wall := map.geometry.get_node_or_null("Wall")
	if wall == null:
		return
	var gap := 9.0
	for node in wall.get_children():
		var b := node as Block
		if b == null:
			continue
		var along_x := b.size.x >= 60.0
		var along_z := b.size.z >= 60.0
		if not along_x and not along_z:
			# Pillars and caps: remove the ones standing in a gate opening.
			if (absf(b.position.x) < 6.0 and absf(absf(b.position.z) - 40.0) < 2.0) \
					or (absf(b.position.z) < 6.0 and absf(absf(b.position.x) - 40.0) < 2.0):
				b.visible = false
				b.collide = false
			continue
		var length := b.size.x if along_x else b.size.z
		var half := (length - gap) * 0.5
		var offset := gap * 0.5 + half * 0.5
		for s in [1.0, -1.0]:
			var seg := Block.new()
			seg.size = b.size
			seg.color = b.color
			seg.metallic = b.metallic
			seg.roughness = b.roughness
			seg.emission = b.emission
			seg.lod = b.lod
			seg.visible = b.visible
			seg.collide = b.collide
			seg.transform = b.transform
			if along_x:
				seg.size = Vector3(half, b.size.y, b.size.z)
				seg.position = b.position + Vector3(offset * s, 0, 0)
			else:
				seg.size = Vector3(b.size.x, b.size.y, half)
				seg.position = b.position + Vector3(0, 0, offset * s)
			wall.add_child(seg)
		b.visible = false
		b.collide = false


static func _gate_posts(root: Node3D, pal: Dictionary) -> void:
	var c: Color = pal["berm"]
	var cap: Color = pal["trim"]
	for axis_x in [true, false]:
		for side in [1.0, -1.0]:
			for along in [1.0, -1.0]:
				var pos := Vector3(5.2 * along, 2.3, 40.0 * side) if axis_x else Vector3(40.0 * side, 2.3, 5.2 * along)
				var size := Vector3(1.1, 4.6, 1.1) if axis_x else Vector3(1.1, 4.6, 1.1)
				_block(root, pos, size, c)
				var cap_pos := pos + Vector3(0, 2.45, 0)
				_block(root, cap_pos, Vector3(1.5, 0.3, 1.5), cap)


static func _boundary(root: Node3D, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var base: Color = pal["berm"]
	var side := EXTENT + 0.6
	var t := -EXTENT
	while t < EXTENT:
		var h := rng.randf_range(2.3, 3.4)
		var c := _shade(base, rng.randf_range(0.9, 1.1))
		_block(root, Vector3(t + 4.0, h * 0.5, -side), Vector3(8.2, h, 0.8), c)
		_block(root, Vector3(t + 4.0, h * 0.5, side), Vector3(8.2, h, 0.8), c)
		_block(root, Vector3(-side, h * 0.5, t + 4.0), Vector3(0.8, h, 8.2), c)
		_block(root, Vector3(side, h * 0.5, t + 4.0), Vector3(0.8, h, 8.2), c)
		t += 8.0


static func _roads(root: Node3D, rng: RandomNumberGenerator, pal: Dictionary, theme: String) -> void:
	var road: Color = pal["road"]
	var walk: Color = pal["walk"]
	var line: Color = pal["line"]
	var end := EXTENT - 1.0
	# Four arms leaving the core map, so the core street continues naturally.
	_block(root, Vector3(0, 0.015, (CORE + end) * 0.5), Vector3(6.0, 0.03, end - CORE), road, false, Block.Lod.ALWAYS)
	_block(root, Vector3(0, 0.015, -(CORE + end) * 0.5), Vector3(6.0, 0.03, end - CORE), road, false, Block.Lod.ALWAYS)
	_block(root, Vector3((CORE + end) * 0.5, 0.015, 0), Vector3(end - CORE, 0.03, 6.0), road, false, Block.Lod.ALWAYS)
	_block(root, Vector3(-(CORE + end) * 0.5, 0.015, 0), Vector3(end - CORE, 0.03, 6.0), road, false, Block.Lod.ALWAYS)
	# Ring road around the whole district.
	_block(root, Vector3(0, 0.017, -RING), Vector3(end * 2.0, 0.03, 5.0), road, false, Block.Lod.ALWAYS)
	_block(root, Vector3(0, 0.017, RING), Vector3(end * 2.0, 0.03, 5.0), road, false, Block.Lod.ALWAYS)
	_block(root, Vector3(-RING, 0.018, 0), Vector3(5.0, 0.03, end * 2.0), road, false, Block.Lod.ALWAYS)
	_block(root, Vector3(RING, 0.018, 0), Vector3(5.0, 0.03, end * 2.0), road, false, Block.Lod.ALWAYS)
	# Sidewalks along the arms.
	for s in [1.0, -1.0]:
		_block(root, Vector3(3.7 * s, 0.04, (CORE + RING) * 0.5), Vector3(1.3, 0.06, RING - CORE), walk, false)
		_block(root, Vector3(3.7 * s, 0.04, -(CORE + RING) * 0.5), Vector3(1.3, 0.06, RING - CORE), walk, false)
		_block(root, Vector3((CORE + RING) * 0.5, 0.04, 3.7 * s), Vector3(RING - CORE, 0.06, 1.3), walk, false)
		_block(root, Vector3(-(CORE + RING) * 0.5, 0.04, 3.7 * s), Vector3(RING - CORE, 0.06, 1.3), walk, false)
	# Curbs.
	for s in [1.0, -1.0]:
		for a in [1.0, -1.0]:
			_block(root, Vector3(3.15 * s, 0.09, a * (CORE + RING) * 0.5), Vector3(0.16, 0.16, RING - CORE), walk, false)
			_block(root, Vector3(a * (CORE + RING) * 0.5, 0.09, 3.15 * s), Vector3(RING - CORE, 0.16, 0.16), walk, false)
		_block(root, Vector3(s * (RING - 2.7), 0.09, 0), Vector3(0.16, 0.16, RING * 2.0), walk, false)
		_block(root, Vector3(s * (RING + 2.7), 0.09, 0), Vector3(0.16, 0.16, RING * 2.0), walk, false)
		_block(root, Vector3(0, 0.09, s * (RING - 2.7)), Vector3(RING * 2.0, 0.16, 0.16), walk, false)
		_block(root, Vector3(0, 0.09, s * (RING + 2.7)), Vector3(RING * 2.0, 0.16, 0.16), walk, false)
	# Dashed centre lines on the arms.
	var t := CORE + 4.0
	while t < RING - 2.0:
		_block(root, Vector3(0, 0.05, t), Vector3(0.16, 0.02, 2.6), line, false, Block.Lod.DETAIL)
		_block(root, Vector3(0, 0.05, -t), Vector3(0.16, 0.02, 2.6), line, false, Block.Lod.DETAIL)
		_block(root, Vector3(t, 0.05, 0), Vector3(2.6, 0.02, 0.16), line, false, Block.Lod.DETAIL)
		_block(root, Vector3(-t, 0.05, 0), Vector3(2.6, 0.02, 0.16), line, false, Block.Lod.DETAIL)
		t += 7.0
	# Crossings where the arms leave the core and meet the ring.
	for k in 5:
		var off := -2.0 + k * 1.0
		for e in [CORE, -CORE]:
			_block(root, Vector3(off, 0.055, e), Vector3(0.55, 0.02, 2.4), line, false, Block.Lod.DETAIL)
			_block(root, Vector3(e, 0.055, off), Vector3(2.4, 0.02, 0.55), line, false, Block.Lod.DETAIL)
	# Manholes and patches.
	for i in 12:
		var mx := rng.randf_range(-RING + 4.0, RING - 4.0)
		var mz := 0.0
		if i % 2 == 0:
			mx = rng.randf_range(-2.0, 2.0)
			mz = rng.randf_range(CORE + 3.0, RING - 3.0) * (1.0 if i % 4 == 0 else -1.0)
		else:
			mz = rng.randf_range(-2.0, 2.0)
			mx = rng.randf_range(CORE + 3.0, RING - 3.0) * (1.0 if i % 4 == 1 else -1.0)
		_cyl(root, Vector3(mx, 0.045, mz), 0.8, 0.02, Color(0.12, 0.13, 0.14), false, 0.4, 0.5)
	if theme == "harbor" or theme == "arctic":
		for i in 8:
			var ox := rng.randf_range(-RING + 8.0, RING - 8.0)
			var oz := rng.randf_range(-2.5, 2.5)
			if absf(ox) < CORE:
				continue
			_block(root, Vector3(ox, 0.035, oz), Vector3(rng.randf_range(1.0, 2.6), 0.01, rng.randf_range(0.8, 2.0)),
				Color(0.08, 0.09, 0.1), false, Block.Lod.DETAIL)
	if theme != "desert":
		for i in 14:
			var px := rng.randf_range(-RING + 5.0, RING - 5.0)
			var pz := rng.randf_range(-RING + 5.0, RING - 5.0)
			if absf(px) < 4.0 or absf(pz) < 4.0:
				continue
			_block(root, Vector3(px, 0.022, pz), Vector3(rng.randf_range(1.5, 3.0), 0.01, rng.randf_range(1.5, 3.5)),
				_shade(road, 0.82), false, Block.Lod.DETAIL)


static func _buildings(root: Node3D, rng: RandomNumberGenerator, pal: Dictionary, theme: String) -> Array[Dictionary]:
	var lots: Array[Dictionary] = []
	var slots: Array = [
		Vector2(49, 49), Vector2(49, -49), Vector2(-49, 49), Vector2(-49, -49),
		Vector2(61, 49), Vector2(61, -49), Vector2(-61, 49), Vector2(-61, -49),
		Vector2(49, 61), Vector2(49, -61), Vector2(-49, 61), Vector2(-49, -61),
	]
	for slot in slots:
		lots.append(_building(root, rng, pal, theme, slot.x, slot.y))
	return lots


## Degrees of rotation so the front door faces the nearest road.
static func _face_road(px: float, pz: float) -> float:
	var options := [
		[absf(px), -90.0 if px > 0.0 else 90.0],       # road at x = 0
		[absf(pz), 180.0 if pz > 0.0 else 0.0],        # road at z = 0
		[absf(RING - absf(px)), 90.0 if px > 0.0 else -90.0],  # ring on x
		[absf(RING - absf(pz)), 180.0 if pz < 0.0 else 0.0],   # ring on z
	]
	var best: Array = options[0]
	for o in options:
		if o[0] < best[0]:
			best = o
	return float(best[1])


static func _building(root: Node3D, rng: RandomNumberGenerator, pal: Dictionary,
		theme: String, px: float, pz: float) -> Dictionary:
	var w := rng.randf_range(8.6, 10.2)
	var d := rng.randf_range(8.4, 9.8)
	var tall := rng.randf() < 0.42
	var h := rng.randf_range(5.3, 6.4) if tall else rng.randf_range(3.4, 4.2)
	var yaw := _face_road(px, pz)
	var lot := Node3D.new()
	lot.name = "Lot"
	lot.position = Vector3(px, 0.0, pz)
	lot.rotation.y = deg_to_rad(yaw)
	root.add_child(lot)

	var walls: Array = pal["walls"]
	var wall: Color = _shade(walls[rng.randi() % walls.size()], rng.randf_range(0.94, 1.06))
	var trim: Color = pal["trim"]
	var roof: Color = pal["roof"]
	var glass: Color = pal["glass"]
	var accents: Array = pal["accent"]
	var accent: Color = accents[rng.randi() % accents.size()]

	# Walls. The front (+Z) wall has a door opening.
	var t := WALL
	_block(lot, Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0), Vector3(t, h, d), wall)
	_block(lot, Vector3(w * 0.5 - t * 0.5, h * 0.5, 0), Vector3(t, h, d), wall)
	_block(lot, Vector3(0, h * 0.5, -d * 0.5 + t * 0.5), Vector3(w - t * 2.0, h, t), wall)
	var side := (w - DOOR_W) * 0.5
	_block(lot, Vector3(-(DOOR_W * 0.5 + side * 0.5), h * 0.5, d * 0.5 - t * 0.5), Vector3(side, h, t), wall)
	_block(lot, Vector3(DOOR_W * 0.5 + side * 0.5, h * 0.5, d * 0.5 - t * 0.5), Vector3(side, h, t), wall)
	_block(lot, Vector3(0, DOOR_H + (h - DOOR_H) * 0.5, d * 0.5 - t * 0.5), Vector3(DOOR_W, h - DOOR_H, t), wall)
	# Roof and parapet.
	_block(lot, Vector3(0, h + 0.15, 0), Vector3(w + 0.7, 0.3, d + 0.7), roof)
	for s in [1.0, -1.0]:
		_block(lot, Vector3(0, h + 0.52, (d * 0.5 + 0.25) * s), Vector3(w + 0.7, 0.45, 0.2), trim)
		_block(lot, Vector3((w * 0.5 + 0.25) * s, h + 0.52, 0), Vector3(0.2, 0.45, d + 0.7), trim)
	if theme == "arctic":
		_block(lot, Vector3(0, h + 0.34, 0), Vector3(w + 0.75, 0.08, d + 0.75), Color(0.9, 0.93, 0.96), false, Block.Lod.DETAIL)

	# Door frame, open door leaf and awning.
	_block(lot, Vector3(-DOOR_W * 0.5 - 0.08, DOOR_H * 0.5, d * 0.5 + 0.02), Vector3(0.16, DOOR_H + 0.16, 0.14), trim)
	_block(lot, Vector3(DOOR_W * 0.5 + 0.08, DOOR_H * 0.5, d * 0.5 + 0.02), Vector3(0.16, DOOR_H + 0.16, 0.14), trim)
	_block(lot, Vector3(0, DOOR_H + 0.08, d * 0.5 + 0.02), Vector3(DOOR_W + 0.32, 0.16, 0.14), trim)
	_block(lot, Vector3(-DOOR_W * 0.5 - 0.04, 1.05, d * 0.5 - 0.5), Vector3(0.06, 2.1, 1.0), _shade(wall, 0.8), false)
	var awning := _block(lot, Vector3(0, 2.74, d * 0.5 + 0.55), Vector3(2.6, 0.07, 1.05),
		_shade(accent, 0.95), false)
	awning.rotation.x = deg_to_rad(-7.0)
	for s in [1.0, -1.0]:
		_block(lot, Vector3(1.15 * s, 2.42, d * 0.5 + 0.98), Vector3(0.05, 0.62, 0.05), _shade(accent, 0.6), false)
	_block(lot, Vector3(0, 3.14, d * 0.5 + 0.08), Vector3(1.9, 0.55, 0.1), _shade(accent, 1.15), false)

	# Windows (front, back and sides) with frames and sills.
	var rows := [1.65, 4.15] if tall else [1.65]
	for y in rows:
		for s in [1.0, -1.0]:
			var wx: float = w * 0.31 * s
			_window(lot, Vector3(wx, y, d * 0.5 + 0.05), glass, trim)
			_window(lot, Vector3(wx, y, -d * 0.5 - 0.05), glass, trim)
			for sz in [1.0, -1.0]:
				_window_side(lot, Vector3((w * 0.5 + 0.05) * s, y, d * 0.25 * sz), glass, trim)
		if theme != "harbor" and theme != "arctic":
			for s in [1.0, -1.0]:
				_shutters(lot, Vector3(w * 0.31 * s, y, d * 0.5 + 0.09), accent)
		_window(lot, Vector3(0, y, -d * 0.5 - 0.05), glass, trim)
	# Flower boxes under the front windows.
	if theme != "harbor" and theme != "arctic":
		for s in [1.0, -1.0]:
			_block(lot, Vector3(w * 0.31 * s, 0.88, d * 0.5 + 0.22), Vector3(1.5, 0.22, 0.3),
				_shade(accent, 0.9), false, Block.Lod.DETAIL)
			_block(lot, Vector3(w * 0.31 * s, 1.05, d * 0.5 + 0.22), Vector3(1.35, 0.16, 0.24),
				Color(0.24, 0.42, 0.22), false, Block.Lod.DETAIL)

	# Corner trims, base skirt and roofline fascia break the flat box look.
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			_block(lot, Vector3((w * 0.5 - 0.09) * sx, h * 0.5, (d * 0.5 - 0.09) * sz),
				Vector3(0.3, h + 0.05, 0.3), _shade(trim, 0.92), false)
			_block(lot, Vector3((w * 0.5 + 0.01) * sx, 0.35, (d * 0.5 + 0.01) * sz),
				Vector3(0.16, 0.7, 0.16), _shade(wall, 0.72), false, Block.Lod.DETAIL)
	for s in [1.0, -1.0]:
		_block(lot, Vector3(0, 0.38, (d * 0.5 + 0.02) * s), Vector3(w + 0.1, 0.7, 0.09),
			_shade(wall, 0.86), false, Block.Lod.DETAIL)
		_block(lot, Vector3(0, h - 0.12, (d * 0.5 + 0.05) * s), Vector3(w + 0.75, 0.2, 0.12), trim, false)
		_block(lot, Vector3((w * 0.5 + 0.02) * s, 0.38, 0), Vector3(0.09, 0.7, d + 0.1),
			_shade(wall, 0.86), false, Block.Lod.DETAIL)
		_block(lot, Vector3((w * 0.5 + 0.05) * s, h - 0.12, 0), Vector3(0.12, 0.2, d + 0.75), trim, false)
	# Gutter and downpipe.
	var gutter := _cyl(lot, Vector3(0, h + 0.02, d * 0.5 + 0.16), 0.14, w + 0.6, _shade(trim, 0.7), false, 0.4, 0.5)
	gutter.rotation.z = deg_to_rad(90.0)
	_cyl(lot, Vector3(w * 0.5 - 0.16, h * 0.5, d * 0.5 + 0.12), 0.1, h, _shade(trim, 0.7), false, 0.4, 0.5)
	# Porch step, two lamps and a dirt path to the door.
	_block(lot, Vector3(0, 0.07, d * 0.5 + 0.5), Vector3(2.4, 0.14, 1.0), trim, false)
	_block(lot, Vector3(0, 0.03, d * 0.5 + 2.6), Vector3(1.5, 0.02, 3.4), _shade(trim, 0.72), false, Block.Lod.DETAIL)
	for s in [1.0, -1.0]:
		_block(lot, Vector3((-DOOR_W * 0.5 - 0.34) * s, 2.12, d * 0.5 + 0.08), Vector3(0.14, 0.22, 0.14),
			Color(1.0, 0.92, 0.7), false, Block.Lod.DETAIL, Vector3.ZERO, 0.0, 0.4).emission = 0.9
	# Grime at the wall base.
	for i in rng.randi_range(3, 6):
		var gx := rng.randf_range(-w * 0.45, w * 0.45)
		_block(lot, Vector3(gx, rng.randf_range(0.4, 1.0), d * 0.5 + 0.055),
			Vector3(rng.randf_range(0.4, 1.4), rng.randf_range(0.5, 1.4), 0.02), _shade(wall, 0.82),
			false, Block.Lod.DETAIL)

	# Rooftop props.
	var roof_y := h + 0.3
	match rng.randi() % 4:
		0:
			_cyl(lot, Vector3(w * 0.22, roof_y + 0.8, -d * 0.22), 1.2, 1.6, _shade(trim, 0.9), true, 0.3, 0.6)
			for sx in [1.0, -1.0]:
				for sz in [1.0, -1.0]:
					_block(lot, Vector3(w * 0.22 + 0.38 * sx, roof_y + 0.2, -d * 0.22 + 0.38 * sz),
						Vector3(0.1, 0.4, 0.1), Color(0.3, 0.3, 0.32), false)
		1:
			_block(lot, Vector3(-w * 0.2, roof_y + 0.32, d * 0.18), Vector3(1.2, 0.64, 0.95), Color(0.55, 0.57, 0.6), true, Block.Lod.AUTO, Vector3.ZERO, 0.4, 0.5)
			_block(lot, Vector3(-w * 0.2, roof_y + 0.66, d * 0.18), Vector3(0.9, 0.06, 0.7), Color(0.3, 0.32, 0.34), false)
		2:
			var pipe := _cyl(lot, Vector3(-w * 0.3, roof_y + 1.5, -d * 0.25), 0.06, 3.0, Color(0.35, 0.36, 0.38), false, 0.4, 0.5)
			pipe.rotation.x = deg_to_rad(rng.randf_range(-3.0, 3.0))
			_block(lot, Vector3(-w * 0.3, roof_y + 2.5, -d * 0.25), Vector3(1.4, 0.06, 0.06), Color(0.35, 0.36, 0.38), false)
		_:
			_block(lot, Vector3(w * 0.24, roof_y + 1.0, d * 0.22), Vector3(0.55, 2.0, 0.55), _shade(roof, 0.85), true)

	# Interior floor so the room does not show raw terrain.
	var floor_color := Color(0.42, 0.33, 0.24)
	if theme == "harbor" or theme == "arctic":
		floor_color = Color(0.42, 0.44, 0.46)
	elif theme == "desert":
		floor_color = Color(0.6, 0.52, 0.41)
	_block(lot, Vector3(0, 0.015, 0), Vector3(w - 0.55, 0.03, d - 0.55), floor_color, false, Block.Lod.ALWAYS)

	# A few interior details.
	for i in rng.randi_range(1, 3):
		var ix := rng.randf_range(-w * 0.3, w * 0.3)
		var iz := rng.randf_range(-d * 0.3, 0.0)
		var scale := rng.randf_range(0.7, 1.1)
		_block(lot, Vector3(ix, 0.5 * scale, iz), Vector3(0.8 * scale, 1.0 * scale, 0.8 * scale),
			_shade(accent, rng.randf_range(0.7, 0.95)), true)
	_block(lot, Vector3(0, h - 0.15, 0), Vector3(1.1, 0.18, 1.1), Color(0.95, 0.92, 0.8), false)

	# Crates or barrels against the front wall, on the other side of the door.
	_courtyard(lot, rng, theme, d)

	# A bench or a dumpster by the entrance.
	var front := d * 0.5 + 2.1
	if rng.randf() < 0.55:
		var bench := _prop("res://scenes/props/bench.tscn").instantiate()
		bench.position = Vector3(rng.randf_range(2.2, 3.2) * (1.0 if rng.randf() < 0.5 else -1.0), 0.0, front)
		bench.rotation.y = rng.randf_range(-0.4, 0.4)
		lot.add_child(bench)
	else:
		var bin := _prop("res://scenes/props/dumpster.tscn").instantiate()
		bin.position = Vector3(rng.randf_range(2.2, 3.2) * (1.0 if rng.randf() < 0.5 else -1.0), 0.0, front + 0.6)
		bin.rotation.y = rng.randf_range(-0.3, 0.3)
		lot.add_child(bin)

	return {"pos": Vector2(px, pz), "radius": maxf(w, d) * 0.75 + 2.4}


static func _window(lot: Node3D, pos: Vector3, glass: Color, trim: Color) -> void:
	var front := pos.z > 0.0
	var z := pos.z + (0.015 if front else -0.015)
	_block(lot, Vector3(pos.x, pos.y, z), Vector3(1.5, 1.5, 0.05), trim, false, Block.Lod.DETAIL)
	_block(lot, Vector3(pos.x, pos.y, z + (0.035 if front else -0.035)), Vector3(1.2, 1.25, 0.06), glass, false, Block.Lod.DETAIL, Vector3.ZERO, 0.2, 0.25)
	_block(lot, Vector3(pos.x, pos.y, z + (0.07 if front else -0.07)), Vector3(0.06, 1.2, 0.03), _shade(trim, 0.9), false, Block.Lod.DETAIL)
	_block(lot, Vector3(pos.x, pos.y, z + (0.07 if front else -0.07)), Vector3(1.15, 0.06, 0.03), _shade(trim, 0.9), false, Block.Lod.DETAIL)
	_block(lot, Vector3(pos.x, pos.y - 0.82, z), Vector3(1.6, 0.1, 0.22), _shade(trim, 0.85), false, Block.Lod.DETAIL)
	if pos.y > 2.5:
		_block(lot, Vector3(pos.x, pos.y + 0.82, z), Vector3(1.5, 0.08, 0.2), trim, false, Block.Lod.DETAIL)


static func _shutters(lot: Node3D, pos: Vector3, accent: Color) -> void:
	for s in [1.0, -1.0]:
		_block(lot, Vector3(pos.x + 0.86 * s, pos.y, pos.z), Vector3(0.34, 1.35, 0.06), accent,
			false, Block.Lod.DETAIL)


static func _window_side(lot: Node3D, pos: Vector3, glass: Color, trim: Color) -> void:
	var right := pos.x > 0.0
	var x := pos.x + (0.015 if right else -0.015)
	_block(lot, Vector3(x, pos.y, pos.z), Vector3(0.05, 1.5, 1.5), trim, false, Block.Lod.DETAIL)
	_block(lot, Vector3(x + (0.035 if right else -0.035), pos.y, pos.z), Vector3(0.06, 1.25, 1.2), glass, false, Block.Lod.DETAIL, Vector3.ZERO, 0.2, 0.25)
	_block(lot, Vector3(x + (0.07 if right else -0.07), pos.y, pos.z), Vector3(0.03, 1.2, 0.06), _shade(trim, 0.9), false, Block.Lod.DETAIL)
	_block(lot, Vector3(x + (0.07 if right else -0.07), pos.y, pos.z), Vector3(0.03, 0.06, 1.15), _shade(trim, 0.9), false, Block.Lod.DETAIL)
	_block(lot, Vector3(x, pos.y - 0.82, pos.z), Vector3(0.22, 0.1, 1.6), _shade(trim, 0.85), false, Block.Lod.DETAIL)


static func _courtyard(lot: Node3D, rng: RandomNumberGenerator, theme: String, d: float) -> void:
	var options := {
		"neighborhood": ["res://scenes/props/crate_stack.tscn", "res://scenes/props/barrels.tscn", "res://scenes/props/pallet.tscn"],
		"harbor": ["res://scenes/props/pallet.tscn", "res://scenes/props/barrels.tscn", "res://scenes/props/crate_stack.tscn"],
		"desert": ["res://scenes/props/crate_stack.tscn", "res://scenes/props/barrels.tscn", "res://scenes/props/sandbags.tscn"],
		"arctic": ["res://scenes/props/crate_stack.tscn", "res://scenes/props/barrels.tscn", "res://scenes/props/sandbags.tscn"],
	}
	var list: Array = options.get(theme, options["neighborhood"])
	for i in rng.randi_range(1, 2):
		var path: String = list[rng.randi() % list.size()]
		var node := _prop(path).instantiate()
		node.position = Vector3(rng.randf_range(2.4, 3.6) * (1.0 if i == 0 else -1.0), 0.0,
			d * 0.5 + rng.randf_range(1.2, 2.2))
		node.rotation.y = rng.randf_range(0.0, TAU)
		lot.add_child(node)


static func _towers(root: Node3D, pal: Dictionary) -> void:
	var metal: Color = pal["trim"]
	var deck: Color = pal["roof"]
	for spot in [Vector2(55, 30), Vector2(-55, 30), Vector2(55, -30), Vector2(-55, -30)]:
		var tower := Node3D.new()
		tower.position = Vector3(spot.x, 0, spot.y)
		tower.rotation.y = 0.0 if spot.y > 0.0 else PI
		root.add_child(tower)
		var h := 4.6
		for sx in [1.0, -1.0]:
			for sz in [1.0, -1.0]:
				_cyl(tower, Vector3(2.2 * sx, h * 0.5, 2.2 * sz), 0.18, h, _shade(metal, 0.8), true, 0.6, 0.4)
		_block(tower, Vector3(0, h + 0.12, 0), Vector3(5.2, 0.24, 5.2), deck, true, Block.Lod.AUTO, Vector3.ZERO, 0.4, 0.55)
		for s in [1.0, -1.0]:
			_block(tower, Vector3(0, h + 0.75, 2.52 * s), Vector3(5.2, 1.0, 0.08), metal, false)
			_block(tower, Vector3(2.52 * s, h + 0.75, 0), Vector3(0.08, 1.0, 5.2), metal, false)
		# Ramp up, on the -Z side.
		var run := 9.0
		var slope := atan2(h, run)
		var length := sqrt(run * run + h * h)
		var ramp := _block(tower, Vector3(0, h * 0.5, -2.6 - run * 0.5), Vector3(1.55, 0.22, length),
			_shade(deck, 0.9), true, Block.Lod.AUTO, Vector3(-slope, 0, 0), 0.35, 0.6)
		ramp.set_meta("no_split", true)
		for s in [1.0, -1.0]:
			_block(tower, Vector3(0.84 * s, h * 0.5 + 0.55, -2.6 - run * 0.5), Vector3(0.06, 0.9, length),
				metal, false, Block.Lod.DETAIL, Vector3(-slope, 0, 0))


static func _street_lamps(root: Node3D, pal: Dictionary, theme: String) -> void:
	var path := "res://scenes/props/lamp_post.tscn"
	var scene := _prop(path)
	var z := -RING + 8.0
	while z <= RING - 8.0:
		if absf(z) > CORE + 3.0:
			for s in [1.0, -1.0]:
				var lamp := scene.instantiate()
				lamp.position = Vector3(5.6 * s, 0, z)
				lamp.rotation.y = deg_to_rad(-90.0 if s > 0.0 else 90.0)
				root.add_child(lamp)
		z += 14.0
	var x := -RING + 8.0
	while x <= RING - 8.0:
		if absf(x) > CORE + 3.0:
			for s in [1.0, -1.0]:
				var lamp2 := scene.instantiate()
				lamp2.position = Vector3(x, 0, 5.6 * s)
				lamp2.rotation.y = deg_to_rad(180.0 if s > 0.0 else 0.0)
				root.add_child(lamp2)
		x += 14.0


static func _power_line(root: Node3D, pal: Dictionary) -> void:
	var wood := Color(0.32, 0.25, 0.19)
	var z := -RING + 10.0
	var prev := 999.0
	while z <= RING - 10.0:
		_cyl(root, Vector3(7.4, 3.2, z), 0.22, 6.4, wood, true, 0.0, 0.9)
		_block(root, Vector3(7.4, 5.85, z), Vector3(1.9, 0.12, 0.12), wood, false, Block.Lod.DETAIL)
		for s in [1.0, -1.0]:
			_block(root, Vector3(7.4 + 0.7 * s, 5.78, z), Vector3(0.08, 0.2, 0.08), Color(0.2, 0.2, 0.2), false, Block.Lod.DETAIL)
		if prev < 500.0:
			for s in [1.0, -1.0]:
				_block(root, Vector3(7.4 + 0.7 * s, 5.72, (z + prev) * 0.5), Vector3(0.035, 0.035, z - prev),
					Color(0.12, 0.12, 0.13), false, Block.Lod.DETAIL)
		prev = z
		z += 18.0


static func _scatter(root: Node3D, rng: RandomNumberGenerator, theme: String, lots: Array[Dictionary]) -> void:
	var paths: Array = THEME_PROPS.get(theme, THEME_PROPS["neighborhood"])
	var placed: Array[Dictionary] = []
	for lot in lots:
		placed.append(lot)
	for spot in [Vector2(55, 30), Vector2(-55, 30), Vector2(55, -30), Vector2(-55, -30)]:
		placed.append({"pos": spot, "radius": 5.0})
	var count := 46
	for i in count:
		var path: String = paths[rng.randi() % paths.size()]
		var radius: float = PROP_RADIUS.get(path, 2.0)
		var pos := Vector2.ZERO
		var ok := false
		for attempt in 18:
			pos = Vector2(rng.randf_range(-RING + 4.0, RING - 4.0), rng.randf_range(-RING + 4.0, RING - 4.0))
			if absf(pos.x) < 5.5 or absf(pos.y) < 5.5:
				continue
			if absf(absf(pos.x) - RING) < 4.5 or absf(absf(pos.y) - RING) < 4.5:
				continue
			if absf(pos.x) < CORE + 1.0 and absf(pos.y) < CORE + 1.0:
				continue
			var free := true
			for other in placed:
				var opos: Vector2 = other["pos"]
				var orad: float = other["radius"]
				if pos.distance_to(opos) < radius + orad + 1.6:
					free = false
					break
			if free:
				ok = true
				break
		if not ok:
			continue
		var node := _prop(path).instantiate()
		node.position = Vector3(pos.x, 0.0, pos.y)
		node.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(node)
		placed.append({"pos": pos, "radius": radius})


static func _markers(map: GameMap) -> void:
	var spawns := map.get_node_or_null("Spawns")
	if spawns:
		var pts := [
			Vector3(0, 0.2, -66), Vector3(0, 0.2, 66), Vector3(-66, 0.2, 0), Vector3(66, 0.2, 0),
			Vector3(0, 0.2, -47), Vector3(0, 0.2, 47), Vector3(-47, 0.2, 0), Vector3(47, 0.2, 0),
		]
		for i in pts.size():
			var m := Marker3D.new()
			m.name = "OuterSpawn%d" % i
			m.position = pts[i]
			spawns.add_child(m)
	var waypoints := map.get_node_or_null("Waypoints")
	if waypoints:
		var pts := [
			Vector3(0, 0.2, -70), Vector3(0, 0.2, 70), Vector3(-70, 0.2, 0), Vector3(70, 0.2, 0),
			Vector3(-56, 0.2, -56), Vector3(56, 0.2, 56), Vector3(-56, 0.2, 56), Vector3(56, 0.2, -56),
			Vector3(64, 0.2, 28), Vector3(-64, 0.2, -28), Vector3(28, 0.2, 64), Vector3(-28, 0.2, -64),
			Vector3(49, 0.2, 42), Vector3(-49, 0.2, -42), Vector3(61, 0.2, -42), Vector3(-61, 0.2, 42),
		]
		for i in pts.size():
			var m := Marker3D.new()
			m.name = "OuterWaypoint%d" % i
			m.position = pts[i]
			waypoints.add_child(m)


static func _prop(path: String) -> PackedScene:
	if not _prop_cache.has(path):
		_prop_cache[path] = load(path)
	return _prop_cache[path]
