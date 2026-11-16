class_name ModeDB
## Game mode list. The index travels over the network (voting and match state).
## To create a mode: add a new .tres in resources/modes (GameModeData) and list
## it here.

const ALL: Array[GameModeData] = [
	preload("res://resources/modes/normal.tres"),
	preload("res://resources/modes/duel.tres"),
	preload("res://resources/modes/semi_auto.tres"),
	preload("res://resources/modes/knives.tres"),
	preload("res://resources/modes/gun_game.tres"),
]


static func count() -> int:
	return ALL.size()


static func get_mode(idx: int) -> GameModeData:
	return ALL[clampi(idx, 0, ALL.size() - 1)]
