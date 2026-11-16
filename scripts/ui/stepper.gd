class_name Stepper
extends PanelContainer
## Compact numeric field with minus/plus buttons and an animated value.
## Used by the server creation screen for bot and player counts.

signal value_changed(value: int)

@export var min_value := 0:
	set(v):
		min_value = v
		if _built:
			value = clampi(value, min_value, max_value)
@export var max_value := 10:
	set(v):
		max_value = v
		if _built:
			value = clampi(value, min_value, max_value)
@export var value := 0:
	set(v):
		var clamped := clampi(v, min_value, max_value)
		if clamped == value:
			return
		value = clamped
		if _number:
			_number.text = str(value)
		if _built:
			value_changed.emit(value)
			_update_buttons()
@export var step := 1
@export var editable := true:
	set(v):
		editable = v
		_update_buttons()

var _number: AnimatedNumber
var _minus: Button
var _plus: Button
var _built := false


func _ready() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_minus = _make_button("−", -1)
	box.add_child(_minus)
	_number = AnimatedNumber.new()
	_number.font_variation = &"HudAccent"
	_number.font_size = 20
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.custom_minimum_size = Vector2(52, 26)
	_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_number.initial_text = str(value)
	box.add_child(_number)
	_plus = _make_button("+", 1)
	box.add_child(_plus)
	_built = true
	value = clampi(value, min_value, max_value)
	_number.text = str(value)
	_update_buttons()


func _make_button(label: String, direction: int) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(34, 30)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"StepButton"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func(): _step(direction))
	UiMotion.attach(button)
	return button


func _step(direction: int) -> void:
	if editable:
		value += direction * step


func _update_buttons() -> void:
	if not _built:
		return
	_minus.disabled = not editable or value <= min_value
	_plus.disabled = not editable or value >= max_value
