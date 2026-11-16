extends Node
## Game sounds. Accepts the name of a file in res://audio (without extension)
## or an AudioStream (for example the fire sound set on [WeaponData]).
##
## Players are pooled: automatic weapons and shotguns fire many sounds per
## second, and creating/freeing a node for each one causes frame spikes. When
## every voice is busy, the oldest one is reused (voice stealing).

const AUDIO_DIR := "res://audio/%s.wav"
## Simultaneous non-positional voices (UI, own shots).
const MAX_VOICES := 16
## Simultaneous positional voices (other players, explosions, footsteps).
const MAX_VOICES_3D := 32

var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_3d := 0
## Holder for the 3D voices: lives in the current scene so they hear the active
## camera and are freed with it.
var _holder_3d: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_pool.append(p)


func get_stream(sound: Variant) -> AudioStream:
	if sound is AudioStream:
		return sound
	var key := str(sound)
	if not _cache.has(key):
		var path := AUDIO_DIR % key
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _cache[key]


## Non-positional sound (interface, the local player's own shots).
func play(sound: Variant, volume_db := 0.0, pitch := 1.0) -> void:
	var s := get_stream(sound)
	if s == null:
		return
	var p := _free_voice(_pool, _next)
	_next = (_pool.find(p) + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Sound positioned in the 3D world (footsteps, other players' shots, explosions).
func play_at(sound: Variant, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s := get_stream(sound)
	if s == null or not _ensure_3d():
		return
	var p := _free_voice(_pool_3d, _next_3d) as AudioStreamPlayer3D
	_next_3d = (_pool_3d.find(p) + 1) % _pool_3d.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


## First idle voice starting at `start`; otherwise the one at `start` (oldest in
## round-robin order) is stolen.
func _free_voice(pool: Array, start: int) -> Node:
	var n := pool.size()
	for i in n:
		var p = pool[(start + i) % n]
		if not p.playing:
			return p
	return pool[start % n]


func _ensure_3d() -> bool:
	if is_instance_valid(_holder_3d) and _holder_3d.is_inside_tree():
		return true
	var root := get_tree().current_scene
	if root == null:
		return false
	_pool_3d.clear()
	_next_3d = 0
	_holder_3d = Node3D.new()
	_holder_3d.name = "SfxVoices3D"
	root.add_child(_holder_3d)
	for i in MAX_VOICES_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 120.0
		p.bus = &"Master"
		_holder_3d.add_child(p)
		_pool_3d.append(p)
	return true


## Stops every voice on exit so no playback outlives the engine shutdown.
func _exit_tree() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	for p in _pool_3d:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_cache.clear()
