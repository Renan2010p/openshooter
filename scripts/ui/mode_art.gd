class_name ModeArt
## Shared visual pieces for game modes: card icons, huge weapon watermarks,
## short rule labels and the little weapon silhouettes of a loadout.

const ICONS := {
	"normal": preload("res://assets/ui/icons/swords.svg"),
	"duel": preload("res://assets/ui/icons/mode_duel.svg"),
	"semi_auto": preload("res://assets/ui/icons/mode_semi.svg"),
	"knives": preload("res://assets/ui/icons/mode_knives.svg"),
	"gun_game": preload("res://assets/ui/icons/mode_gun_game.svg"),
}
const WATERMARKS := {
	"normal": preload("res://assets/ui/weapons/ak47.png"),
	"duel": preload("res://assets/ui/weapons/sniper.png"),
	"semi_auto": preload("res://assets/ui/weapons/pistol.png"),
	"knives": preload("res://assets/ui/weapons/knife.png"),
	"gun_game": preload("res://assets/ui/weapons/pistol.png"),
}
const WEAPON_ICONS := {
	"ak47": preload("res://assets/ui/weapons/ak47.png"),
	"barrier": preload("res://assets/ui/weapons/barrier.png"),
	"grenade": preload("res://assets/ui/weapons/grenade.png"),
	"knife": preload("res://assets/ui/weapons/knife.png"),
	"mine": preload("res://assets/ui/weapons/mine.png"),
	"pistol": preload("res://assets/ui/weapons/pistol.png"),
	"poison": preload("res://assets/ui/weapons/poison.png"),
	"shotgun": preload("res://assets/ui/weapons/shotgun.png"),
	"sniper": preload("res://assets/ui/weapons/sniper.png"),
}


static func icon(mode: GameModeData) -> Texture2D:
	return ICONS.get(mode.id, ICONS["normal"])


static func watermark(mode: GameModeData) -> Texture2D:
	return WATERMARKS.get(mode.id, WATERMARKS["normal"])


## Very short tag shown beside the mode number.
static func rule(mode: GameModeData) -> String:
	if mode.is_gun_game():
		return "%d WEAPONS" % mode.progression.size()
	if mode.id == "knives":
		return "MELEE ONLY"
	if mode.id == "semi_auto":
		return "SEMI-AUTO"
	if mode.one_hit_kill:
		return "ONE HIT"
	return "ALL WEAPONS"


## One line that says what winning means in this mode.
static func hint(mode: GameModeData) -> String:
	if mode.is_gun_game():
		return "NEXT KILL · NEXT WEAPON"
	if mode.id == "knives":
		return "GET CLOSE WITHOUT BEING SEEN"
	if mode.id == "duel":
		return "EVERY HIT IS LETHAL"
	if mode.id == "semi_auto":
		return "PISTOL · SHOTGUN · SNIPER"
	return "MOST ELIMINATIONS WINS"


## Everything the mode gives the player, in slot order.
static func weapons(mode: GameModeData) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	if mode.is_gun_game():
		out.append_array(mode.progression)
		out.append_array(mode.progression_extras)
	else:
		out.append_array(mode.loadout)
	return out


## The first `limit` weapon pictures of the mode (white silhouettes).
static func loadout_icons(mode: GameModeData, limit := 6) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for weapon in weapons(mode):
		if out.size() >= limit:
			break
		var texture: Texture2D = WEAPON_ICONS.get(weapon.id)
		if texture:
			out.append(texture)
	return out
