class_name WeaponData
extends Resource
## Data sheet for a weapon. Each weapon is a .tres file in
## res://resources/weapons/, editable in the Inspector (damage, rate of fire,
## magazine, model, sound...).

enum Kind { GUN, MELEE, MINE, THROWABLE }
## Effect of a throwable.
enum ThrowEffect { FRAG, POISON, BARRIER }

@export_group("Identity")
@export var id := ""
@export var display_name := ""
@export var kind: Kind = Kind.GUN
## 3D model (scene whose root is a [BakedModel] with a "Muzzle" Marker3D).
@export var model: PackedScene
@export var fire_sound: AudioStream

@export_group("Damage")
@export var damage := 20.0
@export var headshot_multiplier := 2.0
## Maximum shot range, in meters.
@export var max_range := 100.0
## Damage falls off with distance (shotgun).
@export var damage_falloff := false
## Projectiles per shot (shotgun > 1).
@export_range(1, 16) var pellets := 1

@export_group("Firing")
## Seconds between shots.
@export var fire_interval := 0.1
@export var automatic := false
## Base inaccuracy (0 = perfect).
@export var spread := 0.01
## How much the aim climbs with each shot.
@export var recoil := 0.02
@export var has_scope := false
@export var scope_fov := 20.0

@export_group("Ammo")
## Rounds per magazine (for the mine: how many per life).
@export var magazine := 30
@export var reserve := 90
@export var reload_time := 2.0

@export_group("Throwable")
@export var throw_effect: ThrowEffect = ThrowEffect.FRAG
## Throw speed (m/s).
@export var throw_speed := 16.0
## Seconds until it explodes or activates after being thrown.
@export var fuse := 2.0
## Radius of the explosion or poison cloud (meters).
@export var effect_radius := 6.0
## Duration of the poison cloud or barrier (seconds).
@export var effect_duration := 6.0

@export_group("First-person view")
@export var view_position := Vector3(0.2, -0.21, -0.36)
@export var view_scale := 0.7
## Shows the left hand holding the weapon.
@export var two_handed := false

@export_group("Aim (right mouse button)")
## Weapon position while aiming. To center the sight on screen:
## y = -(sight height in the model) × view_scale, x = 0.
@export var ads_position := Vector3(0, -0.085, -0.25)
## How much the view zooms in while aiming (1 = none, 0.8 = 20% closer).
@export_range(0.3, 1.0) var ads_zoom := 0.8
## Inaccuracy is multiplied by this while aiming.
@export_range(0.0, 1.0) var ads_spread := 0.35


## Firearms can aim down sights with the right mouse button.
func can_aim() -> bool:
	return kind == Kind.GUN


func is_gun() -> bool:
	return kind == Kind.GUN


func is_melee() -> bool:
	return kind == Kind.MELEE


func is_mine() -> bool:
	return kind == Kind.MINE


func is_throwable() -> bool:
	return kind == Kind.THROWABLE


## Mine and throwables: items counted one by one, with no reload.
func is_equipment() -> bool:
	return kind == Kind.MINE or kind == Kind.THROWABLE
