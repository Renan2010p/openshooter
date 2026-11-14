class_name HotbarSlot
extends PanelContainer
## Um espaço da barra de armas (scenes/ui/hotbar_slot.tscn).

@onready var number_label: Label = %Number
@onready var name_label: Label = %WeaponName

var _selected := false


func setup(number: int, weapon_name: String) -> void:
	number_label.text = str(number)
	name_label.text = weapon_name


func set_selected(selected: bool) -> void:
	if selected == _selected:
		return
	_selected = selected
	theme_type_variation = &"HotbarSlotActive" if selected else &"HotbarSlot"
