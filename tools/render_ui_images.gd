extends SceneTree
## Renders the pictures the interface uses, from the game itself:
##
##   assets/ui/maps/<map id>.png       480 x 270 view of each map (MapDB)
##   assets/ui/weapons/<weapon>.png    side view of each weapon as a WHITE
##                                     silhouette (tint it with `modulate`)
##
## Run again after adding or changing a map or a weapon:
##   godot --path . -s res://tools/render_ui_images.gd
## (needs a window: the pictures are rendered, so not --headless).

const MAP_DIR := "res://assets/ui/maps"
const WEAPON_DIR := "res://assets/ui/weapons"
const MAP_SIZE := Vector2i(480, 270)
const WEAPON_SIZE := Vector2i(256, 128)
## Where the map camera stands and looks (same view for every map).
const MAP_CAMERA := Vector3(-6, 7, 34)
const MAP_TARGET := Vector3(4, 2, 0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WEAPON_DIR))
	for i in MapDB.count():
		await _render_map(MapDB.info(i))
	for i in WeaponDB.count():
		await _render_weapon(WeaponDB.get_data(i))
	print("UI images written to %s and %s" % [MAP_DIR, WEAPON_DIR])
	quit()


## A viewport that renders every frame into its own 3D world.
func _viewport(size: Vector2i, transparent: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = transparent
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _save(viewport: SubViewport, frames: int, path: String) -> void:
	for f in frames:
		await process_frame
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	viewport.queue_free()
	await process_frame


func _render_map(info: Dictionary) -> void:
	var viewport := _viewport(MAP_SIZE, false)
	var map: Node3D = load(info.scene).instantiate()
	viewport.add_child(map)
	var camera := Camera3D.new()
	camera.far = 200.0
	viewport.add_child(camera)
	camera.position = MAP_CAMERA
	camera.look_at(MAP_TARGET)
	camera.current = true
	await _save(viewport, 40, "%s/%s.png" % [MAP_DIR, info.id])


func _render_weapon(data: WeaponData) -> void:
	var viewport := _viewport(WEAPON_SIZE, true)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	viewport.add_child(environment)
	var model: Node3D = data.model.instantiate()
	viewport.add_child(model)
	await process_frame
	# Frame the weapon from its right side, filling the picture.
	var box := _bounds(model, Transform3D.IDENTITY)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Orthographic size = view height; the picture is twice as wide.
	camera.size = maxf(box.size.y * 1.25, box.size.z * 0.56)
	viewport.add_child(camera)
	camera.position = box.get_center() + Vector3(3.0, 0, 0)
	camera.look_at(box.get_center())
	camera.current = true
	for f in 10:
		await process_frame
	# Keep only the shape: every visible pixel becomes white.
	var image := viewport.get_texture().get_image()
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	var name := data.resource_path.get_file().get_basename()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [WEAPON_DIR, name]))
	viewport.queue_free()
	await process_frame


## Combined bounds of every mesh under `node`.
func _bounds(node: Node, xf: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	for child in node.get_children():
		var child_xf := xf
		if child is Node3D:
			child_xf = xf * (child as Node3D).transform
		var boxes: Array[AABB] = []
		if child is VisualInstance3D:
			boxes.append(child_xf * (child as VisualInstance3D).get_aabb())
		if child.get_child_count() > 0:
			var inner := _bounds(child, child_xf)
			if inner.size != Vector3.ZERO:
				boxes.append(inner)
		for b in boxes:
			result = b if not found else result.merge(b)
			found = true
	return result
