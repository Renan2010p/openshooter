class_name MainMenu
extends Node3D
## Menu principal — scenes/ui/main_menu.tscn. O mapa gira ao fundo e cada tela
## é uma cena separada em scenes/ui/screens/ (filhas de %Screens).

signal host_requested(info: Dictionary)
signal join_requested(ip: String, code: String)
signal quit_requested

const AVATAR_SCENE := preload("res://scenes/player/avatar.tscn")

@export_group("Câmera do fundo")
@export var orbit_radius := 30.0
@export var orbit_height := 12.0
@export var orbit_speed := 0.05
@export var locker_camera := Vector3(-1.6, 1.5, 23.2)
@export var locker_target := Vector3(-1.75, 1.1, 18.0)

## Mensagem mostrada ao abrir (ex.: "A conexão com o servidor caiu.").
var message := ""

@onready var camera: Camera3D = $Camera
@onready var avatar_preview: Node3D = $AvatarPreview
@onready var screens: Control = %Screens
@onready var status_label: Label = %Status

var _current: MenuScreen
var _avatar: Avatar
var _t := 0.0


func _ready() -> void:
	# Um mapa diferente de fundo a cada vez que o menu abre.
	var map := MapDB.instantiate(MapDB.random_index())
	add_child(map)
	move_child(map, 0)
	for s in screens.get_children():
		if s is MenuScreen:
			s.menu = self
			s.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.start_listening()
	set_status(message)
	rebuild_avatar()
	show_screen("Home")


func _exit_tree() -> void:
	Net.stop_listening()


## Mostra uma tela pelo nome do nó (Home, Modes, Browser, Private, Create,
## Locker, Settings, Stats). `arg` é repassado para MenuScreen.enter().
func show_screen(screen_name: String, arg: Variant = null) -> void:
	if _current:
		_current.leave()
		_current.visible = false
	_current = screens.get_node(screen_name) as MenuScreen
	_current.visible = true
	_current.enter(arg)


func current_screen() -> String:
	return _current.name if _current else ""


func set_status(text: String, ok := false) -> void:
	status_label.text = text
	status_label.theme_type_variation = &"StatusOk" if ok else &"StatusError"


func request_host(info: Dictionary) -> void:
	host_requested.emit(info)


func request_join(ip: String, code := "") -> void:
	set_status("Conectando a %s..." % ip, true)
	join_requested.emit(ip, code)


func request_quit() -> void:
	quit_requested.emit()


## Recria o boneco do Armário com as cores atuais.
func rebuild_avatar() -> void:
	for c in avatar_preview.get_children():
		c.queue_free()
	var a: Avatar = AVATAR_SCENE.instantiate()
	avatar_preview.add_child(a)
	a.setup(Config.shirt, Config.pants, Config.skin)
	_avatar = a
	a.hand.add_child(WeaponDB.get_data(WeaponDB.RIFLE).model.instantiate())


func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_avatar):
		_avatar.idle_preview(delta)
	if current_screen() == "Locker":
		camera.global_position = camera.global_position.lerp(locker_camera, minf(1.0, delta * 3.0))
		camera.look_at(locker_target)
		avatar_preview.rotation.y += delta * 0.6
	else:
		var a := _t * orbit_speed
		camera.global_position = Vector3(sin(a) * orbit_radius, orbit_height, cos(a) * orbit_radius)
		camera.look_at(Vector3(0, 1, 0))
