class_name WeaponDB
## Lista de armas na ordem dos slots (tecla 1 = índice 0). O índice é o que viaja
## pela rede, então todos os jogadores precisam da mesma lista.
## Para adicionar uma arma: crie o .tres em resources/weapons e coloque-o aqui.

const KNIFE := 0
const PISTOL := 1
const RIFLE := 2
const SHOTGUN := 3
const SNIPER := 4
const MINE := 5

const ALL: Array[WeaponData] = [
	preload("res://resources/weapons/faca.tres"),
	preload("res://resources/weapons/pistola.tres"),
	preload("res://resources/weapons/ak47.tres"),
	preload("res://resources/weapons/escopeta.tres"),
	preload("res://resources/weapons/fuzil.tres"),
	preload("res://resources/weapons/mina.tres"),
]

## Armas sorteadas para os bots.
const BOT_CHOICES := [PISTOL, RIFLE, RIFLE, SHOTGUN, SNIPER]


static func get_data(idx: int) -> WeaponData:
	return ALL[clampi(idx, 0, ALL.size() - 1)]


static func count() -> int:
	return ALL.size()
