@tool
extends SceneTree
## Generates the OpenShooter UI theme (resources/ui/theme.tres).
##
## Run from the project root:
##   godot --headless --path . --script tools/build_theme.gd
##
## Keeping the theme generated makes the design tokens explicit and easy to
## evolve without hand-editing a large .tres file.

const OUT := "res://resources/ui/theme.tres"

# ---------------------------------------------------------------- palette
const BG := Color("#0b0f14")
const SURFACE := Color(0.066, 0.086, 0.114, 0.92)
const SURFACE_2 := Color(0.086, 0.110, 0.145, 0.96)
const SURFACE_3 := Color(0.115, 0.145, 0.190, 0.96)
const BORDER := Color(0.235, 0.290, 0.365, 1.0)
const BORDER_SOFT := Color(0.165, 0.205, 0.265, 1.0)
const TEXT := Color("#e9eef5")
const TEXT_DIM := Color("#93a1b3")
const TEXT_FAINT := Color("#66758a")
const ACCENT := Color("#f5a524")
const ACCENT_HI := Color("#ffc46b")
const ACCENT_DARK := Color("#b56f0e")
const DANGER := Color("#e5484d")
const OK := Color("#4ade80")

var _regular: Font
var _medium: Font
var _semibold: Font
var _bold: Font
var _cond_medium: Font
var _cond_semibold: Font
var _cond_bold: Font


func _initialize() -> void:
	_regular = load("res://assets/fonts/Barlow-Regular.ttf")
	_medium = load("res://assets/fonts/Barlow-Medium.ttf")
	_semibold = load("res://assets/fonts/Barlow-SemiBold.ttf")
	_bold = load("res://assets/fonts/Barlow-Bold.ttf")
	_cond_medium = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	_cond_semibold = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	_cond_bold = load("res://assets/fonts/BarlowCondensed-Bold.ttf")

	var t := Theme.new()
	t.default_font = _regular
	t.default_font_size = 17
	t.default_base_scale = 1.0

	_build_globals(t)
	_build_buttons(t)
	_build_inputs(t)
	_build_containers(t)
	_build_labels(t)
	_build_hud(t)
	_build_misc(t)

	var err := ResourceSaver.save(t, OUT)
	print("theme saved: ", OUT, " (", err, ")")
	quit(0 if int(err) == 0 else 1)


# ---------------------------------------------------------------- helpers
func _flat(bg: Color, border := Color.TRANSPARENT, radius := 10, border_width := 0, margin_h := 14, margin_v := 10, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 5)
	return s


func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _set_button_styles(t: Theme, type: String, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat) -> void:
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, _empty())


func _style_button(t: Theme, type: String, base_font: Font, font_size: int, radius := 10, margin_h := 18, margin_v := 12, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	t.set_font("font", type, base_font)
	t.set_font_size("font_size", type, font_size)
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, ACCENT_HI)
	t.set_color("font_pressed_color", type, ACCENT_HI)
	t.set_color("font_focus_color", type, TEXT)
	t.set_color("font_disabled_color", type, TEXT_FAINT)
	t.set_color("icon_normal_color", type, TEXT_DIM)
	t.set_color("icon_hover_color", type, ACCENT)
	t.set_color("icon_pressed_color", type, ACCENT_HI)
	t.set_color("icon_disabled_color", type, TEXT_FAINT)
	t.set_constant("icon_max_width", type, 26)
	t.set_constant("h_separation", type, 12)
	t.set_constant("outline_size", type, 0)
	t.set_stylebox("normal", type, _flat(SURFACE, BORDER_SOFT, radius, 1, margin_h, margin_v, 0))
	t.set_stylebox("hover", type, _flat(SURFACE_3, ACCENT, radius, 1, margin_h, margin_v, 6))
	t.set_stylebox("pressed", type, _flat(Color(0.17, 0.14, 0.08, 0.98), ACCENT, radius, 1, margin_h, margin_v, 0))
	t.set_stylebox("disabled", type, _flat(Color(0.06, 0.07, 0.09, 0.75), BORDER_SOFT, radius, 1, margin_h, margin_v, 0))
	t.set_stylebox("focus", type, _empty())


# ---------------------------------------------------------------- globals
func _build_globals(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_font("font", "Label", _regular)
	t.set_font_size("font_size", "Label", 17)
	t.set_stylebox("normal", "Label", _empty())

	t.set_font("normal_font", "RichTextLabel", _regular)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_color("default_color", "RichTextLabel", TEXT)


# ---------------------------------------------------------------- buttons
func _build_buttons(t: Theme) -> void:
	# Default / secondary button.
	_style_button(t, "Button", _semibold, 18, 10, 20, 12)
	t.set_stylebox("hover_pressed", "Button", _flat(Color(0.17, 0.14, 0.08, 0.98), ACCENT, 10, 1, 20, 12))

	# Large navigation button (main menu).
	t.set_type_variation("MenuBtn", "Button")
	_style_button(t, "MenuBtn", _semibold, 21, 12, 24, 15)
	t.set_stylebox("normal", "MenuBtn", _flat(Color(0.055, 0.070, 0.095, 0.82), BORDER_SOFT, 12, 1, 24, 15))
	t.set_stylebox("hover", "MenuBtn", _flat(Color(0.115, 0.145, 0.190, 0.98), ACCENT, 12, 1, 24, 15, 8))

	# Hero cards (mode selection).
	t.set_type_variation("BigButton", "Button")
	_style_button(t, "BigButton", _cond_semibold, 34, 14, 26, 18)
	t.set_stylebox("normal", "BigButton", _flat(Color(0.055, 0.070, 0.095, 0.85), BORDER_SOFT, 14, 1, 26, 18, 0))

	# Small utility button.
	t.set_type_variation("SmallButton", "Button")
	_style_button(t, "SmallButton", _medium, 15, 8, 14, 8)
	t.set_constant("icon_max_width", "SmallButton", 20)

	# Primary action.
	t.set_type_variation("PrimaryButton", "Button")
	_style_button(t, "PrimaryButton", _semibold, 19, 10, 22, 13)
	t.set_color("font_color", "PrimaryButton", Color("#17110a"))
	t.set_color("font_hover_color", "PrimaryButton", Color("#19120a"))
	t.set_color("font_pressed_color", "PrimaryButton", Color("#2a1c06"))
	t.set_color("icon_normal_color", "PrimaryButton", Color("#17110a"))
	t.set_color("icon_hover_color", "PrimaryButton", Color("#19120a"))
	t.set_color("icon_pressed_color", "PrimaryButton", Color("#2a1c06"))
	t.set_stylebox("normal", "PrimaryButton", _flat(ACCENT, ACCENT_HI, 10, 1, 22, 13, 4))
	t.set_stylebox("hover", "PrimaryButton", _flat(ACCENT_HI, Color("#ffe0a3"), 10, 1, 22, 13, 10))
	t.set_stylebox("pressed", "PrimaryButton", _flat(ACCENT_DARK, ACCENT, 10, 1, 22, 13))

	# Destructive action.
	t.set_type_variation("DangerButton", "Button")
	_style_button(t, "DangerButton", _semibold, 18, 10, 20, 12)
	t.set_color("font_hover_color", "DangerButton", Color("#ff8a8d"))
	t.set_color("icon_hover_color", "DangerButton", DANGER)
	t.set_stylebox("normal", "DangerButton", _flat(Color(0.075, 0.040, 0.048, 0.9), Color(0.40, 0.19, 0.22, 1), 10, 1, 20, 12))
	t.set_stylebox("hover", "DangerButton", _flat(Color(0.16, 0.07, 0.08, 0.98), DANGER, 10, 1, 20, 12, 6))
	t.set_stylebox("pressed", "DangerButton", _flat(Color(0.22, 0.08, 0.09, 0.98), DANGER, 10, 1, 20, 12))

	# Mobile touch controls.
	t.set_type_variation("TouchButton", "Button")
	_style_button(t, "TouchButton", _semibold, 14, 14, 6, 4)
	t.set_stylebox("normal", "TouchButton", _flat(Color(0.025, 0.035, 0.050, 0.58), Color(0.55, 0.62, 0.72, 0.55), 14, 1, 6, 4))
	t.set_stylebox("hover", "TouchButton", _flat(Color(0.06, 0.08, 0.10, 0.72), ACCENT, 14, 1, 6, 4, 5))
	t.set_stylebox("pressed", "TouchButton", _flat(Color(0.20, 0.15, 0.07, 0.94), ACCENT, 14, 2, 6, 4, 6))
	t.set_color("font_pressed_color", "TouchButton", Color("#17110a"))
	t.set_color("font_outline_color", "TouchButton", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "TouchButton", 3)

	t.set_type_variation("TouchButtonSmall", "Button")
	_style_button(t, "TouchButtonSmall", _semibold, 12, 10, 5, 3)
	t.set_stylebox("normal", "TouchButtonSmall", _flat(Color(0.025, 0.035, 0.050, 0.58), Color(0.55, 0.62, 0.72, 0.55), 10, 1, 5, 3))
	t.set_stylebox("hover", "TouchButtonSmall", _flat(Color(0.06, 0.08, 0.10, 0.72), ACCENT, 10, 1, 5, 3, 4))
	t.set_stylebox("pressed", "TouchButtonSmall", _flat(Color(0.20, 0.15, 0.07, 0.94), ACCENT, 10, 2, 5, 3))
	t.set_color("font_pressed_color", "TouchButtonSmall", Color("#17110a"))
	t.set_color("font_outline_color", "TouchButtonSmall", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "TouchButtonSmall", 2)

	t.set_type_variation("TouchButtonFire", "Button")
	_style_button(t, "TouchButtonFire", _bold, 18, 18, 10, 8)
	t.set_stylebox("normal", "TouchButtonFire", _flat(Color(0.96, 0.65, 0.14, 0.82), ACCENT_HI, 18, 2, 10, 8, 6))
	t.set_stylebox("hover", "TouchButtonFire", _flat(ACCENT_HI, Color("#fff0c8"), 18, 2, 10, 8, 10))
	t.set_stylebox("pressed", "TouchButtonFire", _flat(ACCENT_DARK, ACCENT, 18, 2, 10, 8))
	t.set_color("font_color", "TouchButtonFire", Color("#17110a"))
	t.set_color("font_hover_color", "TouchButtonFire", Color("#17110a"))
	t.set_color("font_pressed_color", "TouchButtonFire", Color("#17110a"))
	t.set_constant("outline_size", "TouchButtonFire", 0)

	# Small +/- buttons used by numeric steppers.
	t.set_type_variation("StepButton", "Button")
	_style_button(t, "StepButton", _cond_bold, 22, 6, 5, 1)
	t.set_stylebox("normal", "StepButton", _flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 6, 0, 5, 1))
	t.set_stylebox("hover", "StepButton", _flat(Color(0.16, 0.13, 0.07, 0.95), ACCENT_DARK, 6, 1, 5, 1))
	t.set_stylebox("pressed", "StepButton", _flat(Color(0.24, 0.18, 0.06, 0.95), ACCENT, 6, 1, 5, 1))
	t.set_stylebox("disabled", "StepButton", _flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 6, 0, 5, 1))
	t.set_constant("icon_max_width", "StepButton", 18)

	# Transparent / back button.
	t.set_type_variation("GhostButton", "Button")
	_style_button(t, "GhostButton", _medium, 16, 8, 16, 10)
	t.set_stylebox("normal", "GhostButton", _flat(Color(0.04, 0.05, 0.07, 0.55), BORDER_SOFT, 8, 1, 16, 10))
	t.set_stylebox("hover", "GhostButton", _flat(Color(0.09, 0.11, 0.15, 0.9), BORDER, 8, 1, 16, 10, 4))

	# Toggle buttons used by the voting list.
	t.set_type_variation("VoteButton", "Button")
	_style_button(t, "VoteButton", _medium, 17, 9, 16, 11)
	t.set_stylebox("normal", "VoteButton", _flat(Color(0.05, 0.065, 0.09, 0.85), BORDER_SOFT, 9, 1, 16, 11))
	t.set_stylebox("hover", "VoteButton", _flat(Color(0.10, 0.125, 0.165, 0.98), ACCENT, 9, 1, 16, 11, 4))
	t.set_stylebox("pressed", "VoteButton", _flat(Color(0.19, 0.15, 0.07, 0.98), ACCENT, 9, 1, 16, 11))


# ---------------------------------------------------------------- inputs
func _build_inputs(t: Theme) -> void:
	var normal := _flat(Color(0.035, 0.045, 0.060, 0.92), BORDER_SOFT, 9, 1, 14, 10)
	var focus := _flat(Color(0.045, 0.058, 0.075, 0.98), ACCENT, 9, 1, 14, 10, 4)
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", _flat(Color(0.03, 0.04, 0.05, 0.6), BORDER_SOFT, 9, 1, 14, 10))
	t.set_font("font", "LineEdit", _medium)
	t.set_font_size("font_size", "LineEdit", 18)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("font_selected_color", "LineEdit", Color("#17110a"))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", ACCENT_HI)
	t.set_color("clear_button_color", "LineEdit", TEXT_DIM)
	t.set_color("clear_button_color_pressed", "LineEdit", ACCENT)

	# Private-code field.
	t.set_type_variation("CodeEdit5", "LineEdit")
	t.set_font("font", "CodeEdit5", _cond_bold)
	t.set_font_size("font_size", "CodeEdit5", 44)
	t.set_color("font_color", "CodeEdit5", ACCENT_HI)
	t.set_color("font_placeholder_color", "CodeEdit5", TEXT_FAINT)
	t.set_constant("outline_size", "CodeEdit5", 0)

	# Dropdowns share the button look.
	for type in ["OptionButton"]:
		_style_button(t, type, _semibold, 17, 9, 16, 10, HORIZONTAL_ALIGNMENT_LEFT)
		t.set_constant("arrow_margin", type, 14)
	t.set_type_variation("OptionButtonSm", "OptionButton")
	_style_button(t, "OptionButtonSm", _medium, 15, 8, 12, 8, HORIZONTAL_ALIGNMENT_LEFT)

	# SpinBox inner line edit.
	t.set_type_variation("SpinBoxField", "LineEdit")
	t.set_font("font", "SpinBoxField", _cond_semibold)
	t.set_font_size("font_size", "SpinBoxField", 20)

	# Checkbox.
	t.set_font("font", "CheckBox", _medium)
	t.set_font_size("font_size", "CheckBox", 17)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", ACCENT_HI)
	t.set_color("font_pressed_color", "CheckBox", ACCENT_HI)
	t.set_color("font_focus_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", _empty())
	t.set_stylebox("hover", "CheckBox", _empty())
	t.set_stylebox("pressed", "CheckBox", _empty())
	t.set_stylebox("focus", "CheckBox", _empty())
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_icon("checked", "CheckBox", load("res://assets/ui/icons/check_checked.svg"))
	t.set_icon("unchecked", "CheckBox", load("res://assets/ui/icons/check_unchecked.svg"))
	t.set_icon("checked_disabled", "CheckBox", load("res://assets/ui/icons/check_checked_disabled.svg"))
	t.set_icon("unchecked_disabled", "CheckBox", load("res://assets/ui/icons/check_unchecked_disabled.svg"))

	# Slider.
	var track := _flat(Color(0.055, 0.070, 0.090, 1.0), BORDER_SOFT, 4, 0, 0, 2)
	track.content_margin_left = 0
	track.content_margin_right = 0
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _flat(ACCENT, Color.TRANSPARENT, 4, 0, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT_HI, Color.TRANSPARENT, 4, 0, 0, 2))
	t.set_icon("grabber", "HSlider", load("res://assets/ui/icons/slider_grabber.svg"))
	t.set_icon("grabber_highlight", "HSlider", load("res://assets/ui/icons/slider_grabber_highlight.svg"))
	t.set_constant("center_grabber", "HSlider", 0)

	# Popup menu.
	t.set_stylebox("panel", "PopupMenu", _flat(Color(0.055, 0.070, 0.090, 0.99), BORDER, 10, 1, 10, 8, 12))
	t.set_stylebox("hover", "PopupMenu", _flat(Color(0.14, 0.12, 0.07, 0.98), ACCENT_DARK, 6, 0, 8, 6))
	t.set_font("font", "PopupMenu", _medium)
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT_HI)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 10)

	# Scroll bars.
	t.set_stylebox("scroll", "VScrollBar", _flat(Color(0.03, 0.04, 0.05, 0.6), Color.TRANSPARENT, 4, 0, 0, 0))
	t.set_stylebox("grabber", "VScrollBar", _flat(Color(0.22, 0.27, 0.34, 0.9), Color.TRANSPARENT, 4, 0, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(ACCENT_DARK, Color.TRANSPARENT, 4, 0, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(ACCENT, Color.TRANSPARENT, 4, 0, 0, 0))
	t.set_stylebox("scroll", "HScrollBar", _flat(Color(0.03, 0.04, 0.05, 0.6), Color.TRANSPARENT, 4, 0, 0, 0))
	t.set_stylebox("grabber", "HScrollBar", _flat(Color(0.22, 0.27, 0.34, 0.9), Color.TRANSPARENT, 4, 0, 0, 0))


# ---------------------------------------------------------------- containers
func _build_containers(t: Theme) -> void:
	t.set_stylebox("panel", "PanelContainer", _flat(SURFACE_2, BORDER_SOFT, 12, 1, 18, 16))

	# Hero card with a soft shadow.
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _flat(SURFACE, BORDER_SOFT, 16, 1, 24, 22, 18))

	# Flat section used inside cards.
	t.set_type_variation("SubCard", "PanelContainer")
	t.set_stylebox("panel", "SubCard", _flat(Color(0.045, 0.058, 0.075, 0.92), BORDER_SOFT, 11, 1, 16, 12))

	# List row (server list, results).
	# Opaque card for modal windows (pause, vote, scoreboard).
	t.set_type_variation("ModalCard", "PanelContainer")
	t.set_stylebox("panel", "ModalCard", _flat(Color(0.034, 0.044, 0.059, 0.975), BORDER, 16, 1, 24, 22, 22))

	t.set_type_variation("Row", "PanelContainer")
	t.set_stylebox("panel", "Row", _flat(Color(0.05, 0.065, 0.085, 0.86), BORDER_SOFT, 10, 1, 14, 10, 4))

	# Numeric stepper field.
	t.set_type_variation("Stepper", "PanelContainer")
	t.set_stylebox("panel", "Stepper", _flat(Color(0.028, 0.036, 0.048, 0.94), BORDER_SOFT, 9, 1, 4, 3))

	# Scoreboard rows.
	t.set_type_variation("ScoreRowPanel", "PanelContainer")
	t.set_stylebox("panel", "ScoreRowPanel", _flat(Color(0.055, 0.070, 0.090, 0.55), Color.TRANSPARENT, 7, 0, 12, 5))
	t.set_type_variation("ScoreRowPanelAlt", "PanelContainer")
	t.set_stylebox("panel", "ScoreRowPanelAlt", _flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 7, 0, 12, 5))

	# In-match hotbar.
	t.set_type_variation("HotbarSlot", "PanelContainer")
	t.set_stylebox("panel", "HotbarSlot", _flat(Color(0.035, 0.045, 0.060, 0.72), BORDER_SOFT, 8, 1, 10, 5))
	t.set_type_variation("HotbarSlotActive", "PanelContainer")
	t.set_stylebox("panel", "HotbarSlotActive", _flat(Color(0.18, 0.14, 0.07, 0.96), ACCENT, 8, 1, 10, 5, 6))

	t.set_type_variation("TopBarPanel", "PanelContainer")
	t.set_stylebox("panel", "TopBarPanel", _flat(Color(0.035, 0.045, 0.060, 0.72), BORDER_SOFT, 12, 1, 20, 8))

	# Kill feed chip.
	t.set_type_variation("FeedChip", "PanelContainer")
	t.set_stylebox("panel", "FeedChip", _flat(Color(0.035, 0.045, 0.060, 0.78), BORDER_SOFT, 8, 1, 12, 6))


# ---------------------------------------------------------------- labels
func _label(t: Theme, type: String, font: Font, size: int, color: Color, outline := 0, outline_color := Color(0, 0, 0, 0.85)) -> void:
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, color)
	t.set_constant("outline_size", type, outline)
	if outline > 0:
		t.set_color("font_outline_color", type, outline_color)


func _build_labels(t: Theme) -> void:
	t.set_type_variation("HeroLabel", "Label")
	_label(t, "HeroLabel", _cond_bold, 104, TEXT, 0)
	t.set_constant("line_spacing", "HeroLabel", 0)

	t.set_type_variation("TitleLabel", "Label")
	_label(t, "TitleLabel", _cond_bold, 54, TEXT, 0)

	t.set_type_variation("TitleSmall", "Label")
	_label(t, "TitleSmall", _cond_semibold, 30, TEXT, 0)

	t.set_type_variation("SubtitleLabel", "Label")
	_label(t, "SubtitleLabel", _medium, 20, TEXT_DIM, 0)

	t.set_type_variation("SectionLabel", "Label")
	_label(t, "SectionLabel", _semibold, 13, ACCENT, 0)

	t.set_type_variation("FieldLabel", "Label")
	_label(t, "FieldLabel", _medium, 17, TEXT_DIM, 0)

	t.set_type_variation("HintLabel", "Label")
	_label(t, "HintLabel", _regular, 15, TEXT_DIM, 0)

	t.set_type_variation("Caption", "Label")
	_label(t, "Caption", _medium, 12, TEXT_FAINT, 0)

	t.set_type_variation("BrandLabel", "Label")
	_label(t, "BrandLabel", _cond_bold, 28, TEXT, 0)

	t.set_type_variation("StatusOk", "Label")
	_label(t, "StatusOk", _semibold, 16, OK, 0)
	t.set_stylebox("normal", "StatusOk", _flat(Color(0.035, 0.07, 0.05, 0.88), Color(0.24, 0.5, 0.32, 0.8), 8, 1, 14, 6))

	t.set_type_variation("StatusError", "Label")
	_label(t, "StatusError", _semibold, 16, Color("#ff8a8d"), 0)
	t.set_stylebox("normal", "StatusError", _flat(Color(0.08, 0.035, 0.04, 0.88), Color(0.5, 0.24, 0.26, 0.8), 8, 1, 14, 6))

	t.set_type_variation("Gold", "Label")
	_label(t, "Gold", _semibold, 15, Color("#f5c451"), 0)
	t.set_type_variation("Silver", "Label")
	_label(t, "Silver", _semibold, 15, Color("#c3ccd8"), 0)
	t.set_type_variation("Bronze", "Label")
	_label(t, "Bronze", _semibold, 15, Color("#c98d5a"), 0)

	t.set_type_variation("ScoreHeader", "Label")
	_label(t, "ScoreHeader", _semibold, 12, TEXT_FAINT, 0)
	t.set_type_variation("ScoreRow", "Label")
	_label(t, "ScoreRow", _medium, 16, TEXT, 0)
	t.set_type_variation("ScoreRowMine", "Label")
	_label(t, "ScoreRowMine", _semibold, 16, ACCENT, 0)

	t.set_type_variation("FeedLabel", "Label")
	_label(t, "FeedLabel", _medium, 14, TEXT, 4)


# ---------------------------------------------------------------- hud
func _build_hud(t: Theme) -> void:
	t.set_type_variation("HudBig", "Label")
	_label(t, "HudBig", _cond_bold, 46, TEXT, 5)
	t.set_type_variation("HudLabel", "Label")
	_label(t, "HudLabel", _semibold, 18, TEXT, 4)
	t.set_type_variation("HudSmall", "Label")
	_label(t, "HudSmall", _medium, 13, TEXT_DIM, 3)
	t.set_type_variation("HudAccent", "Label")
	_label(t, "HudAccent", _cond_semibold, 20, ACCENT_HI, 4)

	t.set_type_variation("ProgressBarHealth", "ProgressBar")
	# Base fill; Hud duplicates and recolors this stylebox at runtime.
	t.set_stylebox("background", "ProgressBar", _flat(Color(0.025, 0.035, 0.045, 0.82), BORDER_SOFT, 6, 1, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _flat(OK, Color.TRANSPARENT, 6, 0, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font("font", "ProgressBar", _semibold)
	t.set_font_size("font_size", "ProgressBar", 14)

	t.set_type_variation("TimeBar", "ProgressBar")
	t.set_stylebox("background", "TimeBar", _flat(Color(0.03, 0.04, 0.055, 0.75), Color.TRANSPARENT, 3, 0, 0, 0))
	t.set_stylebox("fill", "TimeBar", _flat(ACCENT, Color.TRANSPARENT, 3, 0, 0, 0))

	t.set_type_variation("HealthBar", "ProgressBar")
	t.set_stylebox("background", "HealthBar", _flat(Color(0.025, 0.035, 0.045, 0.88), BORDER_SOFT, 7, 1, 0, 0))
	t.set_stylebox("fill", "HealthBar", _flat(OK, Color.TRANSPARENT, 7, 0, 0, 0))


# ---------------------------------------------------------------- misc
func _build_misc(t: Theme) -> void:
	t.set_stylebox("panel", "TooltipPanel", _flat(Color(0.04, 0.05, 0.065, 0.97), BORDER, 8, 1, 10, 6, 8))
	t.set_font("font", "TooltipLabel", _medium)
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_stylebox("panel", "PopupPanel", _flat(Color(0.04, 0.05, 0.065, 0.98), BORDER, 10, 1, 12, 10, 12))

	# Selection/menu focus color used by BaseButton defaults.
	t.set_color("font_color", "LinkButton", ACCENT)
	t.set_color("font_hover_color", "LinkButton", ACCENT_HI)

	# Separators.
	t.set_stylebox("separator", "HSeparator", _flat(BORDER_SOFT, Color.TRANSPARENT, 0, 0, 0, 0))
	t.set_constant("separation", "HSeparator", 18)
	t.set_stylebox("separator", "VSeparator", _flat(BORDER_SOFT, Color.TRANSPARENT, 0, 0, 0, 0))
	t.set_constant("separation", "VSeparator", 18)
