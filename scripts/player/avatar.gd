class_name Avatar
extends Node3D
## Articulated block character (scenes/player/avatar.tscn) and its animations.
##
## Joints: LegL/LegR → Knee, Spine → ArmL/ArmR → Elbow, Spine → Head.
## Animations are procedural: every frame the [Player] passes an [AnimState]
## and each joint smoothly moves toward the computed pose.
##
## Blocks with a "tint" receive the player's shirt, pants and skin colors.


## Everything the animation needs to know about the player this frame.
class AnimState:
	## Horizontal speed (m/s).
	var speed := 0.0
	## Movement direction relative to the body: x = right, y = forward.
	var move := Vector2.ZERO
	var pitch := 0.0
	var on_floor := true
	var crouching := false
	var sprinting := false
	var alive := true
	## Two-handed weapon (AK, shotgun, sniper).
	var two_handed := true
	## 0..1 while reloading; < 0 when not reloading.
	var reload := -1.0
	## 0 = weapon being drawn, 1 = ready.
	var draw := 1.0
	## Shot kick (1 right after firing).
	var kick := 0.0
	## Knife swing (1 at the start of the swing).
	var swing := 0.0


@export_group("Stride")
## Meters per complete step cycle.
@export var stride_length := 2.2
@export var walk_stride_angle := 0.55
@export var sprint_stride_angle := 0.85
@export_group("Smoothing")
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
## Where the third-person weapon is attached.
@onready var hand: Node3D = $Spine/ArmR/Elbow/HandSocket

## Weapon foregrip (Marker3D "Foregrip"): the left hand reaches for it.
var foregrip: Node3D
## Arm lengths: shoulder → elbow and elbow → center of the hand.
const UPPER_ARM := 0.34
const FOREARM := 0.4
## Where the left elbow points (spine space: -X is left).
const ELBOW_POLE := Vector3(-0.5, -1.0, 0.3)

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


## Applies the colors and merges the blocks of each joint into one mesh.
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


## Render layer (the local player does not see their own body: layer 2).
func set_render_layer(layer: int) -> void:
	for mi in find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = layer


## Small jolt backwards when hit.
func flinch() -> void:
	_flinch = 1.0


## Preview pose (Locker): breathes and holds a weapon.
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

	# Step cycle proportional to distance traveled.
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

	# --- Legs ---
	# Positive X rotation swings the foot forward; the knee bends with negative X.
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

	# --- Hips and torso ---
	var drop := 0.0
	if s.crouching:
		drop = 0.42
	drop += _land * 0.12 + absf(sw) * 0.05 * moving
	position.y = lerpf(position.y, -drop, k)
	var lean := -0.08 * moving * dir.y - (0.18 if s.sprinting else 0.0) + _flinch * 0.3
	var aim_share := s.pitch * 0.35
	spine.position = _spine_base + Vector3(0, breath * 0.008, 0)
	_to(spine, Vector3(lean + aim_share, sin(_phase) * 0.06 * moving, -dir.x * 0.08 * moving), k)

	# --- Arms ---
	var aim := s.pitch - aim_share
	var raise := (1.0 - s.draw) * 1.3
	var right := Vector3(PI / 2.0 + aim - raise - s.kick * 0.25 - s.swing * 1.1, s.swing * 0.5, 0)
	var right_elbow := Vector3(0.15 + s.kick * 0.3 - s.swing * 0.15, 0, 0)
	var left := Vector3(PI / 2.0 + aim - raise, -0.45, 0)
	var left_elbow := Vector3(0.35, 0, 0)
	if s.sprinting and s.on_floor:
		# Weapon held across the chest while sprinting.
		right = Vector3(PI / 2.0 * 0.45, 0, 0.45)
		right_elbow = Vector3(1.1, 0, 0)
		left = Vector3(PI / 2.0 * 0.55, -0.2, 0)
		left_elbow = Vector3(1.0, 0, 0)
	if not s.two_handed:
		# Free hand swings with the steps.
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
	var grip_ok := s.two_handed and is_instance_valid(foregrip) and s.reload < 0.0 and not (s.sprinting and s.on_floor) and s.draw > 0.6
	if grip_ok:
		_left_hand_ik(k)
	else:
		_to(arm_l, left, k)
		_to(elbow_l, left_elbow, k)

	# --- Head ---
	_to(head, Vector3(aim * 0.6 - _flinch * 0.2, 0, 0), k)


func _animate_death(delta: float, k: float) -> void:
	if _death_t < 0.0:
		_death_t = 0.0
		_death_side = randf_range(-1.0, 1.0)
	_death_t += delta
	# The knees buckle first, then the body falls backwards.
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


## Two-bone IK: positions the left shoulder and elbow so the hand lands on the
## weapon foregrip. Law of cosines for the shoulder angle; the elbow stays in
## the plane defined by the target and ELBOW_POLE.
func _left_hand_ik(k: float) -> void:
	# The weapon follows the right arm, which just changed this frame.
	var target := spine.to_local(foregrip.global_position)
	var shoulder := arm_l.position
	var to_target := target - shoulder
	var dist := clampf(to_target.length(), 0.1, UPPER_ARM + FOREARM - 0.01)
	var dir := to_target.normalized()
	var cos_a := (UPPER_ARM * UPPER_ARM + dist * dist - FOREARM * FOREARM) / (2.0 * UPPER_ARM * dist)
	var a := acos(clampf(cos_a, -1.0, 1.0))
	var pole := (ELBOW_POLE - dir * ELBOW_POLE.dot(dir)).normalized()
	var upper := (dir * cos(a) + pole * sin(a)).normalized()
	var fore := (shoulder + dir * dist - (shoulder + upper * UPPER_ARM)).normalized()
	# Arm basis: -Y along the arm, X is the elbow hinge axis.
	var x_axis := upper.cross(fore)
	if x_axis.length() < 0.001:
		x_axis = dir.cross(pole)
	x_axis = x_axis.normalized()
	var y_axis := -upper
	var basis := Basis(x_axis, y_axis, x_axis.cross(y_axis).normalized()).orthonormalized()
	arm_l.quaternion = arm_l.quaternion.slerp(basis.get_rotation_quaternion(), k)
	# The elbow rotates on X: 0 = straight forearm (-Y); positive bends toward -Z.
	var f_local := basis.inverse() * fore
	elbow_l.rotation = elbow_l.rotation.lerp(Vector3(atan2(-f_local.z, -f_local.y), 0, 0), k)


func _to(node: Node3D, target: Vector3, k: float) -> void:
	node.rotation = node.rotation.lerp(target, k)
