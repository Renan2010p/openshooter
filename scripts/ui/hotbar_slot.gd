class_name HotbarSlot
extends PanelContainer
## One slot of the weapon hotbar (scenes/ui/hotbar_slot.tscn): the key number,
## the weapon's silhouette and, for equipment, how many are left. The selected
## slot is bigger and orange, with a dark silhouette.

const SIZE := Vector2(58, 50)
const SIZE_SELECTED := Vector2(76, 62)
const SIZE_SMALL := Vector2(50, 50)
const ICON_LIGHT := Color(1, 1, 1, 0.88)
const ICON_DARK := Color("#111111")
const TEXT_LIGHT := Color("#c4c9d2")

@onready var number_label: Label = %Number
@onready var icon: TextureRect = %Icon
@onready var count_label: Label = %Count

var _selected := false
var _small := false
var _tween: Tween


## `weapon` is the WeaponDB index.
func setup(number: int, weapon: int) -> void:
	var data := WeaponDB.get_data(weapon)
	number_label.text = str(number)
	icon.texture = load("res://assets/ui/weapons/%s.png" % data.resource_path.get_file().get_basename())
	tooltip_text = data.display_name
	_small = data.is_equipment()
	_apply()


## Shows how many are left (equipment only); -1 hides the number.
func set_count(count: int) -> void:
	count_label.visible = count >= 0
	count_label.text = str(count)


func set_selected(selected: bool) -> void:
	if selected == _selected:
		return
	_selected = selected
	_apply()
	# The active slot pops slightly.
	pivot_offset = Vector2(SIZE_SELECTED.x / 2.0, SIZE_SELECTED.y)
	if _tween and _tween.is_valid():
		_tween.kill()
	if selected:
		scale = Vector2(0.92, 0.92)
		_tween = create_tween()
		_tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply() -> void:
	theme_type_variation = &"HotbarSlotActive" if _selected else &"HotbarSlot"
	custom_minimum_size = SIZE_SELECTED if _selected else (SIZE_SMALL if _small else SIZE)
	icon.modulate = ICON_DARK if _selected else ICON_LIGHT
	# Key number in the top-left corner (further in on the active slot,
	# whose corner is cut).
	number_label.position = Vector2(8.0 if _selected else 0.0, -1.0)
	number_label.add_theme_color_override("font_color", ICON_DARK if _selected else TEXT_LIGHT)
	count_label.add_theme_color_override("font_color", ICON_DARK if _selected else Color.WHITE)
