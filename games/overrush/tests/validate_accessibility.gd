extends SceneTree

const RunOnboardingModel = preload("res://scripts/run_onboarding.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_onboarding_model()
	await _validate_runtime_preferences()
	if _failures.is_empty():
		print("Accessibility validation passed — persistent comfort settings and non-blocking guidance affect runtime feedback.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_onboarding_model() -> void:
	var onboarding: RunOnboarding = RunOnboardingModel.new()
	onboarding.reset()
	_expect("STEER" in onboarding.get_message(), "Guidance should begin with the steering concept.")
	_expect("LEFT STICK" in onboarding.get_message(true), "Controller guidance should teach steering with the left stick.")
	onboarding.update(0.1, true, false, false)
	_expect(onboarding.step == RunOnboardingModel.DASH, "Steering input should advance guidance to the dash concept.")
	_expect("LB / RB" in onboarding.get_message(true), "Controller guidance should teach both dash shoulder buttons.")
	onboarding.update(0.1, false, true, false)
	_expect(onboarding.step == RunOnboardingModel.HOP, "A dash should advance guidance to hopping and automatic combat.")
	_expect(" •  A" in onboarding.get_message(true), "Controller guidance should teach hopping with the south face button.")
	onboarding.update(0.1, false, false, true)
	_expect(onboarding.step == RunOnboardingModel.THREATS, "Performing movement concepts should advance into combat literacy instead of ending guidance.")
	_expect("MARKED ZONES" in onboarding.get_message().to_upper(), "Guidance should teach players to leave telegraphed attacks.")
	onboarding.update(RunOnboardingModel.INFORMATION_ADVANCE_SECONDS, false, false, false)
	_expect(onboarding.step == RunOnboardingModel.BUILD and "ENGINE" in onboarding.get_message().to_upper(), "Guidance should explain the engine, evolution, and arsenal build structure.")
	onboarding.update(RunOnboardingModel.INFORMATION_ADVANCE_SECONDS, false, false, false)
	_expect(onboarding.step == RunOnboardingModel.OBJECTIVE and "18:00" in onboarding.get_message(), "Guidance should state when the Apex arrives and how the run is won.")
	onboarding.update(RunOnboardingModel.INFORMATION_ADVANCE_SECONDS, false, false, false)
	_expect(onboarding.is_complete(), "Movement and literacy prompts should complete after their bounded display windows.")

	onboarding.reset()
	for _index in range(RunOnboardingModel.COMPLETE):
		onboarding.update(RunOnboardingModel.AUTOMATIC_ADVANCE_SECONDS, false, false, false)
	_expect(onboarding.is_complete(), "Guidance should retire automatically instead of obstructing players who ignore it.")


func _validate_runtime_preferences() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.get_node("World").seed = 80596
	root.add_child(scene)
	await process_frame

	var camera: Camera3D = scene.get_node("Camera3D")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var director: CombatDirector = scene.get_node("CombatDirector")
	scene._profile.reduced_motion = true
	scene._profile.high_contrast_telegraphs = true
	scene._profile.guidance_enabled = true
	scene._profile.onboarding_completed = false
	scene._apply_accessibility()
	_expect(camera._reduced_motion and is_equal_approx(camera.fov, camera.normal_fov), "Steady dash camera should remove FOV displacement immediately.")
	_expect(runner._reduced_motion, "Reduced motion should reach the runner's dash effects.")
	_expect(director._high_contrast_telegraphs, "High-contrast warnings should reach the combat director.")

	scene.begin_run(RunProtocolCatalog.STANDARD)
	await process_frame
	var tutorial_card: Label = scene.get_node("HUD/TutorialCard")
	_expect(tutorial_card.visible, "An unfinished first run should show contextual guidance without pausing play.")
	_expect(not scene.controls.visible, "First-run guidance should replace the redundant full control legend instead of stacking over the integrity HUD.")
	var guidance_style := tutorial_card.get_theme_stylebox(&"normal") as StyleBoxFlat
	_expect(guidance_style != null and guidance_style.bg_color.a >= 0.8, "Guidance should use a stable high-contrast card instead of floating directly over terrain.")
	_expect(tutorial_card.get_global_rect().end.y <= scene.integrity_label.get_global_rect().position.y - 12.0, "Guidance should remain separated from the persistent integrity readout at 720p.")
	_validate_guidance_card_fit(tutorial_card)
	runner.take_damage(12.0, runner.global_position + Vector3.RIGHT, &"skimmer_charge")
	runner._update_ball_material()
	_expect(scene.damage_direction.visible, "Reduced flashes should retain the directional and numeric damage signal.")
	_expect(scene.damage_vignette.visible and scene.damage_vignette.color.a <= 0.0651, "Reduced flashes should cap the full-screen damage vignette without removing it.")
	_expect(runner._ball_material.emission_energy_multiplier <= 1.81, "Reduced flashes should replace the runner's bright white hit burst with a subdued state change.")
	var enemy: EnemyAgent = director._spawn_enemy(&"bulwark")
	enemy.take_damage(1.0)
	enemy._update_material()
	_expect(enemy._body_material.emission_energy_multiplier <= 1.51, "Reduced flashes should dampen repeated enemy hit emission at high combat density.")
	enemy._special_cooldown = 0.0
	enemy._begin_special(runner.global_position - enemy.global_position)
	_expect(enemy._reduced_motion and enemy._high_contrast_telegraphs, "New threats should inherit active accessibility preferences.")
	_expect(is_equal_approx(enemy._telegraph_material.albedo_color.a, 0.22), "High-contrast warning zones should retain a readable terrain fill.")
	_expect(enemy._telegraph_outline_mesh.visible and enemy._telegraph_outline_material.albedo_color.a > 0.9, "High-contrast warnings should add a bright boundary without hiding the terrain.")
	_expect(is_equal_approx(enemy._telegraph_outline_mesh.scale.x, enemy._get_attack_radius()), "Reduced motion should show the full attack area without radial expansion.")

	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame


func _validate_guidance_card_fit(tutorial_card: Label) -> void:
	var font := tutorial_card.get_theme_font(&"font")
	var font_size := tutorial_card.get_theme_font_size(&"font_size")
	var safe_width := tutorial_card.size.x - 28.0
	var onboarding: RunOnboarding = RunOnboardingModel.new()
	for step_index in range(RunOnboardingModel.COMPLETE):
		onboarding.step = step_index
		for gamepad in [false, true]:
			for line in onboarding.get_message(gamepad).split("\n"):
				var line_width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				_expect(line_width <= safe_width, "Guidance step %d should fit the two-line card for %s input." % [step_index, "gamepad" if gamepad else "keyboard"])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
