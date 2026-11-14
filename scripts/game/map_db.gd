class_name MapDB
## Lista de mapas. O índice viaja pela rede (server_info.map), então todos os
## jogadores precisam da mesma lista. Para adicionar um mapa: crie a cena em
## scenes/maps/ (raiz com o script GameMap) e coloque-a aqui.

const MAPS := [
	{"id": "bairro", "name": "Bairro", "scene": "res://scenes/maps/bairro.tscn",
		"description": "Casas, galpão com telhado e ruas abertas."},
	{"id": "porto", "name": "Porto", "scene": "res://scenes/maps/porto.tscn",
		"description": "Labirinto de contêineres no pôr do sol."},
	{"id": "deserto", "name": "Vila do Deserto", "scene": "res://scenes/maps/deserto.tscn",
		"description": "Casas de adobe, feira e telhados para atiradores."},
	{"id": "artico", "name": "Base Ártica", "scene": "res://scenes/maps/artico.tscn",
		"description": "Bunkers, torre de vigia e neblina."},
]

## Valor de "map" que significa sortear um mapa.
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
