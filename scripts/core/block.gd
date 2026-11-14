@tool
class_name Block
extends Node3D
## Bloco de construção editável no Inspetor (caixa, cilindro ou esfera).
##
## No editor ele se desenha sozinho para você ver o que está montando. No jogo,
## quem o contém (mapa, arma, boneco) chama [BlockBaker] e todos os blocos viram
## um único mesh, o que mantém o número de draw calls baixo. Se ninguém juntar o
## bloco, ele se desenha sozinho (e cria a própria colisão) no quadro seguinte.

enum Shape { BOX, CYLINDER, SPHERE }
## Cor trocada pela roupa/pele do jogador (usado pelo [Avatar]).
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
## Brilho próprio (0 = não brilha). Bom para lâmpadas, telas e LEDs.
@export_range(0.0, 8.0) var emission := 0.0:
	set(v):
		emission = v
		_changed()
## Cria colisão (camada "mundo") quando faz parte do mapa.
@export var collide := true
@export var tint: Tint = Tint.NONE

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


## Usado só se nenhum [BlockBaker] juntou este bloco.
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
