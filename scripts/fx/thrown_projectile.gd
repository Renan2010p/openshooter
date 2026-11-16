extends Node3D
## Thrown item (scenes/fx/thrown_projectile.tscn): flies with gravity and
## bounces off walls. Every computer simulates the flight; the server decides
## where it explodes ([ThrowableManager]).

const GRAVITY := 16.0
const BOUNCE := 0.4

var id := 0
var owner_id := 0
var weapon_idx := 0
var velocity := Vector3.ZERO
var resting := false
var _model: Node3D


func setup(p_id: int, p_owner: int, widx: int, origin: Vector3, vel: Vector3) -> void:
	id = p_id
	owner_id = p_owner
	weapon_idx = widx
	global_position = origin
	velocity = vel
	_model = WeaponDB.get_data(widx).model.instantiate()
	add_child(_model)


## Horizontal throw direction (used to face the barrier forward).
func throw_yaw() -> float:
	return atan2(-velocity.x, -velocity.z) if Vector2(velocity.x, velocity.z).length() > 0.1 else rotation.y


func _physics_process(delta: float) -> void:
	if resting:
		return
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		global_position = to
		_model.rotate_x(delta * 9.0)
		return
	global_position = r.position + r.normal * 0.06
	var yaw := throw_yaw()
	velocity = velocity.bounce(r.normal) * BOUNCE
	rotation.y = yaw
	if r.normal.y > 0.7 and velocity.length() < 1.5:
		resting = true
		velocity = Vector3.ZERO
	Sfx.play_at("step", global_position, -4.0, 1.6)
