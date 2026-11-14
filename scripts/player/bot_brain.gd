class_name BotBrain
extends Node
## IA dos bots (roda só no servidor): procura inimigos visíveis, mira com atraso
## e erro, desvia para os lados e anda entre os waypoints do mapa.

## Tempo de reação ao ver um inimigo (segundos).
@export var reaction_min := 0.3
@export var reaction_max := 0.6
## Erro de mira inicial; diminui enquanto o bot continua mirando.
@export var aim_error := 0.035
@export var view_distance := 65.0
@export var turn_speed := 6.0

var player: Player
var _waypoint := Vector3.ZERO
var _enemy: Player
var _scan := 0.0
var _react := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _stuck := 0.0
var _err := Vector2.ZERO


## Devolve o desejo de movimento deste quadro: {wish: Vector3, jump: bool}.
func think(delta: float) -> Dictionary:
	var res := {"wish": Vector3.ZERO, "jump": false}
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.25
		var e := _find_enemy()
		if e != _enemy:
			_enemy = e
			_react = randf_range(reaction_min, reaction_max)
			_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * aim_error
	if _enemy and _enemy.alive:
		_fight(delta, res)
	else:
		_wander(delta, res)
	return res


func reset() -> void:
	_waypoint = Vector3.ZERO
	_enemy = null


func _fight(delta: float, res: Dictionary) -> void:
	var target := _enemy.global_position + Vector3(0, 1.3, 0)
	var to := target - player.head.global_position
	var want_yaw := atan2(-to.x, -to.z)
	player.rotation.y = lerp_angle(player.rotation.y, want_yaw, minf(1.0, delta * turn_speed))
	player.pitch = lerpf(player.pitch, atan2(to.y, Vector2(to.x, to.z).length()), minf(1.0, delta * turn_speed))
	_react -= delta
	_err *= 1.0 - delta * 0.6
	if _react <= 0.0 and absf(angle_difference(player.rotation.y, want_yaw)) < 0.1:
		player.weapons.try_fire(_err)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe = [-1.0, 1.0].pick_random()
		_strafe_t = randf_range(0.6, 1.6)
	var dist := to.length()
	var forward := 0.0
	var idx := player.weapons.index
	if idx == WeaponDB.SHOTGUN or idx == WeaponDB.PISTOL:
		forward = 1.0 if dist > 7.0 else 0.0
	elif dist > 28.0:
		forward = 1.0
	elif dist < 7.0:
		forward = -0.6
	res.wish = player.global_basis * Vector3(_strafe * 0.8, 0, -forward)


func _wander(delta: float, res: Dictionary) -> void:
	var map := player.world.map
	var pos := player.global_position
	if _waypoint == Vector3.ZERO or Vector2(_waypoint.x - pos.x, _waypoint.z - pos.z).length() < 1.5:
		_waypoint = map.random_waypoint()
	var to := _waypoint - pos
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 4.0))
	player.pitch = lerpf(player.pitch, 0.0, minf(1.0, delta * 4.0))
	res.wish = -player.global_basis.z
	if Vector2(player.velocity.x, player.velocity.z).length() < 1.0:
		_stuck += delta
	else:
		_stuck = maxf(0.0, _stuck - delta)
	res.jump = _stuck > 0.4
	if _stuck > 1.8:
		_waypoint = map.random_waypoint()
		_stuck = 0.0
	if player.weapons.mag() < player.weapons.data().magazine / 2:
		player.weapons.start_reload()


func _find_enemy() -> Player:
	var best: Player = null
	var best_d := view_distance
	for p in player.world.players.get_children():
		if p == player or not p.alive:
			continue
		var d := player.global_position.distance_to(p.global_position)
		if d < best_d and _can_see(p):
			best = p
			best_d = d
	return best


func _can_see(p: Player) -> bool:
	var q := PhysicsRayQueryParameters3D.create(player.head.global_position, p.global_position + Vector3(0, 1.5, 0), 1)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
