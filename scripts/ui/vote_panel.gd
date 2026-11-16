class_name VotePanel
extends PanelContainer
## Map and mode voting before each match (scenes/ui/vote_panel.tscn).
## Buttons are created from MapDB and ModeDB.

signal voted(map_idx: int, mode_idx: int)

var _map_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _map := -1
var _mode := -1


func _ready() -> void:
	for i in MapDB.count():
		var b := _option(%MapList, MapDB.display_name(i))
		b.pressed.connect(func(): _pick_map(i))
		_map_buttons.append(b)
	for i in ModeDB.count():
		var b := _option(%ModeList, ModeDB.get_mode(i).display_name)
		b.pressed.connect(func(): _pick_mode(i))
		b.mouse_entered.connect(func(): %ModeDescription.text = ModeDB.get_mode(i).description)
		_mode_buttons.append(b)
	%ModeDescription.text = "Hover over a mode to see how it works."


func _option(list: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"VoteButton"
	UiMotion.attach(b)
	list.add_child(b)
	return b


## Starts a new vote (clears the choices).
func reset() -> void:
	_map = -1
	_mode = -1
	for b in _map_buttons + _mode_buttons:
		b.button_pressed = false


func _pick_map(i: int) -> void:
	_map = i
	for j in _map_buttons.size():
		_map_buttons[j].button_pressed = j == i
	Sfx.play("switch", -8.0)
	voted.emit(_map, _mode)


func _pick_mode(i: int) -> void:
	_mode = i
	for j in _mode_buttons.size():
		_mode_buttons[j].button_pressed = j == i
	%ModeDescription.text = ModeDB.get_mode(i).description
	Sfx.play("switch", -8.0)
	voted.emit(_map, _mode)


## Updates the timer and vote counts.
func show_state(seconds: float, map_votes: Dictionary, mode_votes: Dictionary) -> void:
	%VoteTimer.text = "Match starts in %d s" % ceili(seconds)
	for i in _map_buttons.size():
		_map_buttons[i].text = "%s   (%d)" % [MapDB.display_name(i), int(map_votes.get(i, 0))]
	for i in _mode_buttons.size():
		_mode_buttons[i].text = "%s   (%d)" % [ModeDB.get_mode(i).display_name, int(mode_votes.get(i, 0))]
