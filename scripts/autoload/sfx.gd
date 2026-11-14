extends Node
## Sons do jogo. Aceita o nome de um arquivo em res://audio (sem extensão) ou um
## AudioStream (por exemplo o som de tiro definido no [WeaponData]).

const AUDIO_DIR := "res://audio/%s.wav"

var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_stream(sound: Variant) -> AudioStream:
	if sound is AudioStream:
		return sound
	var key := str(sound)
	if not _cache.has(key):
		var path := AUDIO_DIR % key
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _cache[key]


## Som "na cabeça" do jogador (interface, próprios tiros).
func play(sound: Variant, volume_db := 0.0, pitch := 1.0) -> void:
	var s := get_stream(sound)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = &"Master"
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Som posicionado no mundo 3D (passos, tiros dos outros, explosões).
func play_at(sound: Variant, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s := get_stream(sound)
	var root := get_tree().current_scene
	if s == null or root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 8.0
	p.max_distance = 120.0
	root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
