extends SceneTree

const AtmosphereModel = preload("res://scripts/world_atmosphere.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 41001
	root.add_child(scene)
	await process_frame
	await process_frame
	var world: Node3D = scene.get_node("World")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var atmosphere = scene.get_node("WorldAtmosphere")
	var environment: Environment = scene.get_node("WorldEnvironment").environment
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	var sun: DirectionalLight3D = scene.get_node("Sun")
	var banner: Label = scene.get_node("HUD/EventBanner")
	var reveals: Array[String] = []
	atmosphere.region_revealed.connect(func(region_name: String, _subtitle: String) -> void: reveals.append(region_name))

	_expect(atmosphere.process_mode == Node.PROCESS_MODE_ALWAYS and paused, "Atmosphere transitions should remain initialized while launch or draft UI pauses gameplay.")
	_expect(atmosphere.get_current_region() == "VERDANT REACH" and reveals.is_empty(), "The opening region should initialize without an unnecessary discovery banner.")
	var verdant_state := AtmosphereModel.sample_palette(Vector3(1.0, 0.0, 0.0))
	_expect(sky_material.sky_horizon_color.is_equal_approx(Color(verdant_state.sky_horizon)), "The opening sky should agree with the terrain's Verdant region.")

	var ember_z: float = -world.grammar.route_length * 0.5
	runner.global_position.z = ember_z
	var weights_before: Vector3 = atmosphere.current_weights
	atmosphere._update_accumulator = 0.0
	atmosphere._process(AtmosphereModel.UPDATE_INTERVAL * 0.5)
	_expect(atmosphere.current_weights.is_equal_approx(weights_before), "Sky resources should not regenerate every rendered frame.")
	atmosphere._process(AtmosphereModel.UPDATE_INTERVAL * 0.5)
	var ember_target: Vector3 = world.grammar.get_region_weights(ember_z)
	_expect(atmosphere.current_weights.y > weights_before.y and atmosphere.current_weights.y < ember_target.y, "A large position change should begin a gradual atmosphere transition instead of flashing to the new palette.")

	atmosphere.snap_to_runner()
	atmosphere._process(AtmosphereModel.UPDATE_INTERVAL)
	var ember_state := AtmosphereModel.sample_palette(ember_target)
	_expect(sky_material.sky_horizon_color.is_equal_approx(Color(ember_state.sky_horizon)), "Ember sky color should follow the same deterministic region weights as terrain.")
	_expect(environment.fog_light_color.is_equal_approx(Color(ember_state.fog_color)) and sun.light_color.is_equal_approx(Color(ember_state.sun_color)), "Fog, ambient world depth, and sunlight should transition as one coherent palette.")
	_expect(reveals == ["EMBER BASIN"] and banner.visible and "EMBER BASIN" in banner.text, "Entering a new region should reveal its identity once through the existing readable event banner.")

	runner.global_position.z = 0.0
	atmosphere.snap_to_runner()
	atmosphere._process(AtmosphereModel.UPDATE_INTERVAL)
	runner.global_position.z = ember_z
	atmosphere.snap_to_runner()
	atmosphere._process(AtmosphereModel.UPDATE_INTERVAL)
	_expect(reveals.size() == 1, "Backtracking should never spam a previously discovered region banner.")

	if is_instance_valid(scene._event_tween):
		scene._event_tween.kill()
	banner.visible = true
	banner.text = "HORIZON ELITE • BULWARK\nWide geometry • longer warning"
	var prism_z: float = -world.grammar.route_length * 0.88
	runner.global_position.z = prism_z
	atmosphere.snap_to_runner()
	atmosphere._process(AtmosphereModel.UPDATE_INTERVAL)
	var prism_state := AtmosphereModel.sample_palette(world.grammar.get_region_weights(prism_z))
	_expect(reveals == ["EMBER BASIN", "PRISM HIGHLANDS"], "Every later region should receive exactly one reveal per run.")
	_expect("HORIZON ELITE" in banner.text and scene._pending_region_reveal.size() == 2, "A region reveal should queue behind a higher-priority combat banner instead of erasing it.")
	scene._finish_event_banner()
	await process_frame
	_expect(banner.visible and "PRISM HIGHLANDS" in banner.text, "A queued region reveal should play immediately after the active combat message.")
	_expect(sky_material.sky_top_color.is_equal_approx(Color(prism_state.sky_top)) and is_equal_approx(environment.fog_density, float(prism_state.fog_density)), "Prism Highlands should apply its cold sky and bounded fog depth together.")
	_expect(environment.fog_density <= 0.0011, "Even the deepest region fog should preserve long high-speed sightlines.")

	runner.global_position.z = 0.0
	atmosphere.snap_to_runner()
	atmosphere._update_accumulator = 0.0
	var updates_before: int = atmosphere.applied_update_count
	var benchmark_started := Time.get_ticks_usec()
	for frame in range(600):
		runner.global_position.z = lerpf(0.0, prism_z, float(frame) / 599.0)
		atmosphere._process(1.0 / 60.0)
	var benchmark_milliseconds := (Time.get_ticks_usec() - benchmark_started) / 1000.0
	var applied_updates: int = atmosphere.applied_update_count - updates_before
	print("Atmosphere benchmark — %d applied updates in %.2f ms for 600 frame samples." % [applied_updates, benchmark_milliseconds])
	_expect(applied_updates >= 40 and applied_updates <= 65, "Ten seconds of traversal should update expensive sky resources at a bounded four-to-seven times per second.")
	_expect(benchmark_milliseconds < 80.0, "Atmosphere interpolation should remain negligible beside terrain and combat work (%.2f ms for 600 samples)." % benchmark_milliseconds)

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("World atmosphere runtime validation passed — gradual palettes, %d bounded updates in %.2f ms, region reveals, and sightline-safe fog are connected." % [applied_updates, benchmark_milliseconds])
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
