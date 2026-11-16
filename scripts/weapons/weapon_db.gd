class_name WeaponDB
## Weapon list in slot order (key 1 = index 0). The index is what travels over
## the network, so every player needs the same list.
## To add a weapon: create the .tres in resources/weapons and list it here.

const KNIFE := 0
const PISTOL := 1
const RIFLE := 2
const SHOTGUN := 3
const SNIPER := 4
const MINE := 5
const GRENADE := 6
const POISON := 7
const BARRIER := 8

const ALL: Array[WeaponData] = [
	preload("res://resources/weapons/knife.tres"),
	preload("res://resources/weapons/pistol.tres"),
	preload("res://resources/weapons/ak47.tres"),
	preload("res://resources/weapons/shotgun.tres"),
	preload("res://resources/weapons/sniper.tres"),
	preload("res://resources/weapons/mine.tres"),
	preload("res://resources/weapons/grenade.tres"),
	preload("res://resources/weapons/poison.tres"),
	preload("res://resources/weapons/barrier.tres"),
]

## Weapons randomly given to bots.
const BOT_CHOICES := [PISTOL, RIFLE, RIFLE, SHOTGUN, SNIPER]


static func get_data(idx: int) -> WeaponData:
	return ALL[clampi(idx, 0, ALL.size() - 1)]


static func count() -> int:
	return ALL.size()


static func index_of(w: WeaponData) -> int:
	for i in ALL.size():
		if ALL[i].resource_path == w.resource_path:
			return i
	return 0
