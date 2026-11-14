class_name WeaponData
extends Resource
## Ficha de uma arma. Cada arma é um arquivo .tres em res://resources/weapons/,
## editável no Inspetor (dano, cadência, pente, modelo, som...).

enum Kind { GUN, MELEE, MINE }

@export_group("Identidade")
@export var id := ""
@export var display_name := ""
@export var kind: Kind = Kind.GUN
## Modelo 3D (cena com raiz [BakedModel] e um Marker3D "Muzzle").
@export var model: PackedScene
@export var fire_sound: AudioStream

@export_group("Dano")
@export var damage := 20.0
@export var headshot_multiplier := 2.0
## Alcance máximo do tiro, em metros.
@export var max_range := 100.0
## Dano cai com a distância (escopeta).
@export var damage_falloff := false
## Quantos projéteis por disparo (escopeta > 1).
@export_range(1, 16) var pellets := 1

@export_group("Disparo")
## Segundos entre disparos.
@export var fire_interval := 0.1
@export var automatic := false
## Imprecisão base (0 = perfeito).
@export var spread := 0.01
## Quanto a mira sobe a cada tiro.
@export var recoil := 0.02
@export var has_scope := false
@export var scope_fov := 20.0

@export_group("Munição")
## Balas por pente (para a mina: quantas por vida).
@export var magazine := 30
@export var reserve := 90
@export var reload_time := 2.0

@export_group("Visão em primeira pessoa")
@export var view_position := Vector3(0.2, -0.21, -0.36)
@export var view_scale := 0.7
## Mostra a mão esquerda segurando a arma.
@export var two_handed := false


func is_gun() -> bool:
	return kind == Kind.GUN


func is_melee() -> bool:
	return kind == Kind.MELEE


func is_mine() -> bool:
	return kind == Kind.MINE
