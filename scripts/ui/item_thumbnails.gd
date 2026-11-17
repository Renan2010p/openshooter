class_name ItemThumbnails
extends Node
## 3D thumbnails of Locker items.
##
## Each thumbnail is rendered ONCE in a small SubViewport: a character wearing
## the player's current look with that one item swapped in, framed on the
## part of the body the item is on. The picture is copied into an
## ImageTexture and the viewport is freed right away, so open thumbnails cost
## nothing while the Locker is shown. Pictures are cached until the player's
## colors change.

const AVATAR_SCENE := preload("res://scenes/player/avatar.tscn")
## Thumbnail size in pixels.
const SIZE := Vector2i(160, 160)

## Camera per slot: [point the camera looks at, camera position, avatar turn].
## The avatar faces the camera at turn PI (characters look down -Z).
const FRAMING := {
	"hat": [Vector3(0, 2.06, 0), Vector3(0.0, 2.2, 1.55), PI - 0.45],
	"hair": [Vector3(0, 1.95, 0), Vector3(0.0, 2.05, 1.3), PI - 0.75],
	"face": [Vector3(0, 1.9, 0), Vector3(0.0, 1.95, 1.05), PI - 0.3],
	"top": [Vector3(0, 1.3, 0), Vector3(0.0, 1.45, 2.1), PI - 0.3],
	"legs": [Vector3(0, 0.6, 0), Vector3(0.0, 0.8, 1.9), PI - 0.3],
	"feet": [Vector3(0, 0.15, 0), Vector3(0.0, 0.55, 1.3), PI - 0.5],
	"back": [Vector3(0, 1.25, 0), Vector3(0.0, 1.45, 2.3), 0.5],
}

## "slot/id/colors" -> ImageTexture
var _cache := {}


## Calls `done.call(texture)` with the thumbnail of item `id` in `slot`, as
## soon as it is rendered (right away if cached).
func request(slot: String, id: String, done: Callable) -> void:
	var key := _key(slot, id)
	if _cache.has(key):
		done.call(_cache[key])
		return
	_render(slot, id, key, done)


## Forget every picture (call when the player's colors change).
func clear() -> void:
	_cache.clear()


func _key(slot: String, id: String) -> String:
	return "%s/%s/%s%s%s%s" % [slot, id, Config.shirt.to_html(), Config.pants.to_html(),
		Config.skin.to_html(), Config.hair.to_html()]


func _render(slot: String, id: String, key: String, done: Callable) -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	# Soft, even light so every item reads clearly.
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.55
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.1
	viewport.add_child(sun)

	# The character: current look, with this item.
	var avatar: Avatar = AVATAR_SCENE.instantiate()
	viewport.add_child(avatar)
	var look := Config.look.duplicate()
	look[slot] = id
	avatar.setup(Config.shirt, Config.pants, Config.skin, look, Config.hair)
	avatar.idle_preview(0.0)

	var framing: Array = FRAMING.get(slot, FRAMING["top"])
	avatar.rotation.y = framing[2]
	var camera := Camera3D.new()
	camera.fov = 40.0
	viewport.add_child(camera)
	camera.position = framing[1]
	camera.look_at(framing[0])
	camera.current = true

	# Wait until the frame is drawn, then keep a copy of the picture.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(viewport):
		return
	var texture := ImageTexture.create_from_image(viewport.get_texture().get_image())
	viewport.queue_free()
	_cache[key] = texture
	done.call(texture)
