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
	await physics_frame

	_expect(scene.get_node_or_null("CombatDirector") == null, "The shipped freeride scene must not contain a combat director.")
	_expect(scene.find_child("BuildOverlay", true, false) == null, "The freeride HUD must not contain build progression.")
	_expect(scene.find_child("IntegrityBar", true, false) == null, "The freeride HUD must not contain survivor health UI.")
	var start_text: String = scene.get_node("HUD/StartOverlay/LaunchPanel/Content/Description").text.to_lower()
	_expect("single air boost" in start_text, "The launch screen should explain the defining single air boost.")
	_expect("sand" in start_text, "The launch screen should explain that this is sand freeriding.")

	var rider: Sandboarder = scene.get_node("Sandboarder")
	var paused_position := rider.global_position
	await physics_frame
	await physics_frame
	_expect(rider.global_position.is_equal_approx(paused_position), "The board must stay still behind start and pause overlays.")
	rider.air_boost_state.reset_on_rideable_ground()
	_expect(not rider.try_air_boost(Vector3.FORWARD), "Air boost must reject use while grounded.")
	rider.air_boost_state.leave_surface()
	rider.velocity = Vector3(31.0, 3.0, 0.0)
	_expect(rider.try_air_boost(Vector3.FORWARD), "The first airborne boost should activate.")
	_expect(is_equal_approx(rider.velocity.x, 31.0), "Directional air boost must preserve perpendicular momentum.")
	_expect(rider.velocity.z < -18.0, "Directional air boost should add a meaningful burst in the requested direction.")
	_expect(not rider.try_air_boost(Vector3.RIGHT), "A second boost in the same airtime must be rejected.")
	rider.air_boost_state.land(false)
	rider.air_boost_state.leave_surface()
	_expect(not rider.try_air_boost(Vector3.RIGHT), "Non-sand contact must not refresh the air boost.")
	rider.air_boost_state.land(true)
	rider.air_boost_state.leave_surface()
	_expect(rider.try_air_boost(Vector3.RIGHT), "A valid rideable landing must refresh exactly one boost.")

	scene.begin_run()
	_expect(scene.run_active and not paused, "Drop In should begin an unpaused freeride run.")
	_expect(scene.get_node("HUD/StartOverlay").visible == false, "The launch overlay should leave the view after dropping in.")

	if _failures.is_empty():
		print("Freeride runtime passed — combat-free scene, clear onboarding, and momentum-preserving single air boost agree.")
		scene.queue_free()
		await process_frame
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		scene.queue_free()
		await process_frame
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
