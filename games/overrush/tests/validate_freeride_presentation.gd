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
	_expect(environment.ambient_light_energy >= 0.45, "Forest and rock silhouettes need readable ambient fill.")
	_expect(
		sky_material.sky_top_color.b > sky_material.sky_top_color.r * 5.0
			and sky_material.sky_horizon_color.r > sky_material.sky_top_color.r * 10.0,
		"The cool upper sky and warm atmospheric horizon should create strong landscape depth.",
	)
	var world: ProceduralDesert = scene.get_node("Desert")
	_expect(world.chunk_resolution >= 65, "Mountain silhouettes need terrain sampling finer than the former 8 m grid.")
	_expect(
		world._tree_canopy_mesh is SphereMesh and ProceduralDesert.TREE_CROWN_LAYERS == 3,
		"Forests should use three layered organic crowns rather than single primitive cones.",
	)

	var rider: Sandboarder = scene.get_node("Sandboarder")
	_expect(rider.fatal_obstacle_impact_speed <= 10.0, "Direct high-speed obstacle collisions must have consequential run-ending stakes.")
	var board := rider.get_node("BoardVisual/Board") as MeshInstance3D
	_expect(board.mesh is CylinderMesh, "The sandboard should use a rounded silhouette rather than a placeholder box.")
	for part_name in ["Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		_expect(rider.get_node_or_null("BoardVisual/%s" % part_name) is MeshInstance3D, "The rider silhouette is missing %s." % part_name)
	_expect(rider.surface_trail.draw_pass_1 is SphereMesh, "Surface spray should use rounded grains rather than flashing quad pixels.")
	_expect(rider.surface_trail.amount >= 200, "The high-speed wake should remain continuous instead of a sparse dotted line.")
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

	var camera: Camera3D = scene.get_node("FollowCamera")
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
