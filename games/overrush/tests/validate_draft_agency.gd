extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 167705
	root.add_child(scene)
	await process_frame
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")

	director._on_experience_collected(12)
	await process_frame
	_expect(paused and scene.level_up_overlay.visible, "The initial engine draft should pause the live run.")
	_expect(scene.reroll_button.disabled and scene.banish_button.disabled, "Keystone commitment should not be rerollable or banishable.")
	scene._choose_upgrade(0)
	await process_frame
	_expect(not paused and director.build.core_path == RunBuild.DASHBREAKER, "Choosing the keystone should resume play with a committed engine.")

	director.build.pending_levels = 1
	director._offer_level_up()
	await process_frame
	var first_options: Array[StringName] = scene._current_upgrade_options.duplicate()
	_expect(not scene.reroll_button.disabled and "3" in scene.reroll_button.text, "A committed four-option pool should expose all three rerolls.")
	scene._reroll_upgrade_options()
	await process_frame
	var rerolled_options: Array[StringName] = scene._current_upgrade_options.duplicate()
	var introduced_alternative := false
	for upgrade_id in rerolled_options:
		if upgrade_id not in first_options:
			introduced_alternative = true
	_expect(introduced_alternative and director.rerolls_remaining == 2, "Rerolling should spend one charge only when the offer changes.")
	_expect(director.run_stats.rerolls_used == 1 and "2" in scene.reroll_button.text, "Draft resource use should update both telemetry and visible state.")

	var banish_index := -1
	for index in range(rerolled_options.size()):
		if director.build.can_banish_upgrade(rerolled_options[index]):
			banish_index = index
			break
	_expect(banish_index >= 0 and not scene.banish_button.disabled, "A removable standard option should enable the one-use banish control.")
	scene._toggle_banish_mode()
	_expect(scene._banish_mode and "BANISH ACTIVE" in scene.level_up_prompt.text, "Banish mode should explicitly ask for the upgrade to remove.")
	var banished_id := rerolled_options[banish_index]
	scene._choose_upgrade(banish_index)
	await process_frame
	_expect(director.banishes_remaining == 0 and director.run_stats.banishes_used == 1, "Banishing should spend the single run resource and record its use.")
	_expect(director.build.is_upgrade_banished(banished_id) and banished_id not in scene._current_upgrade_options, "A banished upgrade should disappear from the refreshed offer and future pool.")
	_expect(scene.level_up_overlay.visible and scene.banish_button.disabled, "Banishing should refresh the draft without consuming the pending level.")

	var reduced_options: Array[StringName] = [&"dash_nova", &"dash_echo"]
	scene._render_upgrade_options(reduced_options)
	_expect(scene.level_up_buttons[0].visible and scene.level_up_buttons[1].visible and not scene.level_up_buttons[2].visible, "A depleted late-run pool should render safely without indexing a missing third option.")

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Draft agency validation passed — protected keystones, meaningful rerolls, banishment, telemetry, and reduced pools agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
