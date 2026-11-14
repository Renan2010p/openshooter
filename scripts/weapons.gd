class_name Weapons
## Tabela de armas. O índice na lista é o número do slot (1..6).

const KNIFE := 0
const PISTOL := 1
const RIFLE := 2
const SHOTGUN := 3
const SNIPER := 4
const MINE := 5

const LIST := [
	{"id": "faca", "name": "Faca", "melee": true, "damage": 55, "head": 1.0, "rate": 0.45, "range": 2.6, "mag": 0, "reserve": 0, "sound": "knife"},
	{"id": "pistola", "name": "Pistola", "damage": 26, "head": 2.0, "rate": 0.2, "auto": false, "mag": 12, "reserve": 48, "reload": 1.3, "spread": 0.008, "pellets": 1, "range": 120.0, "recoil": 0.014, "sound": "shot_pistol"},
	{"id": "ak47", "name": "AK-47", "damage": 22, "head": 2.2, "rate": 0.1, "auto": true, "mag": 30, "reserve": 90, "reload": 2.2, "spread": 0.012, "pellets": 1, "range": 150.0, "recoil": 0.02, "sound": "shot_ak"},
	{"id": "escopeta", "name": "Escopeta", "damage": 13, "head": 1.5, "rate": 0.85, "auto": false, "mag": 6, "reserve": 24, "reload": 2.4, "spread": 0.065, "pellets": 9, "range": 45.0, "recoil": 0.06, "sound": "shot_shotgun"},
	{"id": "fuzil", "name": "Fuzil", "damage": 80, "head": 2.0, "rate": 1.25, "auto": false, "mag": 5, "reserve": 20, "reload": 2.8, "spread": 0.06, "scope": true, "pellets": 1, "range": 300.0, "recoil": 0.09, "sound": "shot_sniper"},
	{"id": "mina", "name": "Mina", "mine": true, "rate": 0.8, "mag": 2, "reserve": 0, "sound": "beep"},
]


static func get_w(idx: int) -> Dictionary:
	return LIST[clampi(idx, 0, LIST.size() - 1)]
