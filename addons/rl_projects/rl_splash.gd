# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Renan Lucas Vieira Hilário — RL PROJECTS
#
# RL PROJECTS cinematic intro:
#   1. a planetary system, close up (warm star, six lit planets);
#   2. the camera pulls back exponentially — orbits fade, the star becomes a
#      point, neighbouring stars stream past;
#   3. the whole galaxy comes into frame and the camera settles on its core;
#   4. the galaxy glides left and RL PROJECTS slides out from behind it.
# Soundtrack: one of eight variations (brand/tools/rl_audio.py), all synced to
# the same clock; a different one each launch so the intro never gets old.
#
# The same film is rendered by brand/tools/rl_intro.py (GIF/WebP) and by the
# website; all three read the numbers baked into galaxy_data.gd.
#
# Use as a node (emits `finished`, skippable) or via rl_intro.tscn.
class_name RLProjectsSplash
extends Control

signal finished

const Data := preload("res://addons/rl_projects/galaxy_data.gd")
const NEBULA := preload("res://addons/rl_projects/nebula.png")
const PLANET_SHADER := preload("res://addons/rl_projects/rl_planet.gdshader")
const FONT_BOLD := preload("res://addons/rl_projects/fonts/Poppins-Bold.ttf")
const TEXT_CLIP := preload("res://addons/rl_projects/rl_text_clip.gdshader")
const SOUNDTRACKS := {
	"nebula": preload("res://addons/rl_projects/rl_intro.ogg"),
	"aurora": preload("res://addons/rl_projects/rl_intro_aurora.ogg"),
	"cathedral": preload("res://addons/rl_projects/rl_intro_cathedral.ogg"),
	"odyssey": preload("res://addons/rl_projects/rl_intro_odyssey.ogg"),
	"lullaby": preload("res://addons/rl_projects/rl_intro_lullaby.ogg"),
	"abyss": preload("res://addons/rl_projects/rl_intro_abyss.ogg"),
	"dawn": preload("res://addons/rl_projects/rl_intro_dawn.ogg"),
	"horizon": preload("res://addons/rl_projects/rl_intro_horizon.ogg"),
}
const LAST_SOUNDTRACK := "user://rl_projects.cfg"

const WORD := "RL PROJECTS"
const BG := Color(0.02, 0.02, 0.03)
const INK := Color(0.95, 0.96, 1.0)
const SUN := Color(1.0, 0.86, 0.66)
const KINDS := {"rock": 0, "ocean": 1, "gas": 2, "ringed": 3}

## Play automatically when the node enters the tree.
@export var autoplay := true
## Let any key, click, touch or pad button skip to the end.
@export var skippable := true
## Play the intro soundtrack (synced to the picture).
@export var play_sound := true
## Soundtrack: random picks one at random, never the same as last launch.
@export_enum("random", "nebula", "aurora", "cathedral", "odyssey", "lullaby", "abyss", "dawn", "horizon") var soundtrack := "random"
## Audio bus for the soundtrack.
@export var audio_bus := &"Master"

var t := 0.0
var _playing := false
var _fade_from := -1.0
var _done := false

var _gal: PackedVector2Array      # galaxy stars, plane coords
var _gal_e: PackedFloat32Array    # per-star alpha
var _gal_d: PackedFloat32Array    # per-star dot diameter (unscaled)
var _loc: PackedVector2Array      # local stars, offsets from the sun
var _loc_e: PackedFloat32Array
var _loc_d: PackedFloat32Array
var _dot: Texture2D
var _glow: Texture2D
var _disc: Texture2D

var _stars: Control               # additive: stars, galaxy core
var _orbits: Control              # orbit lines
var _sun: Control                 # additive: sun disc + glows
var _text: Control
var _planets: Array[ColorRect] = []
var _audio: AudioStreamPlayer

var _cam := {}                    # per-frame camera state


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_stars()
	_dot = _radial_texture(32)
	_glow = _radial_texture(128)
	_disc = _sun_disc_texture(96)

	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# the wordmark is created first so the galaxy is drawn over it
	var clip := ShaderMaterial.new()
	clip.shader = TEXT_CLIP
	_text = _layer(0, clip)
	_stars = _layer(0, add)
	_orbits = _layer(0, null)
	for p: Array in Data.INTRO.planets:
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = PLANET_SHADER
		m.set_shader_parameter("base_color", Vector3(p[4][0], p[4][1], p[4][2]))
		m.set_shader_parameter("kind", KINDS[p[5]])
		m.set_shader_parameter("sys_flat", Data.INTRO.sys_flat)
		m.set_shader_parameter("sys_tilt", Data.INTRO.sys_tilt)
		m.set_shader_parameter("seed", float(_planets.size()))
		r.material = m
		r.visible = false
		add_child(r)
		_planets.append(r)
	_sun = _layer(2, add)
	_audio = AudioStreamPlayer.new()
	_audio.stream = SOUNDTRACKS[_pick_soundtrack()]
	_audio.bus = audio_bus if AudioServer.get_bus_index(audio_bus) >= 0 else &"Master"
	add_child(_audio)
	_stars.draw.connect(_draw_stars)
	_orbits.draw.connect(_draw_orbits)
	_sun.draw.connect(_draw_sun)
	_text.draw.connect(_draw_text)
	if autoplay:
		play()


func _layer(z: int, mat: Material) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = z
	c.material = mat
	add_child(c)
	return c


func _load_stars() -> void:
	var G: Array = Data.GALAXY
	var n := G.size() / 4
	_gal.resize(n)
	_gal_e.resize(n)
	_gal_d.resize(n)
	for i in n:
		var sz: float = G[i * 4 + 2]
		_gal[i] = Vector2(G[i * 4], G[i * 4 + 1])
		_gal_e[i] = clampf(G[i * 4 + 3] * (0.55 + 0.75 * sz), 0.0, 1.0)
		_gal_d[i] = 1.7 + 2.0 * sz
	var L: Array = Data.LOCAL
	n = L.size() / 4
	_loc.resize(n)
	_loc_e.resize(n)
	_loc_d.resize(n)
	for i in n:
		var sz: float = L[i * 4 + 2]
		_loc[i] = Vector2(L[i * 4], L[i * 4 + 1])
		_loc_e[i] = clampf(L[i * 4 + 3] * (0.55 + 0.75 * sz), 0.0, 1.0)
		_loc_d[i] = 2.2 + 2.6 * sz


func play() -> void:
	t = 0.0
	_fade_from = -1.0
	_done = false
	_playing = true
	if play_sound:
		_audio.volume_db = 0.0
		_audio.play()


func skip() -> void:
	if _playing and _fade_from < 0.0:
		_fade_from = t


func _process(delta: float) -> void:
	if not _playing:
		return
	t += delta
	var hold: float = Data.INTRO.hold
	if _fade_from < 0.0 and t >= hold:
		_fade_from = hold
	if _fade_from >= 0.0 and _fade() <= 0.0 and not _done:
		_done = true
		_playing = false
		_audio.stop()
		finished.emit()
		return
	if _fade_from >= 0.0 and _fade_from < float(Data.INTRO.hold):
		# skipped: the soundtrack fades out with the picture
		_audio.volume_db = linear_to_db(maxf(1.0 - _smooth((t - _fade_from) / 0.35), 0.0001))
	_update_camera()
	_update_planets()
	_stars.queue_redraw()
	_orbits.queue_redraw()
	_sun.queue_redraw()
	_text.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if skippable and _is_press(event):
		skip()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if skippable and _is_press(event):
		skip()


static func _is_press(e: InputEvent) -> bool:
	return (e is InputEventKey and e.pressed and not e.echo) \
		or (e is InputEventMouseButton and e.pressed) \
		or (e is InputEventScreenTouch and e.pressed) \
		or (e is InputEventJoypadButton and e.pressed)


func _fade() -> float:
	var I: Dictionary = Data.INTRO
	var f := _smooth(t / float(I.fade_in))
	if _fade_from >= 0.0:
		var dur: float = (float(I.end) - float(I.hold)) if _fade_from >= float(I.hold) else 0.35
		f *= 1.0 - _smooth((t - _fade_from) / dur)
	return f


# ------------------------------------------------------------------ camera
func _scale() -> float:
	return minf(size.x / 1280.0, size.y / 720.0)


func _lockup() -> Dictionary:
	var s := _scale()
	var r: float = float(Data.VIEW.lockup.r) * s
	var fs := int(96.0 * s)
	var track := 0.02 * fs
	var ww := _tracked_width(WORD, FONT_BOLD, fs, track)
	var gw := 2.0 * r * float(Data.VIEW.lockup.half_w)
	var gap := float(Data.VIEW.lockup.gap) * r
	var x0 := (size.x - (gw + gap + ww)) * 0.5
	var cap := FONT_BOLD.get_ascent(fs) * 0.72
	return {
		"s": s, "r": r, "fs": fs, "track": track, "ww": ww,
		"c": Vector2(x0 + gw * 0.5, size.y * 0.5),
		"tx": x0 + gw + gap,
		"base": size.y * 0.5 + cap * 0.5,
	}


func _update_camera() -> void:
	var I: Dictionary = Data.INTRO
	var V: Dictionary = Data.VIEW
	var L := _lockup()
	var sys_px0: float = float(I.sys_fill) * size.x / 0.92
	var s0: float = sys_px0 / float(I.sys_size)
	var s1: float = L.r
	var z := _ease_io((t - float(I.zoom0)) / (float(I.zoom1) - float(I.zoom0)))
	var s := exp(log(s0) + z * (log(s1) - log(s0)))
	var k := _smooth((z - float(I.center_from)) / (1.0 - float(I.center_from)))
	var rot: float = float(V.spin) * t
	var sa: float = float(V.sun_a) + rot
	var sun := Vector2(cos(sa), sin(sa)) * float(I.sun_r)
	var focus := sun * (1.0 - k)
	var u := _ease_io((t - float(I.slide0)) / float(I.slide_len))
	var C: Vector2 = size * 0.5 + u * (Vector2(L.c) - size * 0.5)
	# plane -> screen: flatten, tilt, scale, then translate so focus sits at C
	var ct := cos(float(V.tilt))
	var st := sin(float(V.tilt))
	var fl: float = V.flat
	var M := Transform2D(Vector2(ct, st) * s, Vector2(-st, ct) * fl * s, Vector2.ZERO)
	M.origin = C - M.basis_xform(focus)
	_cam = {
		"z": z, "s": s, "M": M, "C": C, "L": L,
		"sun_plane": sun,
		"sun": M * sun,
		"sys_px": float(I.sys_size) * s,
		"spin": Transform2D(rot, Vector2.ZERO),
	}


func _sys_proj(x: float, y: float) -> Vector2:
	var I: Dictionary = Data.INTRO
	var c := cos(float(I.sys_tilt))
	var s := sin(float(I.sys_tilt))
	var yy: float = y * float(I.sys_flat)
	return Vector2(x * c - yy * s, x * s + yy * c) * float(_cam.sys_px)


func _update_planets() -> void:
	var I: Dictionary = Data.INTRO
	var sun: Vector2 = _cam.sun
	var fade := _fade()
	var view := Rect2(Vector2.ZERO, size)
	for i in _planets.size():
		var p: Array = I.planets[i]
		var node := _planets[i]
		var ang: float = float(p[3]) + TAU * t / float(p[2])
		var x: float = float(p[0]) * cos(ang)
		var y: float = float(p[0]) * sin(ang)
		var pos := sun + _sys_proj(x, y)
		var rpx: float = float(p[1]) * float(_cam.sys_px)
		var ext: float = 2.3 if p[5] == "ringed" else 1.25
		var half := rpx * ext + 1.0
		node.visible = rpx >= 0.35 and view.grow(half).has_point(pos)
		if not node.visible:
			continue
		node.position = pos - Vector2(half, half)
		node.size = Vector2(half, half) * 2.0
		node.z_index = 1 if y < 0.0 else 3   # behind / in front of the sun
		var l := sun - pos
		var ld := Vector3(l.x, l.y, 0.0).normalized()
		ld.z = -y * 0.45
		var m: ShaderMaterial = node.material
		m.set_shader_parameter("light_dir", ld.normalized())
		m.set_shader_parameter("radius_px", rpx)
		m.set_shader_parameter("ext", half / maxf(rpx, 0.001))
		m.set_shader_parameter("time_s", t)
		m.set_shader_parameter("opacity", fade * clampf(rpx / 0.8, 0.0, 1.0))


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)


func _draw_stars() -> void:
	if _cam.is_empty():
		return
	var fade := _fade()
	var M: Transform2D = _cam.M
	var spin: Transform2D = _cam.spin
	var full := M * spin        # galaxy plane (t = 0) -> screen
	var px := maxf(_scale(), 0.5)
	var view := Rect2(Vector2.ZERO, size).grow(8.0)
	var col := INK
	# soft nebula glow once the galaxy is small enough to read as a whole
	var neb := 0.55 * _smooth((float(_cam.z) - 0.55) / 0.35) * fade
	if neb > 0.0:
		_stars.draw_set_transform_matrix(full)
		_stars.draw_texture_rect(NEBULA, Rect2(-1.1, -1.1, 2.2, 2.2), false, Color(INK, neb))
		_stars.draw_set_transform_matrix(Transform2D.IDENTITY)
	for i in _gal.size():
		var p := full * _gal[i]
		if not view.has_point(p):
			continue
		var d := _gal_d[i] * px
		col.a = _gal_e[i] * fade
		_stars.draw_texture_rect(_dot, Rect2(p.x - d * 0.5, p.y - d * 0.5, d, d), false, col)
	# neighbouring stars around the system (vanish as the galaxy forms)
	var vanish := 1.0 - _smooth((float(_cam.z) - 0.72) / 0.22)
	if vanish > 0.0:
		var sun: Vector2 = _cam.sun
		var sunp: Vector2 = _cam.sun_plane
		for i in _loc.size():
			var p := M * (sunp + spin.basis_xform(_loc[i]))
			if not view.has_point(p):
				continue
			var a := _loc_e[i] * clampf((p.distance_to(sun) - 4.0) / 40.0, 0.0, 1.0) * vanish
			if a <= 0.004:
				continue
			var d := _loc_d[i] * px
			col.a = a * fade
			_stars.draw_texture_rect(_dot, Rect2(p.x - d * 0.5, p.y - d * 0.5, d, d), false, col)
	# galaxy core + soft disc glow (they scale with the camera)
	var core := 1.05 * _smooth((float(_cam.z) - 0.45) / 0.4) * fade
	if core > 0.0:
		var g := M.origin
		var R: float = _cam.s
		var tilt: float = Data.VIEW.tilt
		_glow_at(_stars, g, sqrt(0.0011) * R, INK, 0.9 * core, 0.8, tilt)
		_glow_at(_stars, g, sqrt(0.015) * R, INK, 0.28 * core, 0.8, tilt)
		_glow_at(_stars, g, 0.4 * R, Color(0.8, 0.85, 1.0), 0.12 * core,
			float(Data.VIEW.flat), tilt)


func _draw_orbits() -> void:
	if _cam.is_empty():
		return
	var fade := _fade()
	var sun: Vector2 = _cam.sun
	for p: Array in Data.INTRO.planets:
		var rpx: float = float(p[0]) * float(_cam.sys_px)
		var a := 0.20 * _smooth((rpx - 18.0) / 90.0) * fade
		if a < 0.004:
			continue
		var pts := PackedVector2Array()
		for j in 121:
			var th := TAU * j / 120.0
			pts.append(sun + _sys_proj(float(p[0]) * cos(th), float(p[0]) * sin(th)))
		_orbits.draw_polyline(pts, Color(0.75, 0.8, 0.95, a), 1.0, true)


func _draw_sun() -> void:
	if _cam.is_empty():
		return
	var fade := _fade()
	var pos: Vector2 = _cam.sun
	var rpx: float = float(Data.INTRO.sun_radius) * float(_cam.sys_px)
	var point := 1.0 - _smooth((rpx - 0.8) / 2.5)
	var settle := 1.0 - _smooth((float(_cam.z) - 0.78) / 0.2)
	var amp := (0.25 + 0.75 * settle) * fade
	var px := maxf(_scale(), 0.5)
	_glow_at(_sun, pos, maxf(rpx * 1.6, 2.2 * px), SUN, 1.2 * amp)
	_glow_at(_sun, pos, maxf(rpx * 4.0, 6.0 * px), SUN, 0.22 * amp)
	_glow_at(_sun, pos, maxf(rpx * 12.0, 14.0 * px), SUN, 0.025 * amp * (1.0 - point))
	if rpx > 1.2:
		_sun.draw_texture_rect(_disc, Rect2(pos - Vector2(rpx, rpx), Vector2(rpx, rpx) * 2.0),
			false, Color(1, 1, 1, fade))
	if rpx > 3.0:
		_glow_at(_sun, pos, rpx * 6.0, SUN, 0.25 * amp, 0.035, 0.0)


func _draw_text() -> void:
	if _cam.is_empty():
		return
	var I: Dictionary = Data.INTRO
	var L: Dictionary = _cam.L
	var e := _ease_out_cubic((t - float(I.slide0) - float(I.text_delay)) / float(I.text_len))
	if e <= 0.0:
		return
	var R: float = L.r
	var hidden: float = size.x * 0.5 + float(I.clip) * R - float(L.ww) - 0.1 * R
	var x: float = hidden + e * (float(L.tx) - hidden)
	var m: ShaderMaterial = _text.material
	m.set_shader_parameter("clip_x", float(_cam.C.x) + float(I.clip) * R)
	m.set_shader_parameter("feather", float(I.feather) * R)
	var fs: int = L.fs
	var col := Color(INK, _fade())
	for ch in WORD:
		if ch != " ":
			_text.draw_string(FONT_BOLD, Vector2(x, L.base), ch, HORIZONTAL_ALIGNMENT_LEFT, -1,
				fs, col)
		x += FONT_BOLD.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + float(L.track)


## Gaussian glow of standard deviation `sigma` px; amp is pre-tonemap energy.
func _glow_at(ci: CanvasItem, pos: Vector2, sigma: float, col: Color, amp: float,
		squash := 1.0, angle := 0.0) -> void:
	if amp <= 0.001 or sigma <= 0.0:
		return
	var a := 1.0 - exp(-amp * 1.15)
	var r := sigma * 3.2
	ci.draw_set_transform(pos, angle, Vector2(1.0, squash))
	ci.draw_texture_rect(_glow, Rect2(-r, -r, r * 2.0, r * 2.0), false,
		Color(col.r, col.g, col.b, a))
	ci.draw_set_transform(Vector2.ZERO)


static func _tracked_width(text: String, f: Font, fs: int, track: float) -> float:
	var w := 0.0
	for ch in text:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return w + track * (text.length() - 1)


# ------------------------------------------------------------------ helpers
static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out_cubic(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5


## Gaussian falloff; the texture edge is 3.2 sigma.
static func _radial_texture(px: int) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var h := px * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - h, y + 0.5 - h).length() / h * 3.2
			img.set_pixel(x, y, Color(1, 1, 1, exp(-0.5 * d * d)))
	return ImageTexture.create_from_image(img)


static func _sun_disc_texture(px: int) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var h := px * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - h, y + 0.5 - h).length() / h
			var a := clampf((1.0 - d) * h, 0.0, 1.0)
			var mu := sqrt(maxf(1.0 - d * d, 0.0))
			var limb := 0.75 + 0.25 * mu
			img.set_pixel(x, y, Color(limb, limb * 0.97, limb * 0.9, a))
	return ImageTexture.create_from_image(img)


func _pick_soundtrack() -> String:
	if SOUNDTRACKS.has(soundtrack):
		return soundtrack
	var cfg := ConfigFile.new()
	cfg.load(LAST_SOUNDTRACK)
	var last: String = cfg.get_value("intro", "soundtrack", "")
	var names: Array = SOUNDTRACKS.keys().filter(func(n): return n != last)
	var pick: String = names[randi() % names.size()]
	cfg.set_value("intro", "soundtrack", pick)
	cfg.save(LAST_SOUNDTRACK)
	return pick
