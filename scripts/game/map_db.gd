class_name MapDB
## Map list. The index travels over the network (server_info.map), so every
## player needs the same list. To add a map: create a scene in scenes/maps/
## (root with the GameMap script) and add it here.

const MAPS := [
	{"id": "neighborhood", "name": "Neighborhood", "scene": "res://scenes/maps/neighborhood.tscn",
		"description": "Houses, a warehouse with a roof, and open streets."},
	{"id": "harbor", "name": "Harbor", "scene": "res://scenes/maps/harbor.tscn",
		"description": "A maze of shipping containers at sunset."},
	{"id": "desert", "name": "Desert Village", "scene": "res://scenes/maps/desert.tscn",
		"description": "Adobe houses, a market, and rooftops for snipers."},
	{"id": "arctic", "name": "Arctic Base", "scene": "res://scenes/maps/arctic.tscn",
		"description": "Bunkers, a watchtower, and fog."},
]

## Value of "map" that means "pick a random map".
const RANDOM := -1


static func count() -> int:
	return MAPS.size()


static func info(idx: int) -> Dictionary:
	return MAPS[clampi(idx, 0, MAPS.size() - 1)]


static func display_name(idx: int) -> String:
	return info(idx).name


static func instantiate(idx: int) -> GameMap:
	var scene: PackedScene = load(info(idx).scene)
	var map: GameMap = scene.instantiate()
	map.name = "Map"
	return map


static func random_index() -> int:
	return randi() % MAPS.size()
