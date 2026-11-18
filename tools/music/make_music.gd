extends SceneTree
## Generates the game's music (original pieces, synthesized here, no samples):
##
##   audio/music/menu_winter.wav      lobby theme "Winter Warfare", 24 bars
##   audio/music/results_winter.wav   match over / map vote, 8 bars
##
## Run from the project root:
##   godot --headless --path . --script tools/music/make_music.gd
##
## Instruments are small synths written below: FM bells (the melody), a warm
## detuned pad, a plucked bass, kick / clap / hats, sleigh bells, a noise
## swell and a Freeverb-style reverb. Each piece loops seamlessly: the reverb
## tail and notes that ring past the end are folded back onto the start.
## Both files are stereo, 16-bit, 32 kHz; Godot imports them compressed (QOA)
## and looping (see the .import files).

const SR := 32000
const TAIL := 4.0
const OUT_DIR := "res://audio/music/"

## Chord voicings (MIDI notes, lowest first: the root is the first note).
const CHORDS := {
	"D": [50, 57, 62, 66], "Bm": [47, 54, 59, 62], "G": [43, 55, 59, 62],
	"A": [45, 52, 57, 61], "F#m": [42, 54, 57, 61], "Asus4": [45, 52, 57, 62],
	"Em": [40, 55, 59, 64], "A7": [45, 55, 61, 64], "D/F#": [42, 54, 57, 62],
	"C": [36, 52, 55, 60], "Am": [45, 52, 57, 60], "Dlow": [38, 54, 57, 62],
}

var _l := PackedFloat32Array()
var _r := PackedFloat32Array()
## Reverb send (mono).
var _send := PackedFloat32Array()
var _warm := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _beat := 0.5


func _initialize() -> void:
	_warm = _make_warm_table()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_menu_theme()
	_results_theme()
	quit()


# ================================================================== pieces

## Lobby theme, D major, 112 BPM, 24 bars:
##   1-8   intro: pad, bells, sleigh bells, soft bass
##   9-16  full: drums, bass groove, bells in thirds
##   17-24 bridge: new melody, arpeggios, a swell back into the intro
func _menu_theme() -> void:
	_rng.seed = 2512
	var bpm := 112.0
	_beat = 60.0 / bpm
	var bars := 24
	_begin(bars * 4 * _beat)
	var a := ["D", "Bm", "G", "A", "D", "F#m", "G", "Asus4"]
	var c := ["Em", "A", "F#m", "Bm", "G", "D", "Em", "A7"]
	var progression: Array = a + a + c
	var melody_a := [
		[[0, 78, 1], [1, 81, 0.5], [1.5, 78, 0.5], [2, 74, 1], [3, 76, 1]],
		[[0, 78, 1.5], [1.5, 76, 0.5], [2, 74, 1], [3, 71, 1]],
		[[0, 74, 1], [1, 79, 1], [2, 78, 0.5], [2.5, 76, 0.5], [3, 74, 1]],
		[[0, 76, 2], [2, 73, 1], [3, 69, 1]],
		[[0, 78, 1], [1, 81, 0.5], [1.5, 83, 0.5], [2, 81, 1], [3, 78, 1]],
		[[0, 81, 1.5], [1.5, 78, 0.5], [2, 76, 1], [3, 73, 1]],
		[[0, 71, 0.5], [0.5, 74, 0.5], [1, 79, 1], [2, 78, 0.5], [2.5, 79, 0.5], [3, 81, 1]],
		[[0, 81, 3]],
	]
	var melody_c := [
		[[0, 79, 1], [1, 78, 1], [2, 76, 1], [3, 71, 1]],
		[[0, 73, 1], [1, 76, 1], [2, 81, 2]],
		[[0, 81, 1], [1, 78, 1], [2, 73, 1], [3, 78, 1]],
		[[0, 74, 1.5], [1.5, 78, 0.5], [2, 83, 2]],
		[[0, 83, 1], [1, 81, 1], [2, 79, 1], [3, 74, 1]],
		[[0, 78, 1], [1, 76, 0.5], [1.5, 74, 0.5], [2, 69, 2]],
		[[0, 79, 1], [1, 78, 1], [2, 76, 1], [3, 79, 1]],
		[[0, 81, 1], [1, 79, 0.5], [1.5, 76, 0.5], [2, 73, 1], [3, 76, 1]],
	]
	for bar in bars:
		var t0 := bar * 4 * _beat
		var chord: Array = CHORDS[progression[bar]]
		var section := bar / 8
		# Pad: whole bar, brighter in the bridge.
		_pad(chord, t0, 4 * _beat, 0.040 if section == 0 else 0.050)
		# Bells melody.
		var phrase: Array = melody_c[bar % 8] if section == 2 else melody_a[bar % 8]
		for n in phrase:
			var start := t0 + float(n[0]) * _beat
			var dur := float(n[2]) * _beat
			_bell(_freq(int(n[1])), start, dur, 0.20, 0.08)
			if section == 1:
				# Thirds below in the full section (diatonic: chord tone under it).
				_bell(_freq(_harmony_below(int(n[1]), chord)), start, dur, 0.10, -0.25)
		# Sleigh bells: 8ths in the intro, 16ths after.
		var step := 0.5 if section == 0 else 0.25
		var count := int(4.0 / step)
		for i in count:
			var accent := 1.0 if i % int(1.0 / step) == 0 else 0.6
			_sleigh(t0 + i * step * _beat, (0.05 if section == 0 else 0.065) * accent)
		# Bass.
		var root := _bass_note(int(chord[0]))
		if section == 0:
			_bass(_freq(root), t0, 2 * _beat, 0.30)
			_bass(_freq(root), t0 + 2 * _beat, 2 * _beat, 0.26)
		else:
			var pattern := [0, 0, 12, 0, 7, 0, 12, 7]
			for i in 8:
				_bass(_freq(root + pattern[i]), t0 + i * 0.5 * _beat, 0.45 * _beat, 0.30 if i % 2 == 0 else 0.22)
		# Drums.
		if section == 1:
			for b in 4:
				_kick(t0 + b * _beat, 0.85 if b % 2 == 0 else 0.6)
				if b % 2 == 1:
					_clap(t0 + b * _beat, 0.32)
			for i in 8:
				_hat(t0 + i * 0.5 * _beat, 0.10 if i % 2 == 1 else 0.05)
		elif section == 2:
			_kick(t0, 0.75)
			_kick(t0 + 2.5 * _beat, 0.5)
			_clap(t0 + _beat, 0.22)
			_clap(t0 + 3 * _beat, 0.22)
			# Arpeggio of the chord, one octave up, 8ths.
			for i in 8:
				var note := int(chord[1 + i % 3]) + 12
				_pluck(_freq(note), t0 + i * 0.5 * _beat, 0.45 * _beat, 0.07, 0.35 if i % 2 == 0 else -0.35)
		if bar == bars - 1:
			_swell(t0, 4 * _beat, 0.16)
	_finish("menu_winter.wav")


## Match over and map vote: G major, 96 BPM, 8 bars, warm and calm.
func _results_theme() -> void:
	_rng.seed = 1225
	var bpm := 96.0
	_beat = 60.0 / bpm
	var bars := 8
	_begin(bars * 4 * _beat)
	var progression := ["G", "D/F#", "Em", "Dlow", "C", "G", "Am", "Dlow"]
	var melody := [
		[[0, 83, 1], [1, 86, 1], [2, 83, 1], [3, 79, 1]],
		[[0, 81, 2], [2, 78, 1], [3, 74, 1]],
		[[0, 76, 1], [1, 79, 1], [2, 83, 1.5], [3.5, 81, 0.5]],
		[[0, 78, 3]],
		[[0, 76, 1], [1, 79, 1], [2, 84, 1], [3, 83, 1]],
		[[0, 86, 2], [2, 83, 1], [3, 79, 1]],
		[[0, 81, 1], [1, 84, 1], [2, 83, 1], [3, 81, 1]],
		[[0, 78, 2], [2, 81, 1], [3, 74, 1]],
	]
	for bar in bars:
		var t0 := bar * 4 * _beat
		var chord: Array = CHORDS[progression[bar]]
		_pad(chord, t0, 4 * _beat, 0.045)
		for n in melody[bar]:
			_bell(_freq(int(n[1])), t0 + float(n[0]) * _beat, float(n[2]) * _beat, 0.18, 0.1)
		for i in 8:
			_sleigh(t0 + i * 0.5 * _beat, 0.045 if i % 2 == 0 else 0.03)
		var root := _bass_note(int(chord[0]))
		_bass(_freq(root), t0, 2 * _beat, 0.26)
		_bass(_freq(root + 7), t0 + 2 * _beat, 2 * _beat, 0.2)
		_kick(t0, 0.45)
		for i in 4:
			var note := int(chord[1 + i % 3]) + 12
			_pluck(_freq(note), t0 + (i + 0.5) * _beat, 0.5 * _beat, 0.05, 0.3 if i % 2 == 0 else -0.3)
	_finish("results_winter.wav")


# ================================================================== helpers

func _freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## Bass in MIDI 33-45.
func _bass_note(root: int) -> int:
	while root > 45:
		root -= 12
	while root < 33:
		root += 12
	return root


## The highest chord tone 3 to 5 semitones below `note` (a third or a
## fourth), or the closest chord tone under it.
func _harmony_below(note: int, chord: Array) -> int:
	var best := -1
	for tone in chord:
		for octave in [0, 12, 24, 36]:
			var candidate := int(tone) + int(octave)
			if candidate <= note - 3 and candidate > best:
				best = candidate
	return best if best >= 0 else note - 4


func _begin(seconds: float) -> void:
	var n := int((seconds + TAIL) * SR)
	_l = PackedFloat32Array()
	_r = PackedFloat32Array()
	_send = PackedFloat32Array()
	_l.resize(n)
	_r.resize(n)
	_send.resize(n)
	_l.fill(0.0)
	_r.fill(0.0)
	_send.fill(0.0)
	set_meta("loop_frames", int(seconds * SR))


## Band-limited, softened sawtooth (one cycle, 2048 points).
func _make_warm_table() -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(2048)
	for i in 2048:
		var x := TAU * i / 2048.0
		var v := 0.0
		for k in range(1, 9):
			v += sin(k * x) / pow(k, 1.35)
		table[i] = v * 0.55
	return table


## Adds a mono signal to the mix with a pan (-1 left .. 1 right) and reverb send.
func _put(index: int, value: float, pan: float, send: float) -> void:
	if index < 0 or index >= _l.size():
		return
	_l[index] += value * (1.0 - maxf(pan, 0.0))
	_r[index] += value * (1.0 + minf(pan, 0.0))
	_send[index] += value * send


# ================================================================== instruments

## FM bell (glockenspiel / celesta): bright attack, long ring.
func _bell(f: float, start: float, dur: float, amp: float, pan: float) -> void:
	var length := dur + 1.6
	var i0 := int(start * SR)
	var n := int(length * SR)
	for i in n:
		var t := float(i) / SR
		var index := 1.6 * exp(-5.0 * t) + 0.25
		var env := minf(t / 0.003, 1.0) * exp(-2.4 * t)
		if t > dur:
			env *= exp(-(t - dur) * 3.0)
		var v := sin(TAU * f * t + index * sin(TAU * 3.5 * f * t))
		v += 0.25 * sin(TAU * 2.0 * f * t) * exp(-6.0 * t)
		_put(i0 + i, v * env * amp, pan, 0.45)


## Warm pad: two detuned voices per note, one per side.
func _pad(chord: Array, start: float, dur: float, amp: float) -> void:
	var attack := 0.35
	var release := 0.7
	var i0 := int(start * SR)
	var n := int((dur + release) * SR)
	for tone in chord:
		var f := _freq(int(tone))
		var fl := f * pow(2.0, -7.0 / 1200.0)
		var fr := f * pow(2.0, 7.0 / 1200.0)
		var pl := _rng.randf()
		var pr := _rng.randf()
		for i in n:
			var t := float(i) / SR
			var env := minf(t / attack, 1.0)
			if t > dur:
				env *= maxf(0.0, 1.0 - (t - dur) / release)
			pl += fl / SR
			pr += fr / SR
			var vl := _warm[int(fmod(pl, 1.0) * 2048.0) & 2047] * env * amp
			var vr := _warm[int(fmod(pr, 1.0) * 2048.0) & 2047] * env * amp
			var k := i0 + i
			if k < _l.size():
				_l[k] += vl
				_r[k] += vr
				_send[k] += (vl + vr) * 0.35


## Plucked bass: sine body with a short bright attack.
func _bass(f: float, start: float, dur: float, amp: float) -> void:
	var i0 := int(start * SR)
	var n := int((dur + 0.08) * SR)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var env := minf(t / 0.004, 1.0) * (0.55 * exp(-3.0 * t) + 0.45)
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / 0.08)
		phase += f / SR
		var body := sin(TAU * phase)
		var bite := _warm[int(fmod(phase, 1.0) * 2048.0) & 2047] * exp(-14.0 * t)
		_put(i0 + i, (body * 0.8 + bite * 0.5) * env * amp, 0.0, 0.05)


## Soft pluck for arpeggios.
func _pluck(f: float, start: float, dur: float, amp: float, pan: float) -> void:
	var i0 := int(start * SR)
	var n := int((dur + 0.5) * SR)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var env := minf(t / 0.002, 1.0) * exp(-6.0 * t)
		phase += f / SR
		var v := _warm[int(fmod(phase, 1.0) * 2048.0) & 2047] * (0.4 + 0.6 * exp(-20.0 * t)) + sin(TAU * phase) * 0.4
		_put(i0 + i, v * env * amp, pan, 0.4)


func _kick(start: float, amp: float) -> void:
	var i0 := int(start * SR)
	var n := int(0.45 * SR)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		phase += (48.0 + 95.0 * exp(-32.0 * t)) / SR
		var v := sin(TAU * phase) * exp(-7.5 * t)
		if t < 0.003:
			v += _rng.randf_range(-0.3, 0.3)
		_put(i0 + i, v * amp, 0.0, 0.02)


func _clap(start: float, amp: float) -> void:
	for burst in 3:
		var i0 := int((start + burst * 0.011) * SR)
		var n := int(0.22 * SR)
		var prev := 0.0
		for i in n:
			var t := float(i) / SR
			var noise := _rng.randf_range(-1.0, 1.0)
			var hp := noise - prev
			prev = noise
			var decay := 0.22 if burst == 2 else 0.02
			var v := hp * exp(-t / decay * 3.0) * (1.0 if burst == 2 else 0.6)
			v += sin(TAU * 185.0 * t) * exp(-35.0 * t) * 0.3 * float(burst == 2)
			_put(i0 + i, v * amp * 0.5, 0.05, 0.3)


func _hat(start: float, amp: float) -> void:
	var i0 := int(start * SR)
	var n := int(0.06 * SR)
	var a := 0.0
	var b := 0.0
	for i in n:
		var t := float(i) / SR
		var noise := _rng.randf_range(-1.0, 1.0)
		var h1 := noise - a
		a = noise
		var h2 := h1 - b
		b = h1
		_put(i0 + i, h2 * 0.5 * exp(-70.0 * t) * amp, 0.3, 0.05)


## Sleigh bells: a cluster of small jingles, slightly loose in time.
func _sleigh(start: float, amp: float) -> void:
	var jingles := 4
	for j in jingles:
		var offset := _rng.randf_range(-0.004, 0.012)
		var f := _rng.randf_range(4800.0, 9200.0)
		var f2 := f * _rng.randf_range(1.38, 1.52)
		var pan := _rng.randf_range(-0.45, 0.45)
		var i0 := int((start + offset) * SR)
		var n := int(0.16 * SR)
		var prev := 0.0
		var level := amp * _rng.randf_range(0.6, 1.0) / jingles
		for i in n:
			var t := float(i) / SR
			var noise := _rng.randf_range(-1.0, 1.0)
			var hp := noise - prev
			prev = noise
			var v := (sin(TAU * f * t) + 0.6 * sin(TAU * f2 * t)) * exp(-38.0 * t)
			v += hp * 0.5 * exp(-60.0 * t)
			_put(i0 + i, v * level, pan, 0.25)


## Rising filtered noise into the next section.
func _swell(start: float, dur: float, amp: float) -> void:
	var i0 := int(start * SR)
	var n := int(dur * SR)
	var low := 0.0
	for i in n:
		var t := float(i) / dur / SR
		var noise := _rng.randf_range(-1.0, 1.0)
		var cut := 0.02 + 0.4 * t * t
		low += (noise - low) * cut
		var v := (noise - low) * t * t * t
		_put(i0 + i, v * amp, sin(t * 9.0) * 0.4, 0.5)


# ================================================================== output

## Reverb, loop folding, gentle limiting, 16-bit stereo WAV.
func _finish(file_name: String) -> void:
	var frames: int = get_meta("loop_frames")
	_reverb(0.30)
	# Fold the tail onto the start so the loop is seamless.
	for i in range(frames, _l.size()):
		_l[i - frames] += _l[i]
		_r[i - frames] += _r[i]
	# Normalize to -1.5 dBFS with a soft knee.
	var peak := 0.0
	for i in frames:
		peak = maxf(peak, maxf(absf(_l[i]), absf(_r[i])))
	var gain := 0.84 / maxf(peak, 0.001) * 1.25
	var data := PackedByteArray()
	data.resize(frames * 4)
	for i in frames:
		var l := tanh(_l[i] * gain) * 0.92
		var r := tanh(_r[i] * gain) * 0.92
		data.encode_s16(i * 4, int(clampf(l, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(r, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = SR
	wav.data = data
	var path := OUT_DIR + file_name
	var err := wav.save_to_wav(path)
	print("%s: %.1f s, %d KB (%s)" % [path, float(frames) / SR, data.size() / 1024, error_string(err)])


## Freeverb-style: 4 parallel damped combs and 2 allpasses per side.
func _reverb(wet: float) -> void:
	var combs := [810, 862, 927, 984]
	var allpasses := [403, 320]
	for side in 2:
		var spread := 0 if side == 0 else 23
		var out := PackedFloat32Array()
		out.resize(_send.size())
		out.fill(0.0)
		for delay in combs:
			var d: int = delay + spread
			var buf := PackedFloat32Array()
			buf.resize(d)
			buf.fill(0.0)
			var pos := 0
			var store := 0.0
			for i in _send.size():
				var y := buf[pos]
				store = y * 0.75 + store * 0.25
				buf[pos] = _send[i] + store * 0.8
				pos = (pos + 1) % d
				out[i] += y
		for delay in allpasses:
			var d: int = delay + spread
			var buf := PackedFloat32Array()
			buf.resize(d)
			buf.fill(0.0)
			var pos := 0
			for i in out.size():
				var b := buf[pos]
				var x := out[i]
				buf[pos] = x + b * 0.5
				out[i] = b - x
				pos = (pos + 1) % d
		for i in out.size():
			if side == 0:
				_l[i] += out[i] * wet * 0.25
			else:
				_r[i] += out[i] * wet * 0.25
