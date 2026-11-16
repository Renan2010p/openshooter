class_name GameModeData
extends Resource
## Rules for a game mode (resources/modes/*.tres), editable in the Inspector.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
## Available weapons and equipment, in the order of keys 1..9.
@export var loadout: Array[WeaponData] = []
## Weapon the player holds on spawn (must be part of the loadout).
@export var start_weapon: WeaponData
## Any hit eliminates.
@export var one_hit_kill := false
## Seconds to regain one unit of each equipment item (0 = never).
@export var equipment_refill_seconds := 0.0

@export_group("Gun Game")
## When not empty, this is Gun Game: every kill advances to the next weapon in
## this list; a kill with the last one wins the match.
@export var progression: Array[WeaponData] = []
## Items that come along with the current weapon (for example a grenade).
@export var progression_extras: Array[WeaponData] = []


func is_gun_game() -> bool:
	return not progression.is_empty()


## WeaponDB indices the player owns. `level` only matters in Gun Game.
func loadout_for(level: int) -> Array[int]:
	var out: Array[int] = []
	if is_gun_game():
		out.append(WeaponDB.index_of(progression[clampi(level, 0, progression.size() - 1)]))
		for w in progression_extras:
			out.append(WeaponDB.index_of(w))
	else:
		for w in loadout:
			out.append(WeaponDB.index_of(w))
	return out


func start_index(level: int) -> int:
	if is_gun_game():
		return WeaponDB.index_of(progression[clampi(level, 0, progression.size() - 1)])
	return WeaponDB.index_of(start_weapon) if start_weapon else loadout_for(level)[0]
