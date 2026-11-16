extends Node
## Custom mouse cursors for the whole game: tactical arrow and text caret.
## Uses the SVG assets under assets/ui/cursors/.

const ARROW_PATH := "res://assets/ui/cursors/arrow.svg"
const IBEAM_PATH := "res://assets/ui/cursors/ibeam.svg"

const ARROW_HOTSPOT := Vector2(4, 3)
const IBEAM_HOTSPOT := Vector2(16, 16)

var _arrow: Texture2D
var _ibeam: Texture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile"):
		set_process(false)
		return
	_arrow = load(ARROW_PATH)
	_ibeam = load(IBEAM_PATH)
	Input.set_custom_mouse_cursor(_arrow, Input.CURSOR_ARROW, ARROW_HOTSPOT)
	Input.set_custom_mouse_cursor(_ibeam, Input.CURSOR_IBEAM, IBEAM_HOTSPOT)
	# Make every button and slider feel like a clickable control.
	get_tree().node_added.connect(_style_cursor)
	_style_tree(get_tree().root)


func _exit_tree() -> void:
	# Release the cursor textures before the renderer shuts down.
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_IBEAM)
	_arrow = null
	_ibeam = null


func _style_tree(node: Node) -> void:
	_style_cursor(node)
	for child in node.get_children():
		_style_tree(child)


func _style_cursor(node: Node) -> void:
	# Buttons keep the standard arrow cursor; only text fields need the I-beam.
	if node is LineEdit:
		(node as Control).mouse_default_cursor_shape = Control.CURSOR_IBEAM
