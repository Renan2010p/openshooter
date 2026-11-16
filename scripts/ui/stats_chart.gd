class_name StatsChart
extends Control
## Performance chart for the statistics screen: kills and deaths for the last
## matches, with a kill trend line. Bars animate in when the screen opens.

const KILL_COLOR := Color("#f5a524")
const DEATH_COLOR := Color("#e5484d")
const GRID_COLOR := Color(0.24, 0.29, 0.36, 0.35)
const TEXT_COLOR := Color(0.58, 0.63, 0.70, 1.0)

@export var max_bars := 12
@export var animation_duration := 0.55

var _history: Array = []
var _progress := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func set_history(history: Array) -> void:
	var start := maxi(0, history.size() - max_bars)
	_history = history.slice(start)
	_progress = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_progress = minf(1.0, _progress + delta / maxf(animation_duration, 0.01))
	queue_redraw()
	if _progress >= 1.0:
		set_process(false)


func _draw() -> void:
	if size.x < 80.0 or size.y < 60.0:
		return
	var font := get_theme_default_font()
	var plot := Rect2(Vector2(38, 8), size - Vector2(52, 38))
	var ease := 1.0 - pow(1.0 - _progress, 3.0)

	for i in 4:
		var y := plot.position.y + plot.size.y * (float(i) / 3.0)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOR, 1.0)

	var max_value := 1
	for entry in _history:
		max_value = maxi(max_value, maxi(int(entry.get("kills", 0)), int(entry.get("deaths", 0))))
	var axis_values := [max_value, 0] if max_value <= 1 else [max_value, int(max_value * 0.5), 0]
	for i in axis_values.size():
		var y := plot.position.y + plot.size.y * (float(i) / maxf(1.0, axis_values.size() - 1.0))
		draw_string(font, Vector2(0, y + 4), str(axis_values[i]), HORIZONTAL_ALIGNMENT_RIGHT, 32, 12, TEXT_COLOR)

	if _history.is_empty():
		draw_string(font, Vector2(plot.position.x, plot.position.y + plot.size.y * 0.5),
			"Play a match to build your performance chart.",
			HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, 14, TEXT_COLOR)
		return

	var n := _history.size()
	var group := plot.size.x / n
	var bar := minf(22.0, group * 0.28)
	var points := PackedVector2Array()
	for i in n:
		var entry: Dictionary = _history[i]
		var kills := int(entry.get("kills", 0))
		var deaths := int(entry.get("deaths", 0))
		var cx := plot.position.x + group * (i + 0.5)
		var hk := plot.size.y * (float(kills) / max_value) * ease
		var hd := plot.size.y * (float(deaths) / max_value) * ease
		var base := plot.position.y + plot.size.y
		draw_rect(Rect2(cx - bar - 1.0, base - hk, bar, hk), KILL_COLOR)
		draw_rect(Rect2(cx + 1.0, base - hd, bar, hd), Color(DEATH_COLOR, 0.62))
		if entry.get("won", false):
			draw_circle(Vector2(cx, base + 5.0), 2.5, KILL_COLOR)
		if group >= 28.0:
			draw_string(font, Vector2(cx - group * 0.5, base + 18.0), "M%d" % (i + 1),
				HORIZONTAL_ALIGNMENT_CENTER, group, 11, TEXT_COLOR)
		points.append(Vector2(cx - bar * 0.5, base - hk))

	draw_line(Vector2(plot.position.x, plot.position.y + plot.size.y),
		Vector2(plot.end.x, plot.position.y + plot.size.y), Color(0.30, 0.35, 0.43, 0.8), 1.0)
	if points.size() > 1:
		draw_polyline(points, KILL_COLOR, 2.0, true)
	for point in points:
		draw_circle(point, 2.5, Color("#ffd479"))
