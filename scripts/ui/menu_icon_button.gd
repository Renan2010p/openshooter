class_name MenuIconButton
extends Button
## Large navigation button with an animated icon and a label, matching the
## selected theme variation (text and icon colors follow normal/hover states).

@export var label_text := "":
	set(v):
		label_text = v
		if _label:
			_label.text = v
@export var icon_texture: Texture2D:
	set(v):
		icon_texture = v
		if _icon:
			_icon.texture = v
@export var icon_size := 24.0
@export var text_offset := 58.0
## Label font size; 0 uses the theme variation's size.
@export var label_font_size := 0

var _icon: AnimatedIcon
var _label: Label


func _ready() -> void:
	UiMotion.attach(self)
	text = ""
	icon = null
	_build_icon()
	_build_label()
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	_set_hover(false)
	# Theme colors may not be propagated yet on the first frame.
	_set_hover.call_deferred(false)


func _build_icon() -> void:
	_icon = AnimatedIcon.new()
	_icon.texture = icon_texture
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.anchor_top = 0.5
	_icon.anchor_bottom = 0.5
	_icon.offset_left = 20.0
	_icon.offset_right = 20.0 + icon_size
	_icon.offset_top = -icon_size / 2.0
	_icon.offset_bottom = icon_size / 2.0
	_icon.modulate = get_theme_color("icon_normal_color", theme_type_variation)
	add_child(_icon)


func _build_label() -> void:
	_label = Label.new()
	_label.text = label_text
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = text_offset
	_label.offset_right = -16.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", get_theme_font("font", theme_type_variation))
	var font_size := label_font_size if label_font_size > 0 else get_theme_font_size("font_size", theme_type_variation)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", get_theme_color("font_color", theme_type_variation))
	add_child(_label)


func _set_hover(on: bool) -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color", get_theme_color("font_hover_color" if on else "font_color", theme_type_variation))
	if _icon:
		_icon.modulate = get_theme_color("icon_hover_color" if on else "icon_normal_color", theme_type_variation)
