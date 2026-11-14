class_name Avatar
extends Node3D
## Boneco articulado em blocos (scenes/player/avatar.tscn) e suas animações.
##
## Articulações: LegL/LegR → Knee, Spine → ArmL/ArmR → Elbow, Spine → Head.
## As animações são procedurais: a cada quadro o [Player] passa um [AnimState]
## e cada articulação vai suavemente até a pose calculada.
##
## Os blocos com "tint" recebem as cores da camisa, calça e pele do jogador.


## Tudo o que a animação precisa saber sobre o jogador neste quadro.
class AnimState:
	## Velocidade horizontal (m/s).
	var speed := 0.0
	## Direção do movimento relativa ao corpo: x = direita, y = frente.
	var move := Vector2.ZERO
	var pitch := 0.0
	var on_floor := true
	var crouching := false
	var sprinting := false
	var alive := true
	## Arma de duas mãos (AK, escopeta, fuzil).
	var two_handed := true
	## 0..1 durante a recarga; < 0 sem recarga.
	var reload := -1.0
	## 0 = arma sendo sacada, 1 = pronta.
	var draw := 1.0
	## Coice do tiro (1 logo depois do disparo).
	var kick := 0.0
	## Golpe de faca (1 no início do golpe).
	var swing := 0.0


@export_group("Passada")
## Metros por ciclo completo de passos.
@export var stride_length := 2.2
@export var walk_stride_angle := 0.55
@export var sprint_stride_angle := 0.85
@export_group("Suavização")
@export var blend_speed := 14.0

@onready var leg_l: Node3D = $LegL
@onready var leg_r: Node3D = $LegR
@onready var knee_l: Node3D = $LegL/Knee
@onready var knee_r: Node3D = $LegR/Knee
@onready var spine: Node3D = $Spine
@onready var arm_l: Node3D = $Spine/ArmL
@onready var arm_r: Node3D = $Spine/ArmR
@onready var elbow_l: Node3D = $Spine/ArmL/Elbow
@onready var elbow_r: Node3D = $Spine/ArmR/Elbow
@onready var head: Node3D = $Spine/Head
## Onde a arma em terceira pessoa é presa.
@onready var hand: Node3D = $Spine/ArmR/Elbow/HandSocket

var _baked := false
var _phase := 0.0
var _time := 0.0
var _was_on_floor := true
var _land := 0.0
var _flinch := 0.0
var _death_t := -1.0
var _death_side := 0.0
var _spine_base := Vector3.ZERO


func _ready() -> void:
	_spine_base = spine.position


## Aplica as cores e junta os blocos de cada articulação num mesh.
func setup(shirt: Color, pants: Color, skin: Color) -> void:
	if _baked:
		return
	_baked = true
	for b in BlockBaker.collect(self):
		match b.tint:
			Block.Tint.SHIRT:
				b.color = shirt
			Block.Tint.PANTS:
				b.color = pants
			Block.Tint.SKIN:
				b.color = skin
	_bake_joints(self)


func _bake_joints(node: Node3D) -> void:
	BlockBaker.bake(node, false)
	for c in node.get_children():
		if c is Node3D and not (c is Block) and not (c is VisualInstance3D) and not (c is Marker3D):
			_bake_joints(c)


## Camada de renderização (o jogador local não vê o próprio corpo: camada 2).
func set_render_layer(layer: int) -> void:
	for mi in find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = layer


## Pequeno tranco para trás ao levar um tiro.
func flinch() -> void:
	_flinch = 1.0


## Pose de exibição (Armário): respira e segura a arma.
func idle_preview(delta: float) -> void:
	var s := AnimState.new()
	animate(delta, s)


func animate(delta: float, s: AnimState) -> void:
	_time += delta
	var k := 1.0 - exp(-blend_speed * delta)
	if not s.alive:
		_animate_death(delta, k)
		return
	if _death_t >= 0.0:
		_death_t = -1.0
		rotation = Vector3.ZERO
		position = Vector3.ZERO

	# Ciclo de passos proporcional à distância percorrida.
	var moving := clampf(s.speed / 6.0, 0.0, 1.0)
	_phase += delta * s.speed / stride_length * TAU
	if s.on_floor and not _was_on_floor:
		_land = 1.0
	_was_on_floor = s.on_floor
	_land = maxf(0.0, _land - delta * 4.0)
	_flinch = maxf(0.0, _flinch - delta * 5.0)

	var dir := s.move.normalized() if s.move.length() > 0.1 else Vector2.ZERO
	var amp := (sprint_stride_angle if s.sprinting else walk_stride_angle) * moving
	if s.crouching:
		amp *= 0.6
	var sw := sin(_phase)
	var lift_l := maxf(0.0, cos(_phase))
	var lift_r := maxf(0.0, -cos(_phase))
	var breath := sin(_time * 1.7)

	# --- Pernas ---
	# Rotação X positiva leva o pé para a frente; joelho dobra com X negativo.
	var hip_l := Vector3(sw * amp * dir.y, 0, sw * amp * dir.x * 0.6)
	var hip_r := Vector3(-sw * amp * dir.y, 0, -sw * amp * dir.x * 0.6)
	var bend_l := lift_l * amp * 1.5
	var bend_r := lift_r * amp * 1.5
	if s.crouching:
		hip_l.x += 0.9
		hip_r.x += 0.5
		bend_l += 1.4
		bend_r += 1.0
	if not s.on_floor:
		hip_l = Vector3(0.6, 0, 0)
		hip_r = Vector3(0.2, 0, 0)
		bend_l = 1.1
		bend_r = 0.6
	bend_l += _land * 0.6
	bend_r += _land * 0.6
	_to(leg_l, hip_l, k)
	_to(leg_r, hip_r, k)
	_to(knee_l, Vector3(-bend_l, 0, 0), k)
	_to(knee_r, Vector3(-bend_r, 0, 0), k)

	# --- Quadril e tronco ---
	var drop := 0.0
	if s.crouching:
		drop = 0.42
	drop += _land * 0.12 + absf(sw) * 0.05 * moving
	position.y = lerpf(position.y, -drop, k)
	var lean := -0.08 * moving * dir.y - (0.18 if s.sprinting else 0.0) + _flinch * 0.3
	var aim_share := s.pitch * 0.35
	spine.position = _spine_base + Vector3(0, breath * 0.008, 0)
	_to(spine, Vector3(lean + aim_share, sin(_phase) * 0.06 * moving, -dir.x * 0.08 * moving), k)

	# --- Braços ---
	var aim := s.pitch - aim_share
	var raise := (1.0 - s.draw) * 1.3
	var right := Vector3(PI / 2.0 + aim - raise - s.kick * 0.25 - s.swing * 1.1, s.swing * 0.5, 0)
	var right_elbow := Vector3(0.15 + s.kick * 0.3 - s.swing * 0.15, 0, 0)
	var left := Vector3(PI / 2.0 + aim - raise, -0.45, 0)
	var left_elbow := Vector3(0.35, 0, 0)
	if s.sprinting and s.on_floor:
		# Arma atravessada no peito enquanto corre.
		right = Vector3(PI / 2.0 * 0.45, 0, 0.45)
		right_elbow = Vector3(1.1, 0, 0)
		left = Vector3(PI / 2.0 * 0.55, -0.2, 0)
		left_elbow = Vector3(1.0, 0, 0)
	if not s.two_handed:
		# Mão livre balança no ritmo dos passos.
		left = Vector3(-sw * amp * 0.9 * dir.y + breath * 0.02, 0, -0.08)
		left_elbow = Vector3(0.25 + absf(sw) * 0.3 * moving, 0, 0)
	if s.reload >= 0.0:
		var r := sin(s.reload * PI)
		right.z += r * 0.5
		right.x -= r * 0.35
		left = Vector3(PI / 2.0 * 0.5 + r * 0.4, -0.2, 0)
		left_elbow = Vector3(0.9 + r * 0.6, 0, 0)
	if not s.on_floor:
		left.z -= 0.3
	_to(arm_r, right, k)
	_to(elbow_r, right_elbow, k)
	_to(arm_l, left, k)
	_to(elbow_l, left_elbow, k)

	# --- Cabeça ---
	_to(head, Vector3(aim * 0.6 - _flinch * 0.2, 0, 0), k)


func _animate_death(delta: float, k: float) -> void:
	if _death_t < 0.0:
		_death_t = 0.0
		_death_side = randf_range(-1.0, 1.0)
	_death_t += delta
	# Primeiro os joelhos cedem, depois o corpo tomba para trás.
	var buckle := clampf(_death_t / 0.25, 0.0, 1.0)
	var fall := clampf((_death_t - 0.12) / 0.5, 0.0, 1.0)
	fall = 1.0 - pow(1.0 - fall, 3.0)
	rotation.x = fall * PI / 2.0 * 0.95
	rotation.z = fall * _death_side * 0.25
	position.y = -buckle * 0.25 * (1.0 - fall)
	_to(knee_l, Vector3(-buckle * 1.2 * (1.0 - fall * 0.7), 0, 0), k)
	_to(knee_r, Vector3(-buckle * 0.9 * (1.0 - fall * 0.7), 0, 0), k)
	_to(leg_l, Vector3(buckle * 0.5, 0, -0.15), k)
	_to(leg_r, Vector3(buckle * 0.3, 0, 0.15), k)
	_to(arm_l, Vector3(PI * 0.6 * fall, 0, -0.9 * fall), k)
	_to(arm_r, Vector3(PI * 0.6 * fall, 0, 0.9 * fall), k)
	_to(elbow_l, Vector3(0.3, 0, 0), k)
	_to(elbow_r, Vector3(0.3, 0, 0), k)
	_to(head, Vector3(-0.5 * fall, _death_side * 0.4, 0), k)
	_to(spine, Vector3(-0.2 * fall, 0, 0), k)


func _to(node: Node3D, target: Vector3, k: float) -> void:
	node.rotation = node.rotation.lerp(target, k)
