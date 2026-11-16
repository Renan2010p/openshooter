@tool
class_name Block
extends Node3D
## Editable building block (box, cylinder or sphere), configured in the Inspector.
##
## In the editor it draws itself so you can see what you are building. At
## runtime, the node that owns it (map, weapon, character) calls [BlockBaker]
## and all blocks become a single mesh, keeping draw calls low. If nothing
## bakes the block, it draws itself (and creates its own collision) on the next
## frame.

enum Shape { BOX, CYLINDER, SPHERE }
## AUTO: small, non-colliding pieces become "details" (only drawn up close and
## casting no shadows). ALWAYS: always part of the normal draw distance.
## DETAIL: always treated as a detail.
enum Lod { AUTO, ALWAYS, DETAIL }
## Color replaced by the player's shirt/pants/skin (used by [Avatar]).
enum Tint { NONE, SHIRT, PANTS, SKIN }

@export var shape: Shape = Shape.BOX:
	set(v):
		shape = v
		_changed()
@export var size := Vector3.ONE:
	set(v):
		size = v
		_changed()
@export var color := Color(0.7, 0.7, 0.7):
	set(v):
		color = v
		_changed()
@export_range(0.0, 1.0) var metallic := 0.0:
	set(v):
		metallic = v
		_changed()
@export_range(0.0, 1.0) var roughness := 0.85:
	set(v):
		roughness = v
		_changed()
## Self-illumination (0 = no glow). Useful for lamps, screens and LEDs.
@export_range(0.0, 8.0) var emission := 0.0:
	set(v):
		emission = v
		_changed()
## Creates collision (the "world" layer) when part of a map.
@export var collide := true
@export var tint: Tint = Tint.NONE
## Level of detail on maps (see [enum Lod]).
@export var lod: Lod = Lod.AUTO

var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_changed()
	else:
		_runtime_fallback.call_deferred()


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	_preview.mesh = make_mesh()
	_preview.material_override = make_material()


## Small piece that can disappear at a distance without anyone noticing.
func is_detail() -> bool:
	match lod:
		Lod.ALWAYS:
			return false
		Lod.DETAIL:
			return true
	return not collide and size.x * size.y * size.z < 0.3


func make_mesh() -> PrimitiveMesh:
	match shape:
		Shape.CYLINDER:
			var c := CylinderMesh.new()
			c.top_radius = size.x / 2.0
			c.bottom_radius = size.x / 2.0
			c.height = size.y
			c.radial_segments = 10
			c.rings = 1
			return c
		Shape.SPHERE:
			var s := SphereMesh.new()
			s.radius = size.x / 2.0
			s.height = size.y
			s.radial_segments = 12
			s.rings = 6
			return s
	var b := BoxMesh.new()
	b.size = size
	return b


func make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func make_shape() -> Shape3D:
	if shape == Shape.CYLINDER:
		var c := CylinderShape3D.new()
		c.radius = size.x / 2.0
		c.height = size.y
		return c
	var b := BoxShape3D.new()
	b.size = size
	return b


## Only used when no [BlockBaker] merged this block.
func _runtime_fallback() -> void:
	if has_meta("baked") or not is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = make_mesh()
	mi.material_override = make_material()
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = make_shape()
		body.add_child(cs)
		add_child(body)
