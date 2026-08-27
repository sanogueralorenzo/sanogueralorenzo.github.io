extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_experience_progression()
	_test_first_choice_establishes_distinct_builds()
	_test_paths_remain_mechanically_isolated()
	_test_repeatable_upgrade_limits()
	_test_exclusive_evolution_forks()
	if _failures.is_empty():
		print("Run build validation passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_experience_progression() -> void:
	var build := RunBuildScript.new()
	var gained: int = build.add_experience(40)
	_expect(gained >= 2, "A large XP award should preserve overflow and grant multiple levels.")
	_expect(build.pending_levels == gained, "Every gained level should require one build decision.")
	_expect(build.experience < build.experience_to_next, "XP overflow should remain within the current level.")


func _test_first_choice_establishes_distinct_builds() -> void:
	var build := RunBuildScript.new()
	build.add_experience(12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var options: Array[StringName] = build.get_upgrade_options(rng)
	_expect(options == [&"dash_nova", &"slipstream", &"velocity_coil"], "The first choice should present three movement-centric build directions.")
	build.apply_upgrade(&"dash_nova")
	_expect(build.core_path == RunBuild.DASHBREAKER, "Dashbreaker should commit the run to its own path.")
	var follow_up_options := build.get_upgrade_options(rng)
	for option in follow_up_options:
		_expect(option in RunBuild.PATH_UPGRADES[RunBuild.DASHBREAKER], "Dashbreaker should not receive upgrades from another engine.")


func _test_paths_remain_mechanically_isolated() -> void:
	var dash_build := RunBuildScript.new()
	dash_build.apply_upgrade(&"dash_nova")
	dash_build.apply_upgrade(&"dash_echo")
	dash_build.apply_upgrade(&"phase_shell")
	var trail_build := RunBuildScript.new()
	trail_build.apply_upgrade(&"slipstream")
	trail_build.apply_upgrade(&"wake_duration")
	trail_build.apply_upgrade(&"wake_width")
	var arc_build := RunBuildScript.new()
	arc_build.apply_upgrade(&"velocity_coil")
	arc_build.apply_upgrade(&"arc_chain")

	_expect(dash_build.dash_echo_level == 1 and dash_build.phase_shell_level == 1, "Dashbreaker should gain dash endpoint and immunity mechanics.")
	_expect(trail_build.get_wake_duration() > 2.0 and trail_build.get_wake_radius() > 11.0, "Stormtrail should gain persistent route-control geometry.")
	_expect(arc_build.arc_chain_count == 1 and arc_build.get_arc_damage(126.0) > arc_build.get_arc_damage(58.0), "Arcstorm should gain speed-scaled chaining projectiles.")
	_expect(not dash_build.is_arc_weapon_enabled() and not trail_build.is_arc_weapon_enabled() and arc_build.is_arc_weapon_enabled(), "Only Arcstorm should retain the universal auto-arc after commitment.")
	_expect(dash_build.apply_upgrade(&"arc_chain").is_empty(), "Committed builds should reject off-path upgrades.")


func _test_repeatable_upgrade_limits() -> void:
	var build := RunBuildScript.new()
	build.apply_upgrade(&"velocity_coil")
	for index in range(12):
		build.apply_upgrade(&"arc_capacitor")
		build.apply_upgrade(&"forked_current")
	_expect(build.fire_interval >= 0.18, "Arc Capacitor should respect its fire-rate floor.")
	_expect(build.projectile_count == 5, "Forked Current should respect its projectile cap.")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	_expect(build.get_upgrade_options(rng).size() == 3, "A mature path should still offer three valid choices after capped upgrades leave the pool.")


func _test_exclusive_evolution_forks() -> void:
	var path_cases := [
		[&"dash_nova", &"ramjet", &"gravity_knot", &"ramjet_mass", &"event_horizon"],
		[&"slipstream", &"twin_current", &"tempest_anchor", &"parallel_flow", &"storm_charge"],
		[&"velocity_coil", &"storm_lance", &"arc_orbit", &"lance_focus", &"orbit_flux"],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7721
	for path_case in path_cases:
		var build := RunBuildScript.new()
		for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
			build.apply_upgrade(StringName(path_case[0]))
		var options := build.get_upgrade_options(rng)
		_expect(StringName(path_case[1]) in options and StringName(path_case[2]) in options, "A mature engine should explicitly offer both exclusive evolution geometries.")
		_expect(not build.apply_upgrade(StringName(path_case[1])).is_empty(), "A qualified evolution should be selectable.")
		_expect(build.apply_upgrade(StringName(path_case[2])).is_empty(), "Choosing one evolution should permanently reject its sibling for the run.")
		_expect(not build.apply_upgrade(StringName(path_case[3])).is_empty(), "The chosen evolution should unlock its dedicated support upgrade.")
		_expect(build.apply_upgrade(StringName(path_case[4])).is_empty(), "Support from the rejected evolution should remain unavailable.")
		_expect(str(build.get_upgrade_name(StringName(path_case[1]))) in build.get_build_name(), "The HUD build name should expose the chosen evolution.")

	var envelope_build := RunBuildScript.new()
	for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
		envelope_build.apply_upgrade(&"velocity_coil")
	envelope_build.apply_upgrade(&"storm_lance")
	for _rank in range(3):
		envelope_build.apply_upgrade(&"lance_focus")
	_expect(envelope_build.get_lance_range() <= 145.0 and envelope_build.get_lance_target_limit() <= 11, "Storm Lance support should stay inside its authored range and target envelope.")
	_expect(envelope_build.apply_upgrade(&"lance_focus").is_empty(), "Evolution support should cap after three meaningful ranks.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
