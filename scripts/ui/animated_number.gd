class_name AnimatedNumber
extends Control
## Odometer-style numeric display: each character sits in its own clipped cell
## and only the characters that change roll to the new value.
##
## Decrease (2 -> 1): the old digit slides down and the new one comes from above.
## Increase (1 -> 2): the old digit slides up and the new one comes from below.
## Digits roll right to left with a small stagger, like a mechanical counter.
## Text that is not numeric (such as "∞") changes instantly.

@export var initial_text := ""
@export var font_variation: StringName = &"HudBig"
## 0 keeps the font size defined by the theme variation.
@export var font_size := 0
@export var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
@export var vertical_alignment: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER
## Duration of one digit roll. Shortened automatically when values change
## faster than this (automatic weapons), so the counter never lags behind.
@export var animation_duration := 0.24
## Delay between neighbouring digits (rightmost rolls first).
@export var digit_stagger := 0.035
## Travel of a rolling digit; 0 uses the full height of the counter.
@export var slide_distance := 0.0

var text: String:
	get:
		return _target if _row else initial_text
	set(value):
		_set_text(value)

## Value shown or being animated toward.
var _target := ""
var _row: HBoxContainer
## One entry per character: {"cell": Control, "cur": Label, "nxt": Label, "ch": String}
var _cells: Array[Dictionary] = []
var _tween: Tween
var _color := Color.TRANSPARENT
var _has_color := false
var _font: Font
var _font_px := 16
var _digit_width := 0.0
var _last_change_ms := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 0)
	_row.alignment = {
		HORIZONTAL_ALIGNMENT_LEFT: BoxContainer.ALIGNMENT_BEGIN,
		HORIZONTAL_ALIGNMENT_CENTER: BoxContainer.ALIGNMENT_CENTER,
		HORIZONTAL_ALIGNMENT_RIGHT: BoxContainer.ALIGNMENT_END,
	}.get(horizontal_alignment, BoxContainer.ALIGNMENT_BEGIN)
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	_measure_font()
	_target = initial_text
	_rebuild(initial_text)


## Changes the displayed value with an odometer roll.
func set_value(new_text: String) -> void:
	_set_text(new_text)


## Applies a color override to every digit (health, warnings, etc.).
func set_text_color(color: Color) -> void:
	if _has_color and color == _color:
		return
	_color = color
	_has_color = true
	for c in _cells:
		(c.cur as Label).add_theme_color_override("font_color", color)
		(c.nxt as Label).add_theme_color_override("font_color", color)


# ------------------------------------------------------------------ internals

func _measure_font() -> void:
	var probe := _make_label()
	add_child(probe)
	_font = probe.get_theme_font("font")
	_font_px = font_size if font_size > 0 else probe.get_theme_font_size("font_size")
	probe.queue_free()
	# Every digit gets the width of the widest one, so numbers never jitter.
	_digit_width = 0.0
	for d in "0123456789":
		_digit_width = maxf(_digit_width, _char_width(d))


func _char_width(ch: String) -> float:
	if ch == "" or ch == " ":
		return 0.0
	if ch.is_valid_int() and _digit_width > 0.0:
		return _digit_width
	if _font == null:
		return 10.0
	return ceilf(_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px).x)


func _make_label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.theme_type_variation = font_variation
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	if _has_color:
		l.add_theme_color_override("font_color", _color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = vertical_alignment
	return l


func _make_cell(ch: String) -> Dictionary:
	var cell := Control.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.clip_contents = true
	cell.size_flags_vertical = Control.SIZE_FILL
	cell.custom_minimum_size.x = _char_width(ch)
	var cur := _make_label()
	cur.text = ch
	cell.add_child(cur)
	cur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var nxt := _make_label()
	nxt.visible = false
	cell.add_child(nxt)
	nxt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {"cell": cell, "cur": cur, "nxt": nxt, "ch": ch}


## Replaces every cell without animation.
func _rebuild(value: String) -> void:
	for c in _cells:
		(c.cell as Control).queue_free()
	_cells.clear()
	for i in value.length():
		var c := _make_cell(value[i])
		_row.add_child(c.cell)
		_cells.append(c)


func _set_text(new_text: String) -> void:
	if _row == null:
		initial_text = new_text
		return
	if new_text == _target:
		return
	var direction := _direction(_target, new_text)
	_finish()
	var old_text := _target
	_target = new_text
	if direction == 0 or not is_inside_tree():
		_rebuild(new_text)
		return
	_roll(old_text, new_text, direction)


## Animates the characters that differ between `old_text` and `new_text`.
func _roll(old_text: String, new_text: String, direction: int) -> void:
	# Align from the right (units under units) by padding the shorter text.
	var n := maxi(old_text.length(), new_text.length())
	var old_p := old_text.lpad(n)
	var new_p := new_text.lpad(n)
	while _cells.size() < n:
		var c := _make_cell(" ")
		_row.add_child(c.cell)
		_row.move_child(c.cell, 0)
		_cells.push_front(c)

	# Values changing faster than the roll (automatic fire): speed it up.
	var now := Time.get_ticks_msec()
	var since := (now - _last_change_ms) / 1000.0
	_last_change_ms = now
	var duration := clampf(since * 0.85, 0.06, animation_duration)
	var stagger := digit_stagger * (duration / animation_duration)

	var travel := slide_distance if slide_distance > 0.0 else maxf(size.y, 1.0)
	# Increase: new digit comes from below, old leaves upward. Decrease: inverse.
	var enter_from := travel if direction > 0 else -travel
	var exit_to := -enter_from

	_tween = create_tween().set_parallel()
	var order := 0
	for i in range(n - 1, -1, -1):
		var c := _cells[i]
		var a := old_p[i]
		var b := new_p[i]
		if a == b:
			continue
		var cur := c.cur as Label
		var nxt := c.nxt as Label
		var cell := c.cell as Control
		c.ch = b
		nxt.text = b
		nxt.visible = true
		_shift(nxt, enter_from)
		_shift(cur, 0.0)
		var delay := order * stagger
		order += 1
		_tween.tween_method(_shift_step.bind(cur), 0.0, exit_to, duration).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(_shift_step.bind(nxt), enter_from, 0.0, duration).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var w := _char_width(b)
		if w != cell.custom_minimum_size.x:
			_tween.tween_property(cell, "custom_minimum_size:x", w, duration).set_delay(delay) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if order == 0:
		_tween.kill()
		return
	_tween.chain().tween_callback(_finish)


## Moves a digit vertically inside its cell. Labels are anchored to the full
## cell, so moving both offsets keeps the size right even while the cell is
## still being laid out (a new digit added on the left).
static func _shift(label: Label, y: float) -> void:
	label.offset_top = y
	label.offset_bottom = y


## Same as _shift with the arguments swapped, for Tween.tween_method + bind.
static func _shift_step(y: float, label: Label) -> void:
	_shift(label, y)


## Ends any running roll immediately and settles every cell on its final
## character (also drops empty padding cells on the left).
func _finish() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	for c in _cells:
		var cur := c.cur as Label
		var nxt := c.nxt as Label
		cur.text = c.ch
		_shift(cur, 0.0)
		nxt.visible = false
		_shift(nxt, 0.0)
		(c.cell as Control).custom_minimum_size.x = _char_width(c.ch)
	while not _cells.is_empty() and _cells[0].ch == " ":
		(_cells[0].cell as Control).queue_free()
		_cells.pop_front()


## +1 when the value grew, -1 when it shrank, 0 when it is not numeric.
static func _direction(old_text: String, new_text: String) -> int:
	var a = _to_number(old_text)
	var b = _to_number(new_text)
	if a == null or b == null:
		return 0
	if b > a:
		return 1
	if b < a:
		return -1
	return 0


## Accepts integers and mm:ss clocks.
static func _to_number(value: String) -> Variant:
	if value.is_valid_int():
		return int(value)
	var parts := value.split(":")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return int(parts[0]) * 60 + int(parts[1])
	return null
