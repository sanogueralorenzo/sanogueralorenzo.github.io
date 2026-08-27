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
		sky_material.sky_top_color.b > sky_material.sky_top_color.r * 5.0
			and sky_material.sky_horizon_color.b > sky_material.sky_horizon_color.r * 2.0,
		"The cool sky should separate clearly from the warm sand instead of producing a monochrome frame.",
	)

	var rider: Sandboarder = scene.get_node("Sandboarder")
	var board := rider.get_node("BoardVisual/Board") as MeshInstance3D
	_expect(board.mesh is CylinderMesh, "The sandboard should use a rounded silhouette rather than a placeholder box.")
	for part_name in ["Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		_expect(rider.get_node_or_null("BoardVisual/%s" % part_name) is MeshInstance3D, "The rider silhouette is missing %s." % part_name)
	_expect(rider.sand_trail.draw_pass_1 is SphereMesh, "Sand spray should use rounded grains rather than flashing quad pixels.")
	_expect(rider.sand_trail.amount >= 200, "The high-speed wake should remain continuous instead of a sparse dotted line.")

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
	_expect(is_equal_approx(camera._get_target_fov(), camera.dash_fov), "Air boost should retain the strongest brief speed framing.")
	camera.set_reduced_motion(true)
	_expect(is_equal_approx(camera._get_target_fov(), camera.normal_fov), "Reduced motion should remove all speed-driven FOV displacement.")

	var shader: Shader = load("res://shaders/desert.gdshader")
	_expect("key_light_direction" in shader.code and "wind_crest" in shader.code, "The desert shader should expose directional slope depth and readable wind ridges.")

	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Freeride presentation passed — cool/warm depth, rounded rider and spray, close framing, and accessible speed FOV agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
