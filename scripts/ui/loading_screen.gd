class_name LoadingScreen
extends CanvasLayer
## Full-screen loading screen used while a match scene and its map are loaded.

@onready var root: Control = $Root
@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
@onready var progress_bar: ProgressBar = %Progress
@onready var status_label: Label = %Status
@onready var percent_label: Label = %Percent


func _ready() -> void:
	visible = false


func begin(title: String, subtitle: String) -> void:
	visible = true
	root.modulate.a = 0.0
	title_label.text = title
	subtitle_label.text = subtitle
	set_progress(0.0, "PREPARING")
	var t := create_tween()
	t.tween_property(root, "modulate:a", 1.0, 0.2)


func set_progress(value: float, status := "") -> void:
	var v := clampf(value, 0.0, 1.0)
	progress_bar.value = v
	percent_label.text = "%d%%" % int(v * 100.0)
	if status != "":
		status_label.text = status


func finish() -> void:
	set_progress(1.0, "READY")
	await get_tree().create_timer(0.28).timeout
	var t := create_tween()
	t.tween_property(root, "modulate:a", 0.0, 0.35)
	await t.finished
	visible = false


func hide_now() -> void:
	visible = false
	root.modulate.a = 1.0
