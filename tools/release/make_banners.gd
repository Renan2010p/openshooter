extends SceneTree
## Renders the release-notes banner and the trailer thumbnail with the game
## fonts (see docs/releases/). Backgrounds are frames taken from the trailer.
##
##   godot --path . --script res://tools/release/make_banners.gd -- \
##       BG_BANNER.png BG_THUMB.png OUT_DIR VERSION DURATION
##
## Writes OUT_DIR/banner.png (1600x600) and OUT_DIR/trailer-thumb.png (1280x540).

const ACCENT := Color("#f5a524")
const TEXT := Color("#e9eef5")
const MUTED := Color("#aab4c3")

var version := "1.0"
var duration := "0:59"
var bold_c: Font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
var semi: Font = load("res://assets/fonts/Barlow-SemiBold.ttf")
var medium: Font = load("res://assets/fonts/Barlow-Medium.ttf")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		printerr("usage: -- BG_BANNER BG_THUMB OUT_DIR [VERSION] [DURATION]")
		quit(1)
		return
	if a.size() > 3:
		version = a[3]
	if a.size() > 4:
		duration = a[4]
	await _render(Vector2i(1600, 600), _banner(a[0]), a[2] + "/banner.png")
	await _render(Vector2i(1280, 540), _thumb(a[1]), a[2] + "/trailer-thumb.png")
	quit()


func _render(size: Vector2i, root: Control, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	root.size = size
	vp.add_child(root)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)
	print("saved ", path)
	vp.queue_free()


func _font(base: Font, spacing := 0) -> Font:
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = spacing
	return f


func _label(text: String, font: Font, px: int, color: Color, spacing := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(font, spacing))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _background(path: String, parent: Control, darken: float) -> void:
	var tex := ImageTexture.create_from_image(Image.load_from_file(path))
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	# Radial vignette: darker at the edges, lighter behind the title.
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.04, darken * 0.75))
	g.set_color(1, Color(0.02, 0.025, 0.04, minf(darken + 0.3, 0.95)))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.15, 1.1)
	gt.width = 256
	gt.height = 256
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)


func _bar(parent: Control, top: bool) -> void:
	var r := ColorRect.new()
	r.color = ACCENT
	r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	if top:
		r.offset_bottom = 6
	else:
		r.offset_top = -6
	parent.add_child(r)


func _banner(bg_path: String) -> Control:
	var root := Control.new()
	_background(bg_path, root, 0.55)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)

	col.add_child(_label("RL PROJECTS  ·  RELEASE NOTES", semi, 26, ACCENT, 5))

	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 28)
	title.add_child(_label("OPENSHOOTER", bold_c, 168, TEXT, 2))
	title.add_child(_label(version, bold_c, 168, ACCENT, 2))
	col.add_child(title)

	var line_holder := CenterContainer.new()
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(220, 5)
	line_holder.add_child(line)
	col.add_child(line_holder)

	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	col.add_child(gap)
	col.add_child(_label("Free and open-source LAN shooter", medium, 36, TEXT))
	col.add_child(_label("WINDOWS   ·   LINUX   ·   MACOS   ·   ANDROID", semi, 22, MUTED, 4))
	_bar(root, false)
	return root


func _thumb(bg_path: String) -> Control:
	var root := Control.new()
	_background(bg_path, root, 0.45)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 18)
	root.add_child(col)

	# Play button: accent circle with a dark triangle.
	var holder := CenterContainer.new()
	var circle := Panel.new()
	circle.custom_minimum_size = Vector2(140, 140)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(70)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	circle.add_theme_stylebox_override("panel", sb)
	var tri := Polygon2D.new()
	tri.color = Color("#14171c")
	tri.polygon = PackedVector2Array([Vector2(56, 40), Vector2(56, 100), Vector2(106, 70)])
	circle.add_child(tri)
	holder.add_child(circle)
	col.add_child(holder)

	col.add_child(_label("WATCH THE TRAILER", bold_c, 64, TEXT, 3))
	col.add_child(_label("OPENSHOOTER %s  ·  %s" % [version, duration], semi, 22, ACCENT, 4))
	_bar(root, false)
	return root
