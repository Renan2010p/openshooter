class_name Snowfall
extends GPUParticles3D
## Falling snow around the active camera (Christmas edition).
##
## Only a box of snow above the camera is simulated, and it follows the
## camera every frame, so it always snows where the player looks while the
## cost stays the same on any map size. Flakes already falling stay where they
## are in the world (local_coords is off), so moving does not drag them along.

## Flakes alive at once, per graphics quality (Low, Medium, High).
const AMOUNT := [600, 1200, 2200]
## Half size of the snowing box around the camera (meters).
const EXTENT := Vector3(22.0, 2.0, 22.0)
## Height of the box center above the camera.
const HEIGHT := 9.0
const LIFETIME := 7.0


func _init() -> void:
	name = "Snowfall"
	amount = AMOUNT[clampi(Config.quality, 0, AMOUNT.size() - 1)]
	lifetime = LIFETIME
	# Start already snowing instead of waiting for the first flakes to land.
	preprocess = LIFETIME
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(-EXTENT - Vector3(0, HEIGHT + 4.0, 0), (EXTENT + Vector3(0, HEIGHT + 4.0, 0)) * 2.0)

	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = EXTENT
	motion.direction = Vector3(0.15, -1.0, 0.05)
	motion.spread = 12.0
	motion.initial_velocity_min = 1.0
	motion.initial_velocity_max = 2.0
	motion.gravity = Vector3(0.0, -0.4, 0.0)
	motion.scale_min = 0.6
	motion.scale_max = 1.3
	process_material = motion

	# Each flake: a tiny white square that always faces the camera.
	var flake := QuadMesh.new()
	flake.size = Vector2(0.07, 0.07)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(0.97, 0.98, 1.0)
	flake.material = look
	draw_pass_1 = flake


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		global_position = camera.global_position + Vector3(0.0, HEIGHT, 0.0)
