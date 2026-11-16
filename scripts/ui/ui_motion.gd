class_name UiMotion
## Small shared animations for buttons, panels and screens.

## Adds a gentle hover/press scale to a control.
static func attach(control: Control, hover_scale := 1.012) -> void:
	if control == null or control.has_meta("ui_motion"):
		return
	control.set_meta("ui_motion", true)
	control.mouse_entered.connect(func(): _scale(control, hover_scale, 0.12))
	control.mouse_exited.connect(func(): _scale(control, 1.0, 0.14))
	if control is BaseButton:
		control.button_down.connect(func(): _scale(control, 0.99, 0.06))
		control.button_up.connect(func(): _scale(control, 1.0, 0.1))


## Fades in and scales a modal/panel from 97% to 100%.
static func pop_in(control: Control, duration := 0.18) -> void:
	if control == null:
		return
	control.pivot_offset = control.size / 2.0
	control.modulate.a = 0.0
	control.scale = Vector2(0.97, 0.97)
	if control.has_meta("ui_pop_tween"):
		var old := control.get_meta("ui_pop_tween") as Tween
		if old and old.is_valid():
			old.kill()
	var t := control.create_tween().set_parallel()
	control.set_meta("ui_pop_tween", t)
	t.tween_property(control, "modulate:a", 1.0, duration * 0.8)
	t.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Slides a screen's content up into place while fading in.
static func slide_in(control: Control, distance := 16.0, duration := 0.24) -> void:
	if control == null:
		return
	# Remember the designer offsets once, so fast screen switching cannot drift
	# the layout.
	if not control.has_meta("ui_base_top"):
		control.set_meta("ui_base_top", control.offset_top)
		control.set_meta("ui_base_bottom", control.offset_bottom)
	var top: float = control.get_meta("ui_base_top")
	var bottom: float = control.get_meta("ui_base_bottom")
	if control.has_meta("ui_slide_tween"):
		var old := control.get_meta("ui_slide_tween") as Tween
		if old and old.is_valid():
			old.kill()
	control.offset_top = top + distance
	control.offset_bottom = bottom + distance
	control.modulate.a = 0.0
	var t := control.create_tween().set_parallel()
	control.set_meta("ui_slide_tween", t)
	t.tween_property(control, "offset_top", top, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(control, "offset_bottom", bottom, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(control, "modulate:a", 1.0, duration * 0.8)


static func _scale(control: Control, factor: float, duration: float) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size / 2.0
	if control.has_meta("ui_scale_tween"):
		var old := control.get_meta("ui_scale_tween") as Tween
		if old and old.is_valid():
			old.kill()
	var t := control.create_tween()
	control.set_meta("ui_scale_tween", t)
	t.tween_property(control, "scale", Vector2.ONE * factor, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Cascading entrance: buttons, cards and loose labels inside `root` fade and
## settle into place one after another.
static func stagger(root: Control, step := 0.035, duration := 0.26, max_items := 18) -> void:
	if root == null:
		return
	var items: Array[Control] = []
	_collect_items(root, items, max_items)
	for c in items:
		_kill_meta_tween(c, "ui_stagger_tween")
		c.modulate.a = 0.0
	# Wait one frame so containers have laid out and sizes (pivots) are valid.
	(func():
		for i in items.size():
			var c := items[i]
			if not is_instance_valid(c):
				continue
			c.pivot_offset = c.size / 2.0
			c.scale = Vector2(0.965, 0.965)
			_kill_meta_tween(c, "ui_scale_tween")
			var t := c.create_tween().set_parallel()
			c.set_meta("ui_stagger_tween", t)
			var delay := i * step
			t.tween_property(c, "modulate:a", 1.0, duration * 0.8).set_delay(delay)
			t.tween_property(c, "scale", Vector2.ONE, duration).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	).call_deferred()


static func _collect_items(node: Node, out: Array[Control], max_items: int) -> void:
	for child in node.get_children():
		if out.size() >= max_items:
			return
		var c := child as Control
		if c == null or not c.visible:
			continue
		if c is BaseButton or c is PanelContainer or c is Label or c is TextureRect:
			out.append(c)
		elif c is Container:
			_collect_items(c, out, max_items)


static func _kill_meta_tween(control: Control, key: String) -> void:
	if control.has_meta(key):
		var old := control.get_meta(key) as Tween
		if old and old.is_valid():
			old.kill()
