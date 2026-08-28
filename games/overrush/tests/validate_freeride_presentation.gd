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
	_expect(
		environment.fog_aerial_perspective >= 0.35
			and environment.fog_aerial_perspective <= 0.5,
		"Fog should add distant depth without washing the sky into a flat gray backdrop.",
	)
	_expect(
		environment.ambient_light_energy >= 0.7
			and environment.ambient_light_sky_contribution >= 0.88
			and environment.adjustment_contrast <= 1.05,
		"The daylight pass must preserve color and terrain detail outside direct sun without crushing shadow contrast.",
	)
	_expect(
		sky_material != null
			and sky_material.sky_top_color.b > sky_material.sky_top_color.r * 8.0
			and sky_material.sky_horizon_color.get_luminance() >= 0.5
			and sky_material.sky_curve >= 0.6,
		"The high-desert sky needs enough vertical gradient to avoid a flat cyan backdrop while preserving a bright horizon.",
	)
	var horizon_color_difference := (
		absf(sky_material.sky_horizon_color.r - sky_material.ground_horizon_color.r)
		+ absf(sky_material.sky_horizon_color.g - sky_material.ground_horizon_color.g)
		+ absf(sky_material.sky_horizon_color.b - sky_material.ground_horizon_color.b)
	)
	_expect(
		horizon_color_difference <= 0.02
			and is_equal_approx(sky_material.sky_energy_multiplier, sky_material.ground_energy_multiplier)
			and sky_material.ground_bottom_color.b > sky_material.ground_bottom_color.r,
		"Sky and ground horizons must share color and energy so reduced fog does not expose a hard seam.",
	)
	var sun := scene.get_node("Sun") as DirectionalLight3D
	_expect(
		sun.light_energy >= 1.35
			and sun.light_color.g >= 0.85
			and sun.rotation_degrees.x >= -40.0
			and sun.shadow_opacity >= 0.5
			and sun.shadow_opacity <= 0.7
			and sun.shadow_blur >= 2.0,
		"Warm daylight should produce readable terrain form without the former dim orange cast.",
	)
	var world: ProceduralDesert = scene.get_node("Desert")
	_expect(world.chunk_resolution >= 65, "Mountain silhouettes need terrain sampling finer than the former 8 m grid.")
	_expect(world.radial_grade >= 0.42, "The base mountainside needs a sustained grade that reads as freeriding rather than flat traversal.")
	_expect(
		ProceduralDesert.SUMMIT_MOUNTAIN_BLEND_START < ProceduralDesert.SUMMIT_RELIEF_BLEND_START
			and ProceduralDesert.SUMMIT_MOUNTAIN_BLEND_END > ProceduralDesert.SUMMIT_RELIEF_BLEND_END,
		"Broad mountain folds must emerge before local dunes and kickers while blending gradually beyond them.",
	)
	_expect(
		ProceduralDesert.MOUNTAIN_RELIEF_AMPLITUDE >= 100.0
			and ProceduralDesert.MOUNTAIN_FOLD_PRIMARY_AMPLITUDE >= 70.0
			and ProceduralDesert.MOUNTAIN_FOLD_SECONDARY_AMPLITUDE >= 55.0,
		"Mountain-scale relief must remain strong enough to form visible valleys and ridgelines around the opening descent.",
	)
	_expect(
		world._tree_canopy_mesh is ArrayMesh
			and ProceduralDesert.TREE_BOUGH_TIERS >= 6
			and ProceduralDesert.TREE_RADIAL_SEGMENTS >= 10
			and world._tree_canopy_mesh.surface_get_array_len(0) >= 1000
			and world._tree_canopy_mesh.surface_get_array_len(0) <= 1200,
		"Forests should use a full layered conifer silhouette rather than sparse stacked cones.",
	)
	var canopy_arrays := world._tree_canopy_mesh.surface_get_arrays(0)
	var canopy_vertices: PackedVector3Array = canopy_arrays[Mesh.ARRAY_VERTEX]
	var canopy_y_levels := {}
	for canopy_vertex in canopy_vertices:
		canopy_y_levels[roundi(canopy_vertex.y * 1000.0)] = true
	var canopy_bounds := world._tree_canopy_mesh.get_aabb()
	_expect(
		canopy_y_levels.size() >= 24
			and canopy_bounds.position.y <= 0.03
			and canopy_bounds.end.y >= 0.98
			and minf(canopy_bounds.size.x, canopy_bounds.size.z) >= 1.6,
		"Conifer crowns need jagged asymmetric bough edges and a full ground-to-tip silhouette: %d height levels, %s bounds."
		% [canopy_y_levels.size(), str(canopy_bounds)],
	)
	var minimum_canopy_color := Color(INF, INF, INF, 1.0)
	var maximum_canopy_color := Color(-INF, -INF, -INF, 1.0)
	var minimum_canopy_luminance := INF
	var maximum_canopy_luminance := -INF
	for cell_y in range(-8, 9):
		for cell_x in range(-8, 9):
			var canopy_color := world._get_tree_canopy_color(Vector2i(cell_x, cell_y))
			minimum_canopy_color.r = minf(minimum_canopy_color.r, canopy_color.r)
			minimum_canopy_color.g = minf(minimum_canopy_color.g, canopy_color.g)
			minimum_canopy_color.b = minf(minimum_canopy_color.b, canopy_color.b)
			maximum_canopy_color.r = maxf(maximum_canopy_color.r, canopy_color.r)
			maximum_canopy_color.g = maxf(maximum_canopy_color.g, canopy_color.g)
			maximum_canopy_color.b = maxf(maximum_canopy_color.b, canopy_color.b)
			minimum_canopy_luminance = minf(minimum_canopy_luminance, canopy_color.get_luminance())
			maximum_canopy_luminance = maxf(maximum_canopy_luminance, canopy_color.get_luminance())
	_expect(
		maximum_canopy_color.r - minimum_canopy_color.r >= 0.35
			and maximum_canopy_color.b - minimum_canopy_color.b >= 0.35
			and maximum_canopy_luminance - minimum_canopy_luminance >= 0.25
			and ProceduralDesert.TREE_CANOPY_EMISSION_ENERGY <= 0.4,
		"Batched forests need deterministic cool/warm and value variation while direct light remains the primary form cue.",
	)
	var stable_canopy_color := world._get_tree_canopy_color(Vector2i(7, -3))
	var repeated_canopy_color := world._get_tree_canopy_color(Vector2i(7, -3))
	_expect(
		stable_canopy_color.is_equal_approx(repeated_canopy_color),
		"Tree palette variation must remain deterministic for a seeded landscape.",
	)
	_expect(
		world._rock_mesh is ArrayMesh
			and ProceduralDesert.ROCK_RADIAL_SEGMENTS >= 12
			and world._rock_mesh.surface_get_array_len(0) >= 330
			and world._rock_mesh.surface_get_array_len(0) <= 420,
		"Rock hazards should use rounded weathered boulders with bounded faceting rather than stretched primitive shards.",
	)
	var rock_arrays := world._rock_mesh.surface_get_arrays(0)
	var rock_normals: PackedVector3Array = rock_arrays[Mesh.ARRAY_NORMAL]
	var rounded_rock_normals := {}
	for rock_normal in rock_normals:
		rounded_rock_normals[Vector3i(
			roundi(rock_normal.x * 1000.0),
			roundi(rock_normal.y * 1000.0),
			roundi(rock_normal.z * 1000.0),
		)] = true
	_expect(
		rock_normals.size() == world._rock_mesh.surface_get_array_len(0)
			and rounded_rock_normals.size() >= 50
			and rounded_rock_normals.size() <= 80,
		"Rock lighting should share smooth outward normals across the bounded asymmetric profile: %d unique normals."
		% rounded_rock_normals.size(),
	)
	var stone_texture := load("res://assets/terrain/weathered_sandstone_albedo.png") as Texture2D
	var stone_material := world._create_stone_material(stone_texture, Color.WHITE, 0.92)
	_expect(
		stone_texture != null
			and stone_texture.get_width() >= 1024
			and stone_texture.get_height() >= 1024
			and stone_material.albedo_texture == stone_texture
			and stone_material.uv1_triplanar
			and stone_material.uv1_world_triplanar
			and stone_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
		"Rocks and ruins need a complete high-resolution anisotropic triplanar stone material instead of flat placeholder color.",
	)
	var stone_rebase_shift := Vector3(384.0, 137.0, -384.0)
	world._offset_stone_texture_origin(stone_material, stone_rebase_shift)
	_expect(
		stone_material.uv1_offset.is_equal_approx(stone_rebase_shift * ProceduralDesert.STONE_TRIPLANAR_SCALE),
		"World-triplanar stone offsets must follow floating-origin rebases so landmark surfaces cannot visibly swim.",
	)
	_expect(
		world._ruin_block_mesh is ArrayMesh
			and world._ruin_block_mesh.surface_get_array_len(0) >= 120
			and ProceduralDesert.RUIN_VISUAL_SEGMENTS >= 34,
		"Ruin landmarks should use a complete arch, relief, cap, base, and crest silhouette rather than five scaled boxes.",
	)
	_expect(
		ProceduralDesert.TREE_COLLISION_RADIUS_FACTOR <= 1.0
			and ProceduralDesert.ROCK_COLLISION_RADIUS_FACTOR <= 0.7,
		"Fatal tree and rock colliders should stay inside their visible silhouettes so high-speed near misses remain fair.",
	)

	var rider: Sandboarder = scene.get_node("Sandboarder")
	_expect(rider.fatal_obstacle_impact_speed <= 10.0, "Direct high-speed obstacle collisions must have consequential run-ending stakes.")
	_expect(
		rider.terrain_follow_snap >= 1.4 and rider.terrain_follow_snap <= 1.8,
		"Terrain following should reduce incidental float without suppressing intentional and natural launches.",
	)
	var board := rider.get_node("BoardVisual/Board") as MeshInstance3D
	_expect(board.mesh is ArrayMesh, "The sandboard should use one authored deck mesh rather than a scaled primitive puck.")
	if board.mesh is ArrayMesh:
		var board_bounds := board.mesh.get_aabb()
		_expect(
			board.mesh.surface_get_array_len(0) >= 150
				and board_bounds.size.x >= 1.2
				and board_bounds.size.z >= 2.8
				and board_bounds.size.y >= 0.2,
			"The board needs a wide, long, beveled deck with readable upturned tips: %s."
			% str(board_bounds),
		)
		_expect(
			rider._get_board_vertex(Vector2(0.0, -1.45), true).y
				- rider._get_board_vertex(Vector2(0.0, 0.0), true).y >= 0.13,
			"The sandboard nose and tail should visibly rise above the center deck.",
		)
	for part_name in ["Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		_expect(rider.get_node_or_null("BoardVisual/%s" % part_name) is MeshInstance3D, "The rider silhouette is missing %s." % part_name)
	for detail_path in [
		"BoardVisual/BoardAccent",
		"BoardVisual/LeftRail",
		"BoardVisual/RightRail",
		"BoardVisual/LeftBinding",
		"BoardVisual/RightBinding",
		"BoardVisual/Rider/JacketPanel",
		"BoardVisual/Rider/Shoulders",
		"BoardVisual/Rider/Hood",
		"BoardVisual/Rider/Belt",
		"BoardVisual/Head/Visor",
		"BoardVisual/Head/HelmetStripe",
		"BoardVisual/LeftArm/LeftGlove",
		"BoardVisual/RightArm/RightGlove",
		"BoardVisual/LeftLeg/LeftBoot",
		"BoardVisual/LeftLeg/LeftKnee",
		"BoardVisual/RightLeg/RightBoot",
		"BoardVisual/RightLeg/RightKnee",
	]:
		_expect(rider.get_node_or_null(detail_path) is MeshInstance3D, "The articulated rider is missing visual detail %s." % detail_path)
	var jacket_material := rider.torso_visual.material_override as StandardMaterial3D
	var pants_material := rider.left_leg_visual.material_override as StandardMaterial3D
	var helmet_material := rider.head_visual.material_override as StandardMaterial3D
	var jacket_pants_separation := (
		absf(jacket_material.albedo_color.r - pants_material.albedo_color.r)
		+ absf(jacket_material.albedo_color.g - pants_material.albedo_color.g)
		+ absf(jacket_material.albedo_color.b - pants_material.albedo_color.b)
	)
	var helmet_jacket_separation := (
		absf(helmet_material.albedo_color.r - jacket_material.albedo_color.r)
		+ absf(helmet_material.albedo_color.g - jacket_material.albedo_color.g)
		+ absf(helmet_material.albedo_color.b - jacket_material.albedo_color.b)
	)
	_expect(
		jacket_pants_separation >= 0.28 and helmet_jacket_separation >= 0.2,
		"The rider's jacket, pants, and helmet need distinct mid-tone values that remain legible at gameplay distance.",
	)
	var shoulders := rider.get_node("BoardVisual/Rider/Shoulders") as MeshInstance3D
	var hood := rider.get_node("BoardVisual/Rider/Hood") as MeshInstance3D
	_expect(
		shoulders.mesh is CapsuleMesh and hood.mesh is TorusMesh,
		"The jacket silhouette should use a rounded shoulder yoke and hood rather than additional box primitives.",
	)
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
	_expect(rider.surface_trail.draw_pass_1 is QuadMesh, "Surface spray should use a soft alpha-masked powder sprite rather than primitive pellets.")
	_expect(
		rider.surface_trail.amount >= 800
			and rider.surface_trail.amount <= 1000
			and rider.surface_trail.lifetime >= 0.7
			and rider.surface_trail.lifetime <= 0.9,
		"The high-speed powder wake should remain dense and bounded instead of a sparse dotted line or an unbounded cloud.",
	)
	_expect(
		rider.surface_trail.fixed_fps >= 60 and rider.surface_trail.fract_delta,
		"Maximum-speed spray needs interpolated 60 Hz simulation to avoid spaced particle clumps.",
	)
	var dust_mesh := rider.surface_trail.draw_pass_1 as QuadMesh
	var dust_material := dust_mesh.material as StandardMaterial3D if dust_mesh != null else null
	_expect(
		dust_mesh != null
			and dust_mesh.size.x >= 0.9
			and dust_material != null
			and dust_material.albedo_texture != null
			and dust_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED,
		"Powder particles need a complete transparent billboard asset that can overlap into a soft continuous plume.",
	)
	var surface_process := rider.surface_trail.process_material as ParticleProcessMaterial
	_expect(surface_process != null, "The movement wake needs a surface-aware particle material.")
	if surface_process != null:
		_expect(
			surface_process.color_ramp != null
				and surface_process.initial_velocity_max >= 9.0
				and surface_process.scale_max <= 1.6
				and surface_process.emission_box_extents.z >= 1.25,
			"Surface spray should burst clearly from the board, fade cleanly, and remain size-bounded.",
		)
		var sand_color := Sandboarder.SAND_TRAIL_COLOR
		var grass_color := Sandboarder.GRASS_TRAIL_COLOR
		var palette_difference := (
			absf(sand_color.r - grass_color.r)
			+ absf(sand_color.g - grass_color.g)
			+ absf(sand_color.b - grass_color.b)
		)
		_expect(palette_difference >= 0.35, "Dune and grass wakes need visibly distinct surface feedback.")
		_expect(
			Sandboarder.SAND_TRAIL_SCALE_MAX >= Sandboarder.GRASS_TRAIL_SCALE_MAX * 1.3
				and Sandboarder.GRASS_TRAIL_SCALE_MIN >= 0.4,
			"Grass contact should use a smaller restrained haze instead of sand-sized green cards.",
		)
		rider.velocity = Vector3(rider.maximum_speed, 0.0, 0.0)
		rider._carve_intensity = 1.0
		rider._carve_sign = 1.0
		rider._update_visuals(1.0 / 60.0)
		_expect(
			surface_process.direction.x <= -0.45 and surface_process.direction.y >= 0.4,
			"A committed carve should fan the surface spray outward and upward from the loaded edge.",
		)
	var carve_track := scene.get_node_or_null("CarveTrack") as MeshInstance3D
	_expect(carve_track != null and carve_track.material_override is StandardMaterial3D, "The rider should leave one terrain-conforming carve-track mesh.")
	_expect(
		rider.carve_track_max_points <= 240
			and rider.carve_track_sample_distance >= 1.25
			and rider.carve_track_surface_offset >= 0.025,
		"Carve-track feedback must remain bounded, sampled efficiently, and lifted above terrain seams.",
	)

	var camera = scene.get_node("FollowCamera")
	_expect(
		camera.follow_distance <= 8.5
			and rad_to_deg(atan2(camera.follow_height, camera.follow_distance)) >= 30.0
			and camera.look_ahead >= 10.0,
		"Third-person framing should keep the rider readable while looking down into the mountain line.",
	)
	_expect(
		camera.get_follow_response_rate(camera.speed_fov_full) >= camera.position_smoothing * 2.5,
		"High-speed follow should close camera lag before the rider shrinks into the horizon.",
	)
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
	var downhill_focus_count := 0
	for direction_index in range(8):
		var heading := TAU * float(direction_index) / 8.0
		var steep_test_position := Vector2(cos(heading), sin(heading)) * 900.0
		rider.global_position = world.world_to_local_position(Vector3(
			steep_test_position.x,
			world.get_surface_height(steep_test_position.x, steep_test_position.y) + 0.45,
			steep_test_position.y,
		))
		camera.set_orbit_angles(-heading - PI * 0.5, atan2(camera.follow_height, camera.follow_distance))
		var camera_forward: Vector3 = camera.get_planar_forward()
		var level_focus_height: float = rider.global_position.y + camera.focus_height
		var terrain_focus: Vector3 = camera._get_focus(camera_forward)
		if terrain_focus.y <= level_focus_height - 0.5:
			downhill_focus_count += 1
		camera.snap_to_target()
		_expect(
			camera.get_current_minimum_terrain_clearance() >= camera.terrain_clearance - 0.03,
			"The chase-camera sightline clips mountain terrain in outward heading %d." % direction_index,
		)
	_expect(
		downhill_focus_count >= 6,
		"The chase camera should look into most descending surfaces instead of flattening them against the horizon: %d/8."
		% downhill_focus_count,
	)

	var shader: Shader = load("res://shaders/desert.gdshader")
	_expect(
		"key_light_direction" in shader.code
			and "wind_crest" in shader.code
			and "grass_weight" in shader.code
			and "surface_texture_scale = 0.08" in shader.code,
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
