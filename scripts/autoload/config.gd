extends Node
## Preferências do jogador, qualidade gráfica e estatísticas (user://config.cfg).
## Os controles ficam em Projeto → Configurações do Projeto → Mapa de Entrada.

signal changed

const PATH := "user://config.cfg"

enum Quality { LOW, MEDIUM, HIGH }

var player_name := ""
var sensitivity := 0.25
var fov := 80.0
var volume := 0.8
var fullscreen := false
var quality: int = Quality.MEDIUM
var show_fps := false
var shirt := Color(0.2, 0.45, 0.85)
var pants := Color(0.18, 0.18, 0.22)
var skin := Color(0.96, 0.8, 0.64)
var stats := {"kills": 0, "deaths": 0, "matches": 0, "wins": 0, "headshots": 0}
## Falso nas execuções de teste (--host, --name, --bench...): nada é gravado.
var persist := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_cfg()
	apply()


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		player_name = c.get_value("player", "name", "")
		sensitivity = c.get_value("player", "sensitivity", sensitivity)
		fov = c.get_value("player", "fov", fov)
		volume = c.get_value("player", "volume", volume)
		fullscreen = c.get_value("player", "fullscreen", fullscreen)
		quality = c.get_value("player", "quality", quality)
		show_fps = c.get_value("player", "show_fps", show_fps)
		shirt = c.get_value("look", "shirt", shirt)
		pants = c.get_value("look", "pants", pants)
		skin = c.get_value("look", "skin", skin)
		stats.merge(c.get_value("stats", "all", {}), true)
	if player_name == "":
		player_name = "Jogador%d" % (randi() % 9000 + 1000)


func save_cfg() -> void:
	if not persist:
		changed.emit()
		return
	var c := ConfigFile.new()
	for key in ["name", "sensitivity", "fov", "volume", "fullscreen", "quality", "show_fps"]:
		c.set_value("player", key, player_name if key == "name" else get(key))
	for key in ["shirt", "pants", "skin"]:
		c.set_value("look", key, get(key))
	c.set_value("stats", "all", stats)
	c.save(PATH)
	changed.emit()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Ajusta o custo gráfico de um mapa conforme a qualidade escolhida.
func apply_quality(sun: DirectionalLight3D, env: Environment, vp: Viewport) -> void:
	if sun:
		sun.shadow_enabled = quality >= Quality.MEDIUM
		sun.directional_shadow_max_distance = 25.0 if quality == Quality.MEDIUM else 45.0
	if env:
		env.fog_enabled = quality >= Quality.MEDIUM
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = [0.6, 0.8, 1.0][clampi(quality, 0, 2)]
		vp.msaa_3d = Viewport.MSAA_2X if quality >= Quality.HIGH else Viewport.MSAA_DISABLED


## Dados enviados ao servidor ao entrar numa partida.
func profile() -> Dictionary:
	return {"name": player_name.substr(0, 20), "shirt": shirt, "pants": pants, "skin": skin}


func add_stat(key: String, amount := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount
	save_cfg()
