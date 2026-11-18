class_name Holiday
## Christmas edition (1.1.0): snow and map decorations. (The Santa hat is a
## Locker item, see Cosmetics, worn by default in this edition.)
##
## Everything is made of Block nodes, like the rest of the maps, and added
## BEFORE the map is baked: the decorations are merged into the same chunk
## meshes and collision as the map, so they cost almost no performance.
##
## The placement is random but seeded per map, and depends only on the map's
## own blocks, so every computer in a match builds exactly the same
## decorations (same collision for everyone).

## Master switch of the Christmas edition.
const ENABLED := true
## Game logo with a Santa hat (splash, loading screen, window icon).
const LOGO_PATH := "res://assets/icons/icon_holiday.svg"
## Santa hat drawn over the "O" of the lobby's OPENSHOOTER wordmark.
const HAT_PATH := "res://assets/ui/santa_hat.svg"


## Puts the Christmas logo on a logo TextureRect (an AnimatedIcon in the
## splash and loading screens). The hat must stay upright, so a spinning logo
## stops spinning.
static func dress_logo(logo: TextureRect) -> void:
	if not ENABLED:
		return
	logo.texture = load(LOGO_PATH)
	if logo is AnimatedIcon:
		(logo as AnimatedIcon).spin_speed = 0.0

## Maps without snow (ground or snowfall). Names are the map scene files.
const NO_SNOW := ["desert"]
## Snow-covered ground, shared with the Arctic Base map.
const SNOW_GROUND := preload("res://resources/materials/arctic.tres")
## Color of snow-covered blocks (lawns).
const SNOW_COLOR := Color(0.9, 0.93, 0.97)

## Map area that can be decorated (the outer district reaches ±76 m).
const AREA := 74.0
## Size of one cell of the occupancy grid (meters).
const CELL := 1.0
## Nothing is placed this close to a spawn point or a bot waypoint.
const KEEP_CLEAR := 3.5
## Free ground needed around each decoration, on top of its own radius.
const MARGIN := 0.6

const BIG_TREES := 1
const TREES := 8
const SNOWMEN := 10
const GIFT_PILES := 16
## Upper limit of string-light bulbs per map.
const MAX_BULBS := 480

const RED := Color(0.78, 0.09, 0.11)
const GREEN := Color(0.1, 0.42, 0.2)
const DARK_GREEN := Color(0.06, 0.3, 0.14)
const WHITE := Color(0.95, 0.96, 0.98)
const GOLD := Color(1.0, 0.78, 0.2)
const COAL := Color(0.07, 0.07, 0.08)
const CARROT := Color(0.96, 0.45, 0.08)
const TRUNK := Color(0.36, 0.22, 0.12)
const TREE_TIERS := 6
const ORNAMENT_COLORS := [Color(0.85, 0.1, 0.12), Color(1.0, 0.75, 0.1), Color(0.2, 0.45, 0.95), Color(0.95, 0.95, 0.98)]
## Glow of the string-light bulbs. Higher values wash the colors out to white.
const BULB_GLOW := 0.9
const BULB_COLORS := [Color(1.0, 0.2, 0.2), Color(0.25, 1.0, 0.35), Color(1.0, 0.8, 0.2), Color(0.3, 0.55, 1.0)]
const GIFT_COLORS := [Color(0.8, 0.12, 0.14), Color(0.15, 0.45, 0.85), Color(0.95, 0.75, 0.15), Color(0.2, 0.6, 0.3), Color(0.6, 0.25, 0.75)]


# ============================================================================
# Snow
# ============================================================================

## Covers the ground with snow and makes it snow (except on NO_SNOW maps).
## Call BEFORE MapExpansion.build: the outer district copies the ground
## material of the core map.
static func apply_snow(map: GameMap) -> void:
	if not ENABLED or theme_of(map) in NO_SNOW:
		return
	var ground := map.get_node_or_null("Ground") as MeshInstance3D
	if ground:
		ground.material_override = SNOW_GROUND
	map.add_child(Snowfall.new())


## Lawns and grass strips (flat green blocks lying on the ground) turn white,
## so the whole ground looks snowed in, not just the bare terrain.
static func _snow_on_grass(found: MapBlocks) -> void:
	for i in found.blocks.size():
		var b: Block = found.blocks[i]
		var box: AABB = found.transforms[i] * AABB(-b.size * 0.5, b.size)
		var on_ground := box.position.y <= 0.05 and box.end.y <= 0.35
		var green := b.color.g > b.color.r * 1.15 and b.color.g > b.color.b * 1.15
		if on_ground and green:
			b.color = SNOW_COLOR


## The map's theme: its scene file name ("neighborhood", "desert", ...).
static func theme_of(map: GameMap) -> String:
	return map.get_scene_file_path().get_file().get_basename()


# ============================================================================
# Map decorations
# ============================================================================

## Decorates `map` (call after MapExpansion.build, before baking).
static func decorate_map(map: GameMap) -> void:
	if not ENABLED:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme_of(map)) + 20261225

	# Every block with its transform relative to the map geometry, found in
	# ONE walk down the tree (cheaper than BlockBaker.relative() per block,
	# which climbs the tree again for every block).
	var found := MapBlocks.new()
	found.walk(map.geometry, Transform3D.IDENTITY, true)

	if not theme_of(map) in NO_SNOW:
		_snow_on_grass(found)

	var grid := Occupancy.new()
	for i in found.blocks.size():
		grid.mark_block(found.blocks[i], found.transforms[i])
	for group in ["Spawns", "Waypoints"]:
		var markers := map.get_node_or_null(group)
		if markers:
			for m in markers.get_children():
				grid.mark_circle(Vector2((m as Node3D).position.x, (m as Node3D).position.z), KEEP_CLEAR)

	var root := Node3D.new()
	root.name = "Christmas"
	map.geometry.add_child(root)

	# The big tree goes on the free spot closest to the middle of the map.
	for i in BIG_TREES:
		var spot := grid.closest_free(Vector2.ZERO, 2.2 + MARGIN, rng)
		if spot.found:
			_big_tree(root, spot.pos, rng)
			grid.mark_circle(spot.pos, 2.2 + MARGIN)
	_scatter(root, grid, rng, TREES, 1.1, _tree)
	_scatter(root, grid, rng, SNOWMEN, 0.7, _snowman)
	_scatter(root, grid, rng, GIFT_PILES, 0.7, _gift_pile)
	_string_lights(root, found, rng)


## Places `count` decorations of radius `radius` with `build(root, pos, rng)`.
## Spots next to walls and buildings are preferred, so the open paths players
## run through stay open.
static func _scatter(root: Node3D, grid: Occupancy, rng: RandomNumberGenerator,
		count: int, radius: float, build: Callable) -> void:
	for i in count:
		var best := Vector2.INF
		for attempt in 40:
			var pos := Vector2(rng.randf_range(-AREA, AREA), rng.randf_range(-AREA, AREA))
			if not grid.is_free(pos, radius + MARGIN):
				continue
			best = pos
			if grid.has_neighbor(pos, radius + MARGIN + 2.5):
				break
		if best == Vector2.INF:
			continue
		build.call(root, best, rng)
		grid.mark_circle(best, radius + MARGIN)


## One Block (thin wrapper so the shapes below read as a list of parts).
static func _part(parent: Node3D, pos: Vector3, size: Vector3, color: Color,
		shape := Block.Shape.BOX, collide := false, emission := 0.0) -> Block:
	var b := Block.new()
	b.shape = shape
	b.position = pos
	b.size = size
	b.color = color
	b.collide = collide
	b.emission = emission
	parent.add_child(b)
	return b


static func _group(root: Node3D, pos: Vector2, rng: RandomNumberGenerator, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	g.position = Vector3(pos.x, 0.0, pos.y)
	g.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(g)
	return g


## Snowman: three snowballs, coal eyes and buttons, a carrot nose, a scarf
## and a top hat. Only the body collides.
static func _snowman(root: Node3D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var g := _group(root, pos, rng, "Snowman")
	_part(g, Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0), WHITE, Block.Shape.SPHERE, true)
	_part(g, Vector3(0, 1.25, 0), Vector3(0.74, 0.74, 0.74), WHITE, Block.Shape.SPHERE, true)
	_part(g, Vector3(0, 1.82, 0), Vector3(0.52, 0.52, 0.52), WHITE, Block.Shape.SPHERE)
	# Face (the snowman looks down -Z, like every character).
	_part(g, Vector3(-0.1, 1.9, -0.24), Vector3(0.06, 0.06, 0.04), COAL)
	_part(g, Vector3(0.1, 1.9, -0.24), Vector3(0.06, 0.06, 0.04), COAL)
	_part(g, Vector3(0, 1.8, -0.33), Vector3(0.07, 0.07, 0.22), CARROT)
	for y in [1.15, 1.32, 1.49]:
		_part(g, Vector3(0, y, -0.36), Vector3(0.07, 0.07, 0.04), COAL)
	# Scarf.
	_part(g, Vector3(0, 1.6, 0), Vector3(0.6, 0.1, 0.6), RED, Block.Shape.CYLINDER)
	_part(g, Vector3(0.18, 1.45, -0.26), Vector3(0.12, 0.3, 0.05), RED)
	# Top hat.
	_part(g, Vector3(0, 2.06, 0), Vector3(0.6, 0.04, 0.6), COAL, Block.Shape.CYLINDER)
	_part(g, Vector3(0, 2.24, 0), Vector3(0.38, 0.34, 0.38), COAL, Block.Shape.CYLINDER)
	_part(g, Vector3(0, 2.12, 0), Vector3(0.4, 0.07, 0.4), RED, Block.Shape.CYLINDER)


## Christmas tree of `height` meters (voxel pine): a trunk, TREE_TIERS
## square tiers that narrow towards the top, colored ornaments on the tier
## corners and a golden star.
static func _tree(root: Node3D, pos: Vector2, rng: RandomNumberGenerator, height := 3.2) -> void:
	var g := _group(root, pos, rng, "ChristmasTree")
	# The tree is designed 3.6 m tall; `s` scales it to `height`.
	var s := height / 3.6
	_part(g, Vector3(0, 0.3 * s, 0), Vector3(0.32, 0.6, 0.32) * s, TRUNK, Block.Shape.BOX, true)
	for t in TREE_TIERS:
		var width := (2.0 - t * 0.3) * s
		var y := (0.65 + t * 0.45) * s
		# Only the bottom tier collides (the trunk area players bump into).
		_part(g, Vector3(0, y, 0), Vector3(width, 0.5 * s, width), DARK_GREEN if t % 2 == 0 else GREEN,
			Block.Shape.BOX, t == 0)
		# Two ornaments on opposite corners, turning a quarter each tier.
		var corner := Vector2(width * 0.5, width * 0.5).rotated(t * PI * 0.5)
		for k in 2:
			var c := corner if k == 0 else -corner
			_part(g, Vector3(c.x, y - 0.2 * s, c.y), Vector3.ONE * 0.16 * s,
				ORNAMENT_COLORS[(t * 2 + k) % ORNAMENT_COLORS.size()], Block.Shape.BOX, false, 0.4)
	var top := (0.65 + TREE_TIERS * 0.45) * s
	_part(g, Vector3(0, top, 0), Vector3(0.36, 0.36, 0.12) * s, GOLD, Block.Shape.BOX, false, 0.8)
	_part(g, Vector3(0, top, 0), Vector3(0.12, 0.36, 0.36) * s, GOLD, Block.Shape.BOX, false, 0.8)


static func _big_tree(root: Node3D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	_tree(root, pos, rng, 6.4)
	# Gifts around the big tree.
	for i in 6:
		var a := TAU * i / 6.0
		_gift(root, pos + Vector2(cos(a), sin(a)) * 2.0, rng)


## Two or three wrapped gifts close together.
static func _gift_pile(root: Node3D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 3)
	for i in count:
		var a := TAU * i / count + rng.randf()
		_gift(root, pos + Vector2(cos(a), sin(a)) * 0.35, rng)


## One gift box with a ribbon cross on top.
static func _gift(root: Node3D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var g := _group(root, pos, rng, "Gift")
	var size := rng.randf_range(0.35, 0.6)
	var box: Color = GIFT_COLORS[rng.randi() % GIFT_COLORS.size()]
	var ribbon := GOLD if box != GIFT_COLORS[2] else RED
	_part(g, Vector3(0, size * 0.5, 0), Vector3(size, size, size), box)
	_part(g, Vector3(0, size * 0.5, 0), Vector3(size + 0.02, size + 0.02, 0.07), ribbon)
	_part(g, Vector3(0, size * 0.5, 0), Vector3(0.07, size + 0.02, size + 0.02), ribbon)
	_part(g, Vector3(0, size + 0.05, 0), Vector3(0.16, 0.1, 0.16), ribbon)


## Colored bulbs along the top edge of buildings and tall walls. Only plain,
## axis-aligned, solid blocks are used; the bulbs glow (emission) and do not
## collide.
static func _string_lights(root: Node3D, found: MapBlocks, rng: RandomNumberGenerator) -> void:
	var lights := Node3D.new()
	lights.name = "StringLights"
	root.add_child(lights)
	var bulbs := 0
	for index in found.blocks.size():
		if bulbs >= MAX_BULBS:
			break
		var b: Block = found.blocks[index]
		if not b.collide or b.shape != Block.Shape.BOX or not found.shown[index]:
			continue
		var xf: Transform3D = found.transforms[index]
		if not xf.basis.is_equal_approx(Basis.IDENTITY):
			continue
		var top := xf.origin.y + b.size.y * 0.5
		var long := maxf(b.size.x, b.size.z)
		if b.size.y < 2.5 or top < 2.5 or top > 9.0 or long < 4.0 or long > 24.0:
			continue
		# About one building in three, so the map is not covered in lights.
		if rng.randf() > 0.35:
			continue
		var along_x := b.size.x >= b.size.z
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var length := b.size.x if along_x else b.size.z
		var depth := b.size.z if along_x else b.size.x
		var steps := int(length / 0.7)
		for i in steps:
			var t := -length * 0.5 + 0.35 + i * 0.7
			# Bulbs hang in a gentle wave just outside the wall.
			var sag := 0.12 * absf(sin(i * 0.9))
			var out := depth * 0.5 + 0.07
			var p := Vector3(t, 0, side * out) if along_x else Vector3(side * out, 0, t)
			p += xf.origin
			p.y = top - 0.12 - sag
			_part(lights, p, Vector3.ONE * 0.11, BULB_COLORS[i % BULB_COLORS.size()],
				Block.Shape.BOX, false, BULB_GLOW)
			bulbs += 1


# ============================================================================
# Occupancy grid
# ============================================================================

## Which ground cells are already used (by a block, a road, a building, a
## decoration, or kept clear around spawns and waypoints).
class Occupancy:
	var size := int(ceil(AREA * 2.0 / CELL)) + 8
	var cells := PackedByteArray()

	func _init() -> void:
		cells.resize(size * size)
		cells.fill(0)

	func _index(x: int, z: int) -> int:
		return z * size + x

	func _cell(v: float) -> int:
		return int(floor((v + AREA + 2.0) / CELL))

	## Marks the ground under a block (`xf`: its transform in the map). The
	## plain ground collider (top at or below y = 0) is the one thing
	## decorations may stand on.
	func mark_block(b: Block, xf: Transform3D) -> void:
		var box := xf * AABB(-b.size * 0.5, b.size)
		if box.end.y <= 0.005:
			return
		_mark_rect(box.position.x, box.position.z, box.end.x, box.end.z)

	func mark_circle(center: Vector2, radius: float) -> void:
		_mark_rect(center.x - radius, center.y - radius, center.x + radius, center.y + radius)

	func _mark_rect(x0: float, z0: float, x1: float, z1: float) -> void:
		var cx0 := clampi(_cell(x0), 0, size - 1)
		var cz0 := clampi(_cell(z0), 0, size - 1)
		var cx1 := clampi(_cell(x1), 0, size - 1)
		var cz1 := clampi(_cell(z1), 0, size - 1)
		for z in range(cz0, cz1 + 1):
			for x in range(cx0, cx1 + 1):
				cells[_index(x, z)] = 1

	## True when every cell within `radius` of `center` is free.
	func is_free(center: Vector2, radius: float) -> bool:
		var cx0 := _cell(center.x - radius)
		var cz0 := _cell(center.y - radius)
		var cx1 := _cell(center.x + radius)
		var cz1 := _cell(center.y + radius)
		if cx0 < 0 or cz0 < 0 or cx1 >= size or cz1 >= size:
			return false
		for z in range(cz0, cz1 + 1):
			for x in range(cx0, cx1 + 1):
				if cells[_index(x, z)] != 0:
					return false
		return true

	## True when something is used within `radius` (a wall or building to
	## stand next to).
	func has_neighbor(center: Vector2, radius: float) -> bool:
		return not is_free(center, radius)

	## A free spot of `radius` near `target`: tries random points in growing
	## circles and keeps the closest free one.
	func closest_free(target: Vector2, radius: float, rng: RandomNumberGenerator) -> Dictionary:
		var best := {"found": false, "pos": Vector2.ZERO}
		var best_distance := INF
		for reach in [12.0, 30.0, AREA]:
			for attempt in 120:
				var pos := target + Vector2(rng.randf_range(-reach, reach), rng.randf_range(-reach, reach))
				var distance := pos.distance_to(target)
				if distance < best_distance and is_free(pos, radius):
					best = {"found": true, "pos": pos}
					best_distance = distance
			if best.found:
				return best
		return best


## Every Block under a node, with its transform relative to that node and
## whether it is visible (a hidden parent hides it too).
class MapBlocks:
	var blocks: Array[Block] = []
	var transforms: Array[Transform3D] = []
	var shown: Array[bool] = []

	func walk(node: Node, xf: Transform3D, visible: bool) -> void:
		for child in node.get_children():
			var child_xf := xf
			var child_visible := visible
			if child is Node3D:
				child_xf = xf * (child as Node3D).transform
				child_visible = visible and (child as Node3D).visible
			if child is Block:
				blocks.append(child)
				transforms.append(child_xf)
				shown.append(child_visible)
			if child.get_child_count() > 0:
				walk(child, child_xf, child_visible)
