class_name TrailerDirector
extends Node
## Cinematic director used to record the game trailer (tools/trailer/).
##
## Added to a running [World] by main.gd when the game is started with
## `--trailer=SEGMENT`. Bots fight for real; this node owns a free camera that
## cuts between shots of the action (chase, orbit, hero, low dolly, flyover),
## hides the HUD and draws a cinematic overlay: letterbox, vignette, captions
## and the closing logo card. Each segment prints the frame where it starts
## (for trimming) and quits the game when it ends.

const SEGMENTS := [
	{   # 0 - opening: title cards on black, then the first shots
		"intro": 7.2,
		"cards": [
			["", "RL PROJECTS", "PRESENTS"],
			["FROM THE CREATORS OF", "Five Nights With Friends", ""],
			["A GAME BY", "Renan Hilário", ""],
		],
		"length": 18.2,
		"shots": [["fly", 3.4], ["hero", 3.2], ["pov", 4.4]],
		"captions": [
			[0.5, 2.8, "A NEW LAN SHOOTER", "Lock and load"],
			[4.2, 3.4, "FREE  ·  OPEN SOURCE  ·  GODOT 4", "Fast tactical firefights"],
		],
	},
	{   # 1 - harbor
		"length": 10.0,
		"shots": [["pov", 3.6], ["grenade", 3.4], ["hero", 3.0]],
		"captions": [[0.6, 3.6, "FOUR HANDCRAFTED MAPS", "Harbor"]],
	},
	{   # 2 - desert
		"length": 10.0,
		"shots": [["chase", 3.0], ["grenade", 3.4], ["pov", 3.6]],
		"captions": [[0.6, 3.6, "NINE WEAPONS  ·  FIVE GAME MODES", "Desert Village"]],
	},
	{   # 3 - arctic
		"length": 10.0,
		"shots": [["pov", 3.6], ["grenade", 3.4], ["orbit", 3.0]],
		"captions": [[0.6, 3.6, "UP TO 12 PLAYERS  ·  BOTS FOR OFFLINE PLAY", "Arctic Base"]],
	},
	{   # 4 - closing logo
		"length": 13.0,
		"shots": [["fly", 13.0]],
		"captions": [],
		"logo": 1.0,
		## Seconds after the logo when the platform row appears.
		"platforms": 4.0,
	},
]

## Seconds of real fighting before the segment starts (screen stays black).
const WARMUP := 6.0
const ACCENT := Color("#f5a524")
const TEXT := Color("#e9eef5")
const CINEMA_ASPECT := 2.35
const PLATFORMS := [
	["Windows", "res://assets/ui/platforms/windows.svg"],
	["Linux", "res://assets/ui/platforms/linux.svg"],
	["macOS", "res://assets/ui/platforms/apple.svg"],
	["Android", "res://assets/ui/platforms/android.svg"],
]

var world: World
var segment := 0

var _cam: Camera3D
var _t := -WARMUP
var _shot := -1
var _shot_t := 0.0
var _shot_type := ""
var _target: Player
var _shot_seed := 0.0
var _last_fire := {}
var _started := false
## Game time (the wall clock does not follow the movie writer).
var _clock := 0.0
var _dead_t := 0.0
## Grenade shot: the enemy it is thrown at, and whether it was thrown yet.
var _foe: Player
var _thrown := false
var _steered := false
var _grenade: Node3D
var _foes: Array[Player] = []
## [time, Player, headshot] for each scheduled enemy fall.
var _deaths: Array = []
var _shot_len := 3.0
## POV shot: the subject is filmed from outside, the camera dives into its
## head and the view switches to its own first-person camera (with HUD).
const POV_OUTSIDE := 1.1
const POV_DIVE := 0.38
var _pov_on := false
var _dive_from: Transform3D
var _dive_fov := 62.0
## Which side of the subject the camera frames from (+1 right, -1 left).
var _side := 1.0

var _fade: ColorRect
var _bars: Array[ColorRect] = []
var _caption_box: Control
var _logo_box: Control
var _cards_box: Control


func _ready() -> void:
	segment = clampi(segment, 0, SEGMENTS.size() - 1)
	_cam = Camera3D.new()
	_cam.name = "TrailerCamera"
	_cam.fov = 62.0
	_cam.far = 600.0
	# Layer 4 is the first-person weapon; layer 2 the local player's body.
	_cam.cull_mask = 1 | 2
	world.add_child(_cam)
	_build_overlay()


func _seg() -> Dictionary:
	return SEGMENTS[segment]


func _intro() -> float:
	return float(_seg().get("intro", 0.0))


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if world.hud:
		world.hud.visible = _pov_on
	if _pov_on and _target and is_instance_valid(_target) and is_instance_valid(_target.camera):
		if not _target.camera.current:
			_target.camera.make_current()
	elif not _cam.current:
		_cam.make_current()
	_clock += delta
	_track_fire()
	for p in world.players.get_children():
		(p as Player).name_tag.visible = false
	_t += delta
	if _t < 0.0:
		_fade.color.a = 1.0
		_update_camera(delta, true)
		return
	if not _started:
		_started = true
		print("TRAILER_START_FRAME=%d" % Engine.get_frames_drawn())
		var intro := _intro()
		var cards: Array = _seg().get("cards", [])
		for i in cards.size():
			var card: Array = cards[i]
			var slot := intro / cards.size()
			get_tree().create_timer(i * slot + 0.15).timeout.connect(
				_show_card.bind(card[0], card[1], card[2], slot - 0.3))
		if intro > 0.0:
			get_tree().create_timer(intro).timeout.connect(_fade_in)
		else:
			_fade_in()
		for c in _seg().captions:
			_schedule_caption(float(c[0]) + intro, c[1], c[2], c[3])
		if _seg().has("logo"):
			get_tree().create_timer(_seg().logo).timeout.connect(_show_logo)
	# Shot list (scene time starts after the title cards).
	var st := maxf(0.0, _t - _intro())
	var shots: Array = _seg().shots
	var elapsed := 0.0
	var index := shots.size() - 1
	for i in shots.size():
		if st < elapsed + float(shots[i][1]):
			index = i
			break
		elapsed += float(shots[i][1])
	if index != _shot:
		_shot = index
		_start_shot(shots[index][0], float(shots[index][1]))
	if _t < _intro():
		# Behind the title cards: keep the first shot framed, not moving.
		_shot_t = 0.0
		_update_camera(delta, true)
		return
	_shot_t += delta
	if _shot_type == "grenade" and not _thrown and _shot_t >= 0.35:
		_thrown = true
		_throw_grenade()
	_direct(delta)
	_follow_action(delta)
	_update_camera(delta, false)
	if _t >= float(_seg().length):
		print("TRAILER_END_FRAME=%d" % Engine.get_frames_drawn())
		get_tree().quit()


## Remembers when each player last fired, to find where the action is.
func _track_fire() -> void:
	var now := _clock
	for node in world.players.get_children():
		var p := node as Player
		if p.weapons.kick > 0.9 or p.weapons.swing > 0.9:
			_last_fire[p.pid] = now


# ------------------------------------------------------------------ shots

func _start_shot(type: String, length := 3.0) -> void:
	# Everyone becomes an actor: no AI. Extras stand still off the action.
	for node in world.players.get_children():
		var pl := node as Player
		pl.hold = false
		pl.puppet = true
		pl.puppet_input = _idle_input()
		pl.weapons.aiming = false
		# Extras never die from stray bullets; actors get their health in _cast.
		if pl.alive:
			pl.hp = 100000
	_shot_type = type
	_shot_t = 0.0
	_shot_len = length
	_shot_seed = randf() * TAU
	_foe = null
	_foes.clear()
	_deaths.clear()
	_thrown = false
	_steered = false
	_grenade = null
	_target = null
	_set_pov(false)
	_cam.fov = 62.0
	_cam.cull_mask = 1 | 2
	if type == "pov":
		var me := world.local_player
		if me and me.alive:
			_target = me
			_foes = _stage(me, 2, 12.0)
		else:
			_shot_type = "chase"
			type = "chase"
	if type != "fly" and type != "pov":
		# Find a subject with open ground ahead and bring enemies into its
		# line of fire.
		var count := 1 if type == "grenade" else 2
		var tried := 0
		for p in _ranked_targets():
			tried += 1
			var foes := _stage(p, count, 13.0 if type == "grenade" else 11.0)
			if not foes.is_empty() or tried >= 6:
				_target = p
				_foes = foes
				break
	if _target:
		_cast(type)
	if _target == null:
		_target = _pick_target()
	_update_camera(0.0, true)


func _idle_input() -> Dictionary:
	return {"wish": Vector3.ZERO, "jump": false, "crouch": false, "sprint": false}


## Sets up the actors of a shot: weapons, health and when each enemy falls.
func _cast(type: String) -> void:
	_foe = _foes[0] if not _foes.is_empty() else null
	# The hero never dies on camera.
	_target.hp = 100000
	_target.weapons.equip(WeaponDB.RIFLE, false, true)
	_target.weapons.ammo[WeaponDB.RIFLE] = [30, 90]
	var foe_guns := [WeaponDB.RIFLE, WeaponDB.PISTOL, WeaponDB.SHOTGUN]
	for i in _foes.size():
		var f := _foes[i]
		f.weapons.equip(foe_guns[i % foe_guns.size()], false, true)
		f.weapons.refill()
		# Enemies only fall when the choreography says so (grenade: the blast).
		f.hp = 100 if type == "grenade" else 100000
	if type == "grenade":
		return
	# Enemy falls: spaced through the shot; in POV, after the dive.
	var start := POV_OUTSIDE + POV_DIVE + 0.55 if type == "pov" else 0.9
	var end := _shot_len - 0.35
	for i in _foes.size():
		var at := start + (end - start) * float(i) / maxf(1.0, _foes.size() - 1.0) if _foes.size() > 1 else (start + end) * 0.5
		_deaths.append([at, _foes[i], randf() < 0.45])


## Runs the actors every frame: the hero strafes, tracks the next enemy and
## fires a burst before each scheduled fall; enemies return fire and miss.
func _direct(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return
	var t := _shot_t
	var hero := _target
	# Next enemy still standing.
	var aim_at: Player = null
	var next_death := 1e9
	for d in _deaths:
		if (d[1] as Player).alive and not d.has("done"):
			aim_at = d[1]
			next_death = d[0]
			break
	if aim_at == null and _foe and is_instance_valid(_foe) and _foe.alive:
		aim_at = _foe

	# Hero movement.
	var fwd := -hero.global_basis.z
	fwd.y = 0.0
	var right := fwd.normalized().cross(Vector3.UP)
	var wish := Vector3.ZERO
	match _shot_type:
		"pov":
			wish = fwd.normalized() * 0.32 + right * sin(t * 1.3) * 0.25
		"grenade":
			wish = Vector3.ZERO
		_:
			wish = right * sin(t * 1.5 + _shot_seed) * 0.55
	hero.puppet_input = {"wish": wish, "jump": false, "crouch": false, "sprint": false}

	# Hero aim and fire.
	if aim_at:
		_aim(hero, aim_at.global_position + Vector3.UP * 1.25, delta, 9.0)
	var bursting := aim_at != null and t >= next_death - 0.55 and t < next_death
	# Hip fire in first person: the crosshair shows and the weapon never
	# covers the target (sights would fill the middle of the frame).
	hero.weapons.aiming = false
	if bursting and _shot_type != "grenade":
		hero.weapons.cooldown = minf(hero.weapons.cooldown, hero.weapons.data().fire_interval)
		hero.weapons.try_fire()

	# Scheduled falls.
	for d in _deaths:
		var foe := d[1] as Player
		if not d.has("done") and t >= d[0] and foe.alive:
			d.append("done")
			world.combat.server_damage(foe.pid, hero.pid, 10000000, hero.weapons.index, d[2])

	# Enemies: small strafe, aim a little off the hero and fire in bursts.
	for i in _foes.size():
		var f := _foes[i]
		if not f.alive:
			continue
		var side := f.global_basis.x
		f.puppet_input = {"wish": side * sin(t * 1.8 + i * 2.0) * 0.4, "jump": false, "crouch": false, "sprint": false}
		var miss := side * (0.9 if i % 2 == 0 else -0.9)
		_aim(f, hero.global_position + Vector3.UP * 1.3 + miss, delta, 6.0)
		if fmod(t + i * 0.7, 1.4) < 0.5 and t > 0.4:
			f.weapons.try_fire()

	# Grenade: once thrown, steer the projectile onto the enemy; when it goes
	# off, the enemy falls with it.
	if _shot_type == "grenade" and _thrown:
		if not _steered:
			_steer_grenade()
		elif not is_instance_valid(_grenade) and _foe and is_instance_valid(_foe) and _foe.alive:
			world.combat.server_damage(_foe.pid, hero.pid, 10000000, WeaponDB.GRENADE, false)


## Turns a player smoothly toward a point (yaw on the body, pitch on the head).
func _aim(p: Player, point: Vector3, delta: float, speed: float) -> void:
	var to := point - p.head.global_position
	var k := minf(1.0, delta * speed)
	p.rotation.y = lerp_angle(p.rotation.y, atan2(-to.x, -to.z), k)
	p.pitch = lerpf(p.pitch, atan2(to.y, Vector2(to.x, to.z).length()), k)


## Gives the newest grenade of the hero a ballistic arc that lands on the enemy.
func _steer_grenade() -> void:
	if _foe == null or not is_instance_valid(_foe):
		_steered = true
		return
	for c in world.throwables.get_children():
		if "owner_id" in c and c.owner_id == _target.pid and not c.resting:
			var flight := 0.95
			var from: Vector3 = c.global_position
			# Land a little short: the bounce carries it to the enemy's feet.
			var short := (from - _foe.global_position)
			short.y = 0.0
			var goal := _foe.global_position + short.normalized() * 1.6 + Vector3.UP * 0.1
			var v := (goal - from) / flight
			v.y += 0.5 * 16.0 * flight  # ThrownProjectile.GRAVITY
			c.velocity = v
			_grenade = c
			_steered = true
			return


## Living players, best subjects first.
func _ranked_targets() -> Array[Player]:
	var list: Array[Player] = []
	for node in world.players.get_children():
		# The POV player stars only in its first-person shots (variety).
		if (node as Player).alive and node != world.local_player:
			list.append(node as Player)
	list.shuffle()
	return list


## Moves up to `count` other living players in front of `p` (with line of sight
## and ground at about the same height), facing it. Returns the moved players.
func _stage(p: Player, count: int, distance: float) -> Array[Player]:
	var moved: Array[Player] = []
	var space := world.get_world_3d().direct_space_state
	var fwd := -p.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var eye := p.global_position + Vector3.UP * 1.5
	for node in world.players.get_children():
		var e := node as Player
		if moved.size() >= count:
			break
		# The POV player is never cast as a victim: it must be alive for its
		# first-person shots.
		if e == p or not e.alive or e == world.local_player:
			continue
		for attempt in 10:
			var dir := fwd.rotated(Vector3.UP, randf_range(-0.45, 0.45))
			var spot := p.global_position + dir * (distance + randf_range(-1.5, 3.0))
			var down := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 4.0, 1)
			var ground := space.intersect_ray(down)
			if ground.is_empty() or absf(ground.position.y - p.global_position.y) > 1.2:
				continue
			var feet: Vector3 = ground.position
			var los := PhysicsRayQueryParameters3D.create(eye, feet + Vector3.UP * 1.5, 1)
			if not space.intersect_ray(los).is_empty():
				continue
			# Room for the body.
			var up := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.2, feet + Vector3.UP * 2.0, 1)
			if not space.intersect_ray(up).is_empty():
				continue
			e.global_position = feet + Vector3.UP * 0.05
			e.velocity = Vector3.ZERO
			var to := p.global_position - feet
			e.rotation.y = atan2(-to.x, -to.z)
			moved.append(e)
			break
	if not moved.is_empty():
		var to := moved[0].global_position - p.global_position
		p.rotation.y = atan2(-to.x, -to.z)
	return moved


## Grenade shot: the subject draws a grenade and throws it at the enemy.
func _throw_grenade() -> void:
	if _target == null or not _target.alive:
		return
	if _foe and _foe.alive:
		var to := _foe.global_position - _target.global_position
		_target.rotation.y = atan2(-to.x, -to.z)
		_target.pitch = 0.0
	var w := _target.weapons
	w.equip(WeaponDB.GRENADE, false, true)
	w.ammo[WeaponDB.GRENADE][0] = 1
	w.cooldown = 0.0
	w.draw = 1.0
	w.try_fire()


## After showing a subject fall for a moment, moves on to the nearest living
## player (usually whoever won the fight) without restarting the shot timing.
func _follow_action(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.alive:
		_dead_t = 0.0
		return
	_dead_t += delta
	if _dead_t < 0.7:
		return
	var best: Player = null
	var best_d := 1e9
	for node in world.players.get_children():
		var p := node as Player
		if p.alive and p != _target:
			var d := p.global_position.distance_to(_target.global_position)
			if d < best_d:
				best_d = d
				best = p
	if best:
		_target = best
		_dead_t = 0.0
		_update_camera(0.0, true)


## Prefers a living player who fired recently and has an enemy nearby.
func _pick_target() -> Player:
	var now := _clock
	var best: Player = null
	var best_score := -1e9
	for node in world.players.get_children():
		var p := node as Player
		if not p.alive:
			continue
		var score := randf() * 0.5 + p.hp / 100.0
		var fired: float = _last_fire.get(p.pid, -100.0)
		score += clampf(3.0 - (now - fired), 0.0, 3.0)
		for other in world.players.get_children():
			if other != p and (other as Player).alive:
				var d := p.global_position.distance_to((other as Player).global_position)
				if d < 25.0:
					score += 0.6
		if score > best_score:
			best_score = score
			best = p
	return best


func _update_camera(delta: float, snap: bool) -> void:
	var pos: Vector3
	var look: Vector3
	var t := _shot_t
	if _shot_type == "fly" or _target == null or not is_instance_valid(_target):
		var a := _shot_seed + t * 0.06
		var r := 46.0 - t * 1.2
		pos = Vector3(sin(a) * r, 24.0 - t * 0.6, cos(a) * r)
		look = Vector3(0, 2.0, 0)
	else:
		var p := _target.global_position
		var fwd := -_target.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var right := fwd.cross(Vector3.UP)
		if _shot_type == "pov":
			_pov_camera(p, fwd, right, delta, snap)
			return
		if snap:
			# Pick the side of the subject with a clear view (once per shot,
			# so the camera never flips mid-shot).
			_side = 1.0
			var a := _frame(p, fwd, right, t, 1.0)
			var b := _frame(p, fwd, right, t, -1.0)
			if not _clear(a) and _clear(b):
				_side = -1.0
		var f := _frame(p, fwd, right, t, _side)
		pos = _avoid_walls(f[2], f[0])
		look = f[1]
	var k := 1.0 if snap else 1.0 - exp(-7.0 * delta)
	_cam.global_position = _cam.global_position.lerp(pos, k)
	var dir := look - _cam.global_position
	if dir.length() < 0.01 or absf(dir.normalized().y) > 0.995:
		return
	var basis := Basis.looking_at(dir, Vector3.UP)
	_cam.global_basis = basis if snap else Basis(_cam.global_basis.get_rotation_quaternion().slerp(basis.get_rotation_quaternion(), minf(1.0, k * 1.2)))


## Camera position, look target and wall-check anchor for the current shot.
## `side` mirrors the framing to the subject's left (-1) or right (+1).
func _frame(p: Vector3, fwd: Vector3, right: Vector3, t: float, side: float) -> Array:
	var r := right * side
	match _shot_type:
		"chase":
			return [p - fwd * 3.4 + r * 0.95 + Vector3.UP * 2.05, p + fwd * 8.0 + Vector3.UP * 1.3, p + Vector3.UP * 1.5]
		"orbit":
			var a := _shot_seed + t * 0.38 * side
			return [p + Vector3(sin(a) * 4.6, 2.1, cos(a) * 4.6), p + Vector3.UP * 1.25, p + Vector3.UP * 1.5]
		"hero":
			return [p + fwd * 3.2 + r * (0.8 + t * 0.12) + Vector3.UP * 1.25, p + Vector3.UP * 1.45, p + Vector3.UP * 1.5]
		"grenade":
			# Wide side view framing thrower and enemy, slowly pushing in.
			var other := _foe.global_position if _foe and is_instance_valid(_foe) else p + fwd * 12.0
			var mid := (p + other) * 0.5
			var span := maxf(p.distance_to(other), 6.0)
			var along := (other - p).normalized()
			var sd := along.cross(Vector3.UP) * side
			var pos := mid + sd * (span * 0.75 + 2.5 - t * 0.35) + Vector3.UP * (2.6 + span * 0.08) - along * 1.5
			return [pos, mid + Vector3.UP * 0.9, mid + Vector3.UP * 1.2]
		"low":
			return [p + r * 2.8 - fwd * (1.5 - t * 0.5) + Vector3.UP * 0.45, p + fwd * 2.0 + Vector3.UP * 1.5, p + Vector3.UP * 1.5]
	return [p + Vector3(0, 3, 4), p, p + Vector3.UP * 1.5]


## True when nothing solid sits between the camera and its subject.
func _clear(frame: Array) -> bool:
	var space := world.get_world_3d().direct_space_state
	var a := PhysicsRayQueryParameters3D.create(frame[2], frame[0], 1)
	var b := PhysicsRayQueryParameters3D.create(frame[0], frame[1], 1)
	return space.intersect_ray(a).is_empty() and space.intersect_ray(b).is_empty()


## POV shot: over-the-shoulder for a moment, a quick dive into the head, then
## the subject's own first-person view.
func _pov_camera(p: Vector3, fwd: Vector3, right: Vector3, delta: float, snap: bool) -> void:
	var t := _shot_t
	if _pov_on:
		return
	if t < POV_OUTSIDE:
		var pos := _avoid_walls(p + Vector3.UP * 1.5, p - fwd * 3.0 + right * 0.9 + Vector3.UP * 2.0)
		var look := p + fwd * 8.0 + Vector3.UP * 1.3
		var k := 1.0 if snap else 1.0 - exp(-8.0 * delta)
		_cam.global_position = _cam.global_position.lerp(pos, k)
		var dir := look - _cam.global_position
		if dir.length() > 0.01:
			var b := Basis.looking_at(dir, Vector3.UP)
			_cam.global_basis = b if snap else Basis(_cam.global_basis.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), k))
		_dive_from = _cam.global_transform
		_dive_fov = _cam.fov
		return
	var x := clampf((t - POV_OUTSIDE) / POV_DIVE, 0.0, 1.0)
	var e := x * x * x  # ease in: accelerates into the head
	var eye := _target.camera.global_transform
	_cam.global_position = _dive_from.origin.lerp(eye.origin, e)
	_cam.global_basis = Basis(_dive_from.basis.get_rotation_quaternion().slerp(eye.basis.get_rotation_quaternion(), e))
	_cam.fov = lerpf(_dive_fov, _target.camera.fov, e)
	# Past halfway the camera would cross the subject's own head: hide its body
	# (layer 2 is the local player's body, which its own camera never draws).
	_cam.cull_mask = 1 if x > 0.45 else 1 | 2
	if x >= 1.0:
		_set_pov(true)


## Switches between the director camera (no HUD) and the subject's
## first-person view (with the game HUD). The letterbox stays on in both.
func _set_pov(on: bool) -> void:
	if on == _pov_on:
		return
	_pov_on = on
	if on:
		_fit_hud_in_frame()
	if not on:
		_cam.make_current()


## Squeezes the game HUD into the area between the letterbox bars, so the
## timer, health and ammo stay visible in the first-person shots.
func _fit_hud_in_frame() -> void:
	var root := world.hud.get_node_or_null("Root") as Control
	if root == null:
		return
	var bar_h := (1.0 - (16.0 / 9.0) / CINEMA_ASPECT) / 2.0
	root.anchor_top = bar_h
	root.anchor_bottom = 1.0 - bar_h
	root.offset_top = 0.0
	root.offset_bottom = 0.0


## Keeps the camera on the near side of walls between it and the subject.
func _avoid_walls(anchor: Vector3, wanted: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(anchor, wanted, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return wanted
	return hit.position + (anchor - wanted).normalized() * 0.35


# ------------------------------------------------------------------ overlay

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ui_vignette.gdshader")
	mat.set_shader_parameter("strength", 0.6)
	vignette.material = mat
	root.add_child(vignette)

	# Letterbox bars for a 2.35:1 frame.
	var bar_h := (1.0 - (16.0 / 9.0) / CINEMA_ASPECT) / 2.0
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - bar_h
		bar.anchor_bottom = bar_h if top else 1.0
		root.add_child(bar)
		_bars.append(bar)

	_caption_box = Control.new()
	_caption_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_caption_box)
	_logo_box = Control.new()
	_logo_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_logo_box)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)
	_cards_box = Control.new()
	_cards_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_cards_box)


func _fade_in() -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _seg().has("logo"):
		# The closing card ends on black.
		t.tween_interval(float(_seg().length) - 0.7 - 1.6)
		t.tween_property(_fade, "color:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _label(text: String, variation: StringName, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_outline_size", 10)
	return l


func _schedule_caption(at: float, duration: float, eyebrow: String, title: String) -> void:
	get_tree().create_timer(at).timeout.connect(_show_caption.bind(duration, eyebrow, title))


## Lower-left caption: accent line grows, eyebrow and title slide in, then
## everything slides out to the left.
func _show_caption(duration: float, eyebrow: String, title: String) -> void:
	var vp := _caption_box.size
	var bar_px := vp.y * (1.0 - (16.0 / 9.0) / CINEMA_ASPECT) / 2.0
	var box := Control.new()
	box.position = Vector2(vp.x * 0.065, vp.y - bar_px - vp.y * 0.235)
	_caption_box.add_child(box)
	var s := vp.y / 1080.0

	var line := ColorRect.new()
	line.color = ACCENT
	line.size = Vector2(0, 4 * s)
	box.add_child(line)
	var eb := _label(eyebrow, &"Caption", int(26 * s), ACCENT)
	eb.position = Vector2(0, 16 * s)
	eb.modulate.a = 0.0
	box.add_child(eb)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(0, 50 * s)
	clip.size = Vector2(vp.x * 0.8, 120 * s)
	box.add_child(clip)
	var ti := _label(title, &"HeroLabel", int(92 * s), TEXT)
	ti.position = Vector2(0, 120 * s)
	clip.add_child(ti)

	var t := create_tween()
	t.tween_property(line, "size:x", 96 * s, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(eb, "modulate:a", 1.0, 0.4).set_delay(0.1)
	t.parallel().tween_property(eb, "position:x", 0.0, 0.5).from(-24 * s).set_delay(0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(ti, "position:y", 0.0, 0.6).set_delay(0.18) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_interval(maxf(0.0, duration - 1.2))
	t.tween_property(box, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(box, "position:x", box.position.x - 40 * s, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(box.queue_free)


## Title card on black: small eyebrow, large line and small footer, centered.
## The large line rises into place while the letters fade in; everything
## fades out before the next card.
func _show_card(eyebrow: String, title: String, footer: String, duration: float) -> void:
	var vp := _cards_box.size
	var s := vp.y / 1080.0
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", int(10 * s))
	_cards_box.add_child(col)
	var parts: Array[Control] = []
	if eyebrow != "":
		var eb := _label(eyebrow, &"Caption", int(26 * s), ACCENT)
		eb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(eb)
		parts.append(eb)
	var big := _label(title, &"HeroLabel", int(84 * s), TEXT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(big)
	parts.append(big)
	var line_holder := CenterContainer.new()
	col.add_child(line_holder)
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(0, 3 * s)
	line_holder.add_child(line)
	if footer != "":
		var ft := _label(footer, &"Caption", int(26 * s), ACCENT)
		ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(ft)
		parts.append(ft)
	for c in parts:
		c.modulate.a = 0.0
	await get_tree().process_frame
	big.pivot_offset = big.size / 2.0
	big.scale = Vector2(1.06, 1.06)
	var t := create_tween().set_parallel()
	var delay := 0.0
	for c in parts:
		t.tween_property(c, "modulate:a", 1.0, 0.6).set_delay(delay).set_trans(Tween.TRANS_SINE)
		delay += 0.15
	t.tween_property(big, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(line, "custom_minimum_size:x", 140 * s, 0.7).set_delay(0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(0.0)
	var out := create_tween()
	out.tween_interval(maxf(0.0, duration - 0.45))
	out.tween_property(col, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	out.tween_callback(col.queue_free)


## Closing card: the logo settles from a slight zoom, an accent line draws
## under it, then the tagline and the credits fade in.
func _show_logo() -> void:
	var vp := _logo_box.size
	var s := vp.y / 1080.0
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.035, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo_box.add_child(dim)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", int(14 * s))
	_logo_box.add_child(col)

	var logo := _label("OPENSHOOTER", &"HeroLabel", int(170 * s), TEXT)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(logo)
	var line_holder := CenterContainer.new()
	col.add_child(line_holder)
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(0, 5 * s)
	line_holder.add_child(line)
	var tag := _label("Free and open-source LAN shooter", &"SubtitleLabel", int(34 * s), TEXT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var credit := _label("RL PROJECTS  ·  BUILT WITH GODOT 4  ·  GPL-3.0", &"Caption", int(22 * s), ACCENT)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(credit)

	# Platform row: reserved in the layout from the start (so the logo does
	# not jump), revealed a few seconds after the logo.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 34 * s)
	col.add_child(gap)
	var avail := _label("AVAILABLE ON", &"Caption", int(24 * s), ACCENT)
	avail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(avail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(64 * s))
	col.add_child(row)
	var items: Array[Control] = []
	for entry in PLATFORMS:
		var item := VBoxContainer.new()
		item.alignment = BoxContainer.ALIGNMENT_CENTER
		item.add_theme_constant_override("separation", int(10 * s))
		var icon := TextureRect.new()
		icon.texture = load(entry[1])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(64, 64) * s
		item.add_child(icon)
		var caption := _label(entry[0], &"SubtitleLabel", int(26 * s), TEXT)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.add_child(caption)
		row.add_child(item)
		items.append(item)
	for c in [logo, tag, credit, avail] + items:
		c.modulate.a = 0.0

	await get_tree().process_frame
	logo.pivot_offset = logo.size / 2.0
	logo.scale = Vector2(1.12, 1.12)
	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.55, 1.2)
	t.tween_property(logo, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	t.tween_property(logo, "scale", Vector2.ONE, 2.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(line, "custom_minimum_size:x", 420 * s, 0.9).set_delay(0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(tag, "modulate:a", 1.0, 0.8).set_delay(1.1)
	t.tween_property(credit, "modulate:a", 1.0, 0.8).set_delay(1.6)

	var at := float(_seg().get("platforms", 4.0))
	t.tween_property(avail, "modulate:a", 1.0, 0.6).set_delay(at)
	for i in items.size():
		var it := items[i]
		it.pivot_offset = it.size / 2.0
		it.scale = Vector2(0.85, 0.85)
		var d := at + 0.35 + i * 0.16
		t.tween_property(it, "modulate:a", 1.0, 0.5).set_delay(d).set_trans(Tween.TRANS_SINE)
		t.tween_property(it, "scale", Vector2.ONE, 0.7).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
