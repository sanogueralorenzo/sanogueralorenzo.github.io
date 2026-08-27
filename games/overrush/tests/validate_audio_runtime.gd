extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.get_node("World").seed = 88515
	root.add_child(scene)
	await process_frame

	var audio: OverrushAudioDirector = scene.get_node("AudioDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var director: CombatDirector = scene.get_node("CombatDirector")
	_expect(audio._effect_players.size() == audio.EFFECT_POOL_SIZE, "Runtime audio should pool enough players for overlapping combat cues.")
	_expect(runner.dash_state_changed.is_connected(audio.play_dash), "Dash state should drive velocity audio feedback.")
	_expect(runner.damaged.is_connected(scene._on_runner_damaged), "Integrity damage should drive the combined audio and visual feedback path.")
	_expect(director.enemy_defeated_feedback.is_connected(audio.play_enemy_defeat), "Enemy defeats should reach the audio director.")
	_expect(director.enemy_hit_feedback.is_connected(audio.play_enemy_hit), "Weapon impacts should reach the rate-limited hit cue system.")
	_expect(director.experience_collected_feedback.is_connected(audio.play_pickup), "Core pickups should reach the audio director.")
	_expect(director.integrity_collected_feedback.is_connected(audio.play_repair), "Integrity cores should reach their distinct recovery cue.")
	_expect(director.attack_warning_feedback.is_connected(audio.play_attack_warning), "Enemy telegraphs should reach the warning cue system.")

	var master_slider: HSlider = scene.get_node("HUD/SettingsOverlay/SettingsPanel/Content/MasterAudio/Slider")
	var music_slider: HSlider = scene.get_node("HUD/SettingsOverlay/SettingsPanel/Content/MusicAudio/Slider")
	var effects_slider: HSlider = scene.get_node("HUD/SettingsOverlay/SettingsPanel/Content/EffectsAudio/Slider")
	master_slider.value = 35.0
	music_slider.value = 20.0
	effects_slider.value = 40.0
	_expect(is_equal_approx(scene._profile.master_volume, 0.35) and is_equal_approx(audio.master_level, 0.35), "Master audio changes should apply immediately and update the profile.")
	_expect(is_equal_approx(scene._profile.music_volume, 0.2) and is_equal_approx(audio.music_level, 0.2), "Music changes should apply immediately and update the profile.")
	_expect(is_equal_approx(scene._profile.effects_volume, 0.4) and is_equal_approx(audio.effects_level, 0.4), "Effects changes should apply immediately and update the profile.")
	_expect(is_equal_approx(audio._effect_players[0].volume_db, linear_to_db(0.35 * 0.4)), "Independent effects volume should retune already-pooled players instead of only future sounds.")

	scene.begin_run()
	await process_frame
	var enemy: EnemyAgent = director._spawn_enemy(&"bulwark")
	enemy._begin_special(runner.global_position - enemy.global_position)
	_expect(audio._warning_cooldown > 0.0, "A telegraphed enemy attack should trigger the rate-limited warning cue path.")
	var defeat_sequence_before := audio._defeat_sequence
	enemy.take_damage(enemy.health + 1.0)
	await process_frame
	_expect(audio._defeat_sequence > defeat_sequence_before, "Defeating a threat should select a varied defeat cue pitch.")
	var pickup_sequence_before := audio._pickup_sequence
	director._on_experience_collected(3)
	_expect(audio._pickup_sequence > pickup_sequence_before, "Collecting a core should select a varied pickup cue pitch.")
	var repair_sequence_before := audio._repair_sequence
	runner.take_damage(20.0, runner.global_position + Vector3.RIGHT, &"pursuer_contact")
	director._on_integrity_collected(12.0)
	_expect(audio._repair_sequence > repair_sequence_before, "Collecting an integrity core should select a distinct varied recovery cue.")

	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Audio runtime validation passed — gameplay cues, pooling, rate limiting, and independent persistent mix controls are connected.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
