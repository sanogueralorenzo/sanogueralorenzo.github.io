extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_experience_progression()
	_test_first_choice_establishes_distinct_builds()
	_test_speed_scaling_rewards_fast_movement()
	_test_repeatable_upgrade_limits()
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
	_expect(build.dash_nova_level == 1 and build.slipstream_level == 0, "Dash Nova should unlock dash burst combat without also unlocking Slipstream.")


func _test_speed_scaling_rewards_fast_movement() -> void:
	var build := RunBuildScript.new()
	build.apply_upgrade(&"velocity_coil")
	_expect(build.get_arc_damage(126.0) > build.get_arc_damage(58.0), "Velocity Coil should deal materially more damage at dash speed.")


func _test_repeatable_upgrade_limits() -> void:
	var build := RunBuildScript.new()
	for index in range(12):
		build.apply_upgrade(&"arc_capacitor")
		build.apply_upgrade(&"forked_current")
	_expect(build.fire_interval >= 0.18, "Arc Capacitor should respect its fire-rate floor.")
	_expect(build.projectile_count == 5, "Forked Current should respect its projectile cap.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
