class_name HotbarSlot
extends PanelContainer
## One slot of the weapon hotbar (scenes/ui/hotbar_slot.tscn).

@onready var number_label: Label = %Number
@onready var name_label: Label = %WeaponName

var _selected := false
var _tween: Tween


func setup(number: int, weapon_name: String) -> void:
	number_label.text = str(number)
	name_label.text = weapon_name


func set_selected(selected: bool) -> void:
	if selected == _selected:
		return
	_selected = selected
	theme_type_variation = &"HotbarSlotActive" if selected else &"HotbarSlot"
	# The active slot pops up slightly; the previous one settles back.
	pivot_offset = Vector2(size.x / 2.0, size.y)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if selected:
		scale = Vector2(0.94, 0.94)
		_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
