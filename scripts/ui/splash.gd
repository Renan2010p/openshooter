extends Control
## Startup credit sequence: RL PROJECTS, then the author credit, then the menu.
## Test runs skip it so screenshots and automated matches start immediately.

const MAIN_SCENE := "res://scenes/main.tscn"

var _leaving := false

@onready var phase1: VBoxContainer = %Phase1
@onready var phase2: VBoxContainer = %Phase2
@onready var skip_hint: Label = %SkipHint


func _ready() -> void:
	Holiday.dress_logo($Center/Phase1/Logo)
	if not OS.get_cmdline_user_args().is_empty():
		_go_main()
		return
	_play_sequence()


func _play_sequence() -> void:
	phase1.modulate.a = 0.0
	phase2.visible = false
	skip_hint.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(phase1, "modulate:a", 1.0, 0.65)
	t.parallel().tween_property(skip_hint, "modulate:a", 0.65, 0.65)
	await t.finished
	await get_tree().create_timer(0.85).timeout
	t = create_tween()
	t.tween_property(phase1, "modulate:a", 0.0, 0.35)
	await t.finished
	phase1.visible = false
	phase2.visible = true
	phase2.modulate.a = 0.0
	t = create_tween()
	t.tween_property(phase2, "modulate:a", 1.0, 0.55)
	await t.finished
	await get_tree().create_timer(1.35).timeout
	t = create_tween()
	t.tween_property(phase2, "modulate:a", 0.0, 0.4)
	t.parallel().tween_property(skip_hint, "modulate:a", 0.0, 0.4)
	await t.finished
	_go_main()


func _go_main() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	if event is InputEventKey and event.pressed:
		_go_main()
	elif event is InputEventMouseButton and event.pressed:
		_go_main()
	elif event is InputEventScreenTouch and event.pressed:
		_go_main()
