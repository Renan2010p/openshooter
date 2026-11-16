class_name WeaponHolder
extends Node
## A player's weapons: which ones they have (defined by the game mode), ammo,
## switching, firing, throwing, reloading, scoping and models (weapon in the
## character's hands and first-person weapon).

signal weapon_changed(index: int)
## The weapon list changed (new mode or Gun Game level).
signal loadout_changed(loadout: Array[int])

## Seconds to draw a weapon.
const DRAW_TIME := 0.35

var player: Player
var index := WeaponDB.RIFLE
## WeaponDB indices the player owns, in the order of keys 1..9.
var loadout: Array[int] = []
## Ammo per weapon: [magazine, reserve].
var ammo: Array = []
var cooldown := 0.0
var reload_left := 0.0
var scoped := false
## Aiming down sights (right mouse button). With a scope, `scoped` is also true.
var aiming := false
var kick := 0.0
var swing := 0.0
## 0 right after switching weapons, 1 when the weapon is ready (draw animation).
var draw := 1.0
## Seconds to regain one equipment item (defined by the mode).
var equipment_refill := 0.0

var _world_model: BakedModel
var _view_model: Node3D
var _refill_t := 0.0


func setup(p: Player) -> void:
	player = p
	refill()


func data() -> WeaponData:
	return WeaponDB.get_data(index)


## Replaces the available weapons and draws `start`.
func set_loadout(list: Array[int], start: int, refill_seconds := 0.0) -> void:
	loadout = list
	equipment_refill = refill_seconds
	refill()
	if not loadout.has(start):
		start = loadout[0] if not loadout.is_empty() else WeaponDB.KNIFE
	equip(start, false, true)
	loadout_changed.emit(loadout)


func refill() -> void:
	ammo.clear()
	for w in WeaponDB.ALL:
		ammo.append([w.magazine if not w.is_melee() else 0, w.reserve])


func mag() -> int:
	return ammo[index][0]


func reserve() -> int:
	return ammo[index][1]


func is_reloading() -> bool:
	return reload_left > 0.0


func has_weapon(idx: int) -> bool:
	return loadout.is_empty() or loadout.has(idx)


## Draws a weapon. Weapons outside the mode loadout are ignored (unless `force`
## is used by the network: whoever sends the position also sends the weapon).
func equip(idx: int, sound := true, force := false) -> void:
	if not force and not has_weapon(idx):
		return
	index = clampi(idx, 0, WeaponDB.count() - 1)
	scoped = false
	aiming = false
	reload_left = 0.0
	cooldown = maxf(cooldown, DRAW_TIME)
	draw = 0.0
	_build_models()
	if sound and player.local:
		Sfx.play("switch", -6.0)
	weapon_changed.emit(index)


## Key 1..9: position in the mode loadout.
func equip_slot(slot: int) -> void:
	if slot < loadout.size():
		equip(loadout[slot])


func cycle(step: int) -> void:
	if loadout.is_empty():
		return
	var i := loadout.find(index)
	equip(loadout[posmod(i + step, loadout.size())])


func _build_models() -> void:
	var w := data()
	if _world_model:
		_world_model.queue_free()
	_world_model = w.model.instantiate()
	player.avatar.hand.add_child(_world_model)
	# The character's left hand looks for the foregrip of two-handed weapons.
	player.avatar.foregrip = _world_model.get_node_or_null("Foregrip") if w.two_handed else null
	if player.local:
		_world_model.set_render_layer(2)
		if _view_model:
			_view_model.queue_free()
		_view_model = Node3D.new()
		_view_model.name = "Held"
		player.view_model.add_child(_view_model)
		var gun: BakedModel = w.model.instantiate()
		gun.cast_shadows = false
		_view_model.add_child(gun)
		gun.set_render_layer(4)
		var arms := preload("res://scenes/player/view_arms.tscn").instantiate()
		_view_model.add_child(arms)
		for b in BlockBaker.collect(arms):
			if b.tint == Block.Tint.SKIN:
				b.color = player.info().get("skin", Config.skin)
			elif b.tint == Block.Tint.SHIRT:
				b.color = player.info().get("shirt", Config.shirt)
		# The left hand goes to the weapon foregrip (Marker3D "Foregrip").
		var left_hand: Node3D = arms.get_node("LeftHand")
		left_hand.visible = w.two_handed
		var grip := gun.get_node_or_null("Foregrip") as Node3D
		if grip:
			left_hand.position = grip.position + Vector3(0, -0.035, 0)
		var mi := BlockBaker.bake(arms)
		if mi:
			mi.layers = 4
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.view_model.scale = Vector3.ONE * w.view_scale


func muzzle_position() -> Vector3:
	if player.local and _view_model and _view_model.get_child_count() > 0:
		return (_view_model.get_child(0) as BakedModel).muzzle_position()
	if _world_model:
		return _world_model.muzzle_position()
	return player.head.global_position


func spread() -> float:
	var w := data()
	var s := w.spread
	if w.has_scope and scoped:
		s = 0.0015
	elif aiming:
		s *= w.ads_spread
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	if hv > 1.0:
		s += 0.015 * clampf(hv / Player.WALK, 0.0, 1.5)
	if not player.is_on_floor():
		s += 0.04
	if player.crouching:
		s *= 0.6
	return s


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	kick = maxf(0.0, kick - delta * 8.0)
	swing = maxf(0.0, swing - delta * 4.0)
	draw = minf(1.0, draw + delta / DRAW_TIME)
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			var w := data()
			var a: Array = ammo[index]
			var take := mini(w.magazine - a[0], a[1])
			a[0] += take
			a[1] -= take
	# Modes with equipment refill: items come back over time.
	if equipment_refill > 0.0:
		_refill_t += delta
		if _refill_t >= equipment_refill:
			_refill_t = 0.0
			for i in loadout:
				var w := WeaponDB.get_data(i)
				if w.is_equipment() and ammo[i][0] < w.magazine:
					ammo[i][0] += 1


func start_reload() -> void:
	var w := data()
	if not w.is_gun() or reload_left > 0.0 or not player.alive:
		return
	if mag() >= w.magazine or reserve() <= 0:
		return
	reload_left = w.reload_time
	scoped = false
	aiming = false
	if player.local:
		Sfx.play("reload", -6.0)


## Tries to fire. `aim_error` is the extra inaccuracy of bots.
func try_fire(aim_error := Vector2.ZERO) -> void:
	var world := player.world
	if not player.alive or cooldown > 0.0 or reload_left > 0.0 or world.match_manager.phase != "play":
		return
	var w := data()
	if w.is_mine():
		_place_mine()
		return
	if w.is_throwable():
		_throw()
		return
	if w.is_gun():
		if mag() <= 0:
			if player.local:
				Sfx.play("empty", -4.0)
			cooldown = 0.25
			start_reload()
			return
		ammo[index][0] -= 1
	cooldown = w.fire_interval
	var head := player.head
	var origin := head.global_position
	var basis := head.global_basis
	var sp := spread()
	var dirs := PackedVector3Array()
	for i in w.pellets:
		var d := -basis.z + basis.x * randf_range(-sp, sp) + basis.y * randf_range(-sp, sp)
		d += basis.x * (aim_error.x + (randf_range(-0.02, 0.02) if aim_error != Vector2.ZERO else 0.0))
		d += basis.y * (aim_error.y + (randf_range(-0.02, 0.02) if aim_error != Vector2.ZERO else 0.0))
		dirs.append(d.normalized())
	play_fire_fx()
	world.combat.fire(player.pid, origin, dirs, index)
	if player.local:
		player.add_recoil(w.recoil)
	if w.is_gun() and mag() <= 0:
		start_reload()


func _out_of(what: String) -> void:
	if player.local:
		player.world.hud.toast("No %s left for now." % what)


func _throw() -> void:
	var w := data()
	if mag() <= 0:
		_out_of(w.display_name.to_lower())
		return
	ammo[index][0] -= 1
	cooldown = w.fire_interval
	swing = 1.0
	var basis := player.head.global_basis
	var origin := player.head.global_position - basis.z * 0.5 + basis.x * 0.15
	var velocity := (-basis.z + Vector3.UP * 0.18).normalized() * w.throw_speed + player.velocity * 0.5
	player.world.throwables.throw(player.pid, index, origin, velocity)
	Sfx.play_at(w.fire_sound, player.head.global_position, -2.0, 0.8)
	_after_equipment_used()


func _place_mine() -> void:
	if mag() <= 0:
		_out_of("mines")
		return
	var from := player.global_position - player.global_basis.z * 1.0 + Vector3.UP
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	var r := player.get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	ammo[index][0] -= 1
	cooldown = data().fire_interval
	player.world.mines.place(player.pid, r.position)
	_after_equipment_used()


## Out of equipment: switch back to the first firearm (or knife) in the loadout.
func _after_equipment_used() -> void:
	if mag() > 0 or equipment_refill > 0.0:
		return
	for i in loadout:
		if not WeaponDB.get_data(i).is_equipment():
			equip.call_deferred(i)
			return


## Weapon sound, muzzle flash and kick. Called locally and, for other players,
## over the network.
func play_fire_fx() -> void:
	var w := data()
	if w.is_melee() or w.is_equipment():
		swing = 1.0
		Sfx.play_at(w.fire_sound, player.head.global_position, -2.0)
		return
	kick = 1.0
	if player.local:
		Sfx.play(w.fire_sound, -3.0, randf_range(0.95, 1.05))
	else:
		Sfx.play_at(w.fire_sound, player.head.global_position, 2.0, randf_range(0.95, 1.05))
	player.muzzle_flash.global_position = muzzle_position()
	player.muzzle_flash.light_energy = 3.0
	player.muzzle_flash.visible = true
