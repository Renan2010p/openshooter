class_name Avatar
extends Node3D
## Boneco em blocos (scenes/player/avatar.tscn). Os blocos com "tint" recebem as
## cores da camisa, calça e pele do jogador. Cada articulação vira um mesh só.

@onready var leg_l: Node3D = $LegL
@onready var leg_r: Node3D = $LegR
@onready var arm_l: Node3D = $ArmL
@onready var arm_r: Node3D = $ArmR
@onready var head: Node3D = $Head
## Onde a arma em terceira pessoa é presa.
@onready var hand: Node3D = $ArmR/HandSocket

var _bob := 0.0
var _baked := false


## Aplica as cores e junta os blocos. Chame logo depois de adicionar à árvore.
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
	BlockBaker.bake(self, false)
	for pivot in [leg_l, leg_r, arm_l, arm_r, head]:
		BlockBaker.bake(pivot, false)


## Camada de renderização (o jogador local não vê o próprio corpo: camada 2).
func set_render_layer(layer: int) -> void:
	for mi in find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = layer


## Pose segurando a arma; só para a prévia do Armário.
func hold_pose() -> void:
	arm_r.rotation = Vector3(PI / 2.0, 0, 0)
	arm_l.rotation = Vector3(PI / 2.0, -0.45, 0)


func animate(delta: float, speed: float, pitch: float, crouching: bool, alive: bool, swing: float) -> void:
	_bob += delta * speed * 1.4
	var stride := sin(_bob) * clampf(speed / 6.0, 0.0, 1.0) * 0.7
	leg_l.rotation.x = stride
	leg_r.rotation.x = -stride
	arm_r.rotation = Vector3(PI / 2.0 + pitch - swing * 0.8, 0, 0)
	arm_l.rotation = Vector3(PI / 2.0 + pitch, -0.45, 0)
	head.rotation.x = pitch * 0.7
	position.y = -0.5 if crouching and alive else 0.0
	if alive:
		rotation.x = 0.0
	else:
		rotation.x = lerpf(rotation.x, PI / 2.0, minf(1.0, delta * 8.0))
