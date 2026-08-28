extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = 41777
	root.add_child(scene)
	await process_frame

	var environment: Environment = scene.get_node("WorldEnvironment").environment
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	_expect(environment.ssao_enabled, "The freeride terrain needs contact depth from SSAO in Forward+.")
	_expect(environment.fog_density <= 0.001, "Atmospheric depth must preserve maximum-speed sightlines.")
	_expect(environment.ambient_light_energy >= 0.6, "The daylight pass must keep terrain readable outside direct sun.")
	_expect(
		sky_material.sky_top_color.b > sky_material.sky_top_color.r * 5.0
			and sky_material.sky_horizon_color.r > sky_material.sky_top_color.r * 10.0
			and sky_material.sky_horizon_color.get_luminance() >= 0.65,
		"The saturated upper sky and bright atmospheric horizon should separate mountain silhouettes clearly.",
	)
	var sun := scene.get_node("Sun") as DirectionalLight3D
	_expect(
		sun.light_energy >= 1.4 and sun.light_color.g >= 0.85,
		"Warm daylight should produce readable terrain form without the former dim orange cast.",
	)
	var world: ProceduralDesert = scene.get_node("Desert")
	_expect(world.chunk_resolution >= 65, "Mountain silhouettes need terrain sampling finer than the former 8 m grid.")
	_expect(
		world._tree_canopy_mesh is ArrayMesh
			and ProceduralDesert.TREE_BOUGH_TIERS >= 4
			and world._tree_canopy_mesh.surface_get_array_len(0) >= 180,
		"Forests should use a layered faceted conifer silhouette rather than stacked primitive blobs.",
	)
	_expect(
		world._rock_mesh is ArrayMesh and world._rock_mesh.surface_get_array_len(0) >= 150,
		"Rock hazards should use irregular faceted boulders rather than stretched primitive spheres.",
	)
	_expect(
		world._ruin_block_mesh is ArrayMesh
			and world._ruin_block_mesh.surface_get_array_len(0) >= 120
			and ProceduralDesert.RUIN_VISUAL_SEGMENTS >= 19,
		"Ruin landmarks should use segmented bevel-edged masonry rather than five scaled box primitives.",
	)
	_expect(
		ProceduralDesert.TREE_COLLISION_RADIUS_FACTOR <= 1.0
			and ProceduralDesert.ROCK_COLLISION_RADIUS_FACTOR <= 0.7,
		"Fatal tree and rock colliders should stay inside their visible silhouettes so high-speed near misses remain fair.",
	)

	var rider: Sandboarder = scene.get_node("Sandboarder")
	_expect(rider.fatal_obstacle_impact_speed <= 10.0, "Direct high-speed obstacle collisions must have consequential run-ending stakes.")
	var board := rider.get_node("BoardVisual/Board") as MeshInstance3D
	_expect(board.mesh is CylinderMesh, "The sandboard should use a rounded silhouette rather than a placeholder box.")
	for part_name in ["Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		_expect(rider.get_node_or_null("BoardVisual/%s" % part_name) is MeshInstance3D, "The rider silhouette is missing %s." % part_name)
	for detail_path in [
		"BoardVisual/LeftBinding",
		"BoardVisual/RightBinding",
		"BoardVisual/Rider/JacketPanel",
		"BoardVisual/Head/Visor",
		"BoardVisual/LeftArm/LeftGlove",
		"BoardVisual/RightArm/RightGlove",
		"BoardVisual/LeftLeg/LeftBoot",
		"BoardVisual/RightLeg/RightBoot",
	]:
		_expect(rider.get_node_or_null(detail_path) is MeshInstance3D, "The articulated rider is missing visual detail %s." % detail_path)
	var torso_base_rotation := rider.torso_visual.rotation
	var left_arm_base_rotation := rider.left_arm_visual.rotation
	rider.velocity = Vector3(rider.maximum_speed * 0.82, 0.0, 0.0)
	rider._carve_intensity = 1.0
	rider._carve_sign = 1.0
	rider._update_rider_pose(1.0, true, 0.82)
	_expect(
		absf(rider.torso_visual.rotation.z - torso_base_rotation.z) >= deg_to_rad(12.0),
		"A committed carve should visibly lean the rider into the turn.",
	)
	_expect(
		absf(rider.left_arm_visual.rotation.z - left_arm_base_rotation.z) >= deg_to_rad(9.0),
		"The rider arms should counterbalance a committed carve rather than remain rigid.",
	)
	rider._update_rider_pose(1.0, false, 0.82)
	_expect(rider._air_pose >= 0.95, "Airborne movement should produce a readable tucked rider silhouette.")
	rider.respawn()
	_expect(
		is_equal_approx(rider._air_pose, 0.0)
			and rider.torso_visual.rotation.is_equal_approx(torso_base_rotation),
		"Returning to the summit should reset every procedural rider pose.",
	)
	_expect(rider.surface_trail.draw_pass_1 is SphereMesh, "Surface spray should use rounded grains rather than flashing quad pixels.")
	_expect(rider.surface_trail.amount >= 300, "The high-speed wake should remain continuous instead of a sparse dotted line.")
	_expect(
		(rider.surface_trail.draw_pass_1 as SphereMesh).radius <= 0.08,
		"The denser surface wake should use fine grains rather than oversized glowing balls.",
	)
	var surface_process := rider.surface_trail.process_material as ParticleProcessMaterial
	_expect(surface_process != null, "The movement wake needs a surface-aware particle material.")
	if surface_process != null:
		var sand_color := Sandboarder.SAND_TRAIL_COLOR
		var grass_color := Sandboarder.GRASS_TRAIL_COLOR
		var palette_difference := (
			absf(sand_color.r - grass_color.r)
			+ absf(sand_color.g - grass_color.g)
			+ absf(sand_color.b - grass_color.b)
		)
		_expect(palette_difference >= 0.35, "Dune and grass wakes need visibly distinct surface feedback.")
	var carve_track := scene.get_node_or_null("CarveTrack") as MeshInstance3D
	_expect(carve_track != null and carve_track.material_override is StandardMaterial3D, "The rider should leave one terrain-conforming carve-track mesh.")
	_expect(
		rider.carve_track_max_points <= 240
			and rider.carve_track_sample_distance >= 1.25
			and rider.carve_track_surface_offset >= 0.025,
		"Carve-track feedback must remain bounded, sampled efficiently, and lifted above terrain seams.",
	)

	var camera = scene.get_node("FollowCamera")
	_expect(camera.follow_distance <= 11.0 and camera.follow_height <= 3.5, "Third-person framing should keep the rider readable against the terrain.")
	rider.velocity = Vector3.ZERO
	_expect(is_equal_approx(camera._get_target_fov(), camera.normal_fov), "Resting camera FOV should remain restrained.")
	rider.velocity = Vector3(camera.speed_fov_full, 0.0, 0.0)
	_expect(
		is_equal_approx(camera._get_target_fov(), camera.normal_fov + camera.speed_fov_addition),
		"High speed should widen FOV continuously without waiting for the air boost.",
	)
	camera.set_speed_burst_active(true)
	_expect(is_equal_approx(camera._get_target_fov(), camera.boost_fov), "Air boost should retain the strongest brief speed framing.")
	camera.set_reduced_motion(true)
	_expect(is_equal_approx(camera._get_target_fov(), camera.normal_fov), "Reduced motion should remove all speed-driven FOV displacement.")
	for direction_index in range(8):
		var heading := TAU * float(direction_index) / 8.0
		var steep_test_position := Vector2(cos(heading), sin(heading)) * 900.0
		rider.global_position = world.world_to_local_position(Vector3(
			steep_test_position.x,
			world.get_surface_height(steep_test_position.x, steep_test_position.y) + 0.45,
			steep_test_position.y,
		))
		camera.set_orbit_angles(-heading - PI * 0.5, atan2(camera.follow_height, camera.follow_distance))
		camera.snap_to_target()
		_expect(
			camera.get_current_minimum_terrain_clearance() >= camera.terrain_clearance - 0.03,
			"The chase-camera sightline clips mountain terrain in outward heading %d." % direction_index,
		)

	var shader: Shader = load("res://shaders/desert.gdshader")
	_expect(
		"key_light_direction" in shader.code and "wind_crest" in shader.code and "grass_weight" in shader.code,
		"The terrain shader should expose directional slope depth, readable wind ridges, and seamless biome blending.",
	)
	_expect(
		"sand_albedo" in shader.code
			and "grass_albedo" in shader.code
			and "filter_linear_mipmap_anisotropic" in shader.code
			and "repeat_enable" in shader.code,
		"Fast terrain needs original sand and grass albedo detail with mipmapped anisotropic filtering and continuous repetition.",
	)
	for texture_path in [
		"res://assets/terrain/wind_sand_albedo.png",
		"res://assets/terrain/alpine_grass_albedo.png",
	]:
		var terrain_texture := load(texture_path) as Texture2D
		_expect(terrain_texture != null, "The terrain material asset is missing: %s" % texture_path)
		if terrain_texture != null:
			_expect(
				terrain_texture.get_width() == 1024 and terrain_texture.get_height() == 1024,
				"Terrain albedo assets should remain production-sized 1024 px square textures.",
			)

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Freeride presentation passed — layered forests, mountain sampling, atmospheric depth, rider feedback, and accessible speed FOV agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
