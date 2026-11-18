class_name ChatBox
extends Control
## In-match chat (see Net.send_chat()): the last lines over the game, fading
## after a few seconds, and a text field opened with T or ENTER (the chat
## button on phones). ESC or ENTER on an empty line closes it.
##
## While the field is open the mouse is free (desktop), so the player stops
## moving: Player reads its keys only with the mouse captured.

## The field opened or closed.
signal typing_changed(on: bool)

## Seconds a line stays over the game, then FADE seconds to disappear.
const LINE_SECONDS := 9.0
const FADE := 1.2
## Lines shown at once (all of them while typing, the recent ones otherwise).
const VISIBLE_LINES := 8
## Lines kept for scrolling back while typing.
const HISTORY := 40
const SELF_COLOR := Color("#ff8a1f")
## Names of the other players, picked by player id so a name keeps its color.
const NAME_COLORS := [Color("#a9d8ff"), Color("#ffd27a"), Color("#b8f0c0"),
	Color("#ffb3c1"), Color("#d9c2ff"), Color("#9ff0e8")]
const FONT := preload("res://assets/fonts/Barlow-SemiBold.ttf")
const NAME_FONT := preload("res://assets/fonts/Barlow-Bold.ttf")

## True while the text field is open.
var typing := false
## Set by the Hud: whether the chat may open now (not in the pause menu).
var can_open: Callable = func() -> bool: return true

var _panel: PanelContainer
var _lines: VBoxContainer
var _field: LineEdit
## [{label: RichTextLabel, age: float}], oldest first.
var _entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.043, 0.047, 0.063, 0.72)
	back.border_color = Color(1, 1, 1, 0.12)
	back.border_width_left = 3
	back.set_content_margin_all(10)
	back.corner_radius_top_right = 12
	back.corner_detail = 1
	_panel.add_theme_stylebox_override("panel", back)
	_panel.self_modulate.a = 0.0
	add_child(_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.alignment = BoxContainer.ALIGNMENT_END
	_lines.add_theme_constant_override("separation", 2)
	_lines.clip_contents = true
	column.add_child(_lines)

	_field = LineEdit.new()
	_field.max_length = Net.CHAT_MAX
	_field.placeholder_text = "Message everyone" if Touch.active \
		else "Message everyone  ·  ENTER to send, ESC to close"
	_field.add_theme_font_size_override("font_size", 15)
	_field.context_menu_enabled = false
	_field.visible = false
	_field.text_submitted.connect(_submit)
	_field.focus_exited.connect(close)
	column.add_child(_field)

	Net.chat_received.connect(_on_message)


func open() -> void:
	if typing or not can_open.call():
		return
	typing = true
	_field.text = ""
	_field.visible = true
	_panel.self_modulate.a = 1.0
	_field.grab_focus.call_deferred()
	typing_changed.emit(true)


func close() -> void:
	if not typing:
		return
	typing = false
	_field.visible = false
	_panel.self_modulate.a = 0.0
	if _field.has_focus():
		_field.release_focus()
	typing_changed.emit(false)


func _submit(text: String) -> void:
	Net.send_chat(text)
	close()


func _input(event: InputEvent) -> void:
	# ESC closes the chat before the pause menu sees it.
	if typing and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not typing and is_visible_in_tree() and event.is_action_pressed("chat") and not event.is_echo():
		get_viewport().set_input_as_handled()
		open()


func _on_message(sender: int, text: String) -> void:
	if text.is_empty():
		return
	var info: Dictionary = Net.players.get(sender, {})
	var who := str(info.get("name", "Player"))
	var me := multiplayer.has_multiplayer_peer() and sender == multiplayer.get_unique_id()
	var color: Color = SELF_COLOR if me else NAME_COLORS[absi(sender) % NAME_COLORS.size()]
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", FONT)
	label.add_theme_font_override("bold_font", NAME_FONT)
	label.add_theme_font_size_override("normal_font_size", 15)
	label.add_theme_font_size_override("bold_font_size", 15)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_color_override("default_color", Color("#f2f1ec"))
	# Names and text come from other players: escape BBCode.
	label.text = "[b][color=#%s]%s[/color][/b]  %s" % [color.to_html(false), _escape(who), _escape(text)]
	_lines.add_child(label)
	_entries.append({"label": label, "age": 0.0})
	while _entries.size() > HISTORY:
		(_entries.pop_front().label as Node).queue_free()
	UiMotion.pop_in(label, 0.16)
	if not me:
		Sfx.play("beep", -18.0, 1.6)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _process(delta: float) -> void:
	var count := _entries.size()
	for i in count:
		var entry: Dictionary = _entries[i]
		entry.age += delta
		var label := entry.label as RichTextLabel
		var recent := i >= count - VISIBLE_LINES
		var alpha := 1.0 if typing else clampf((LINE_SECONDS + FADE - float(entry.age)) / FADE, 0.0, 1.0)
		label.visible = recent and alpha > 0.0
		label.modulate.a = alpha
