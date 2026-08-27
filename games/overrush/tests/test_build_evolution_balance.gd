extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_dashbreaker_envelopes()
	_test_stormtrail_envelopes()
	_test_arcstorm_envelopes()
	_test_catalyst_tradeoff_envelopes()
	if _failures.is_empty():
		print("Build evolution tuning envelopes passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_dashbreaker_envelopes() -> void:
	var ramjet := _evolved_build(&"dash_nova", &"ramjet")
	var ramjet_base := ramjet.get_ramjet_damage(126.0) * ramjet.get_ramjet_radius()
	_apply_support(ramjet, &"ramjet_mass")
	var ramjet_peak := ramjet.get_ramjet_damage(126.0) * ramjet.get_ramjet_radius()
	_expect_ratio(ramjet_peak, ramjet_base, 2.0, 2.7, "Ramjet support")
	_expect_ratio(
		ramjet.get_ramjet_damage(126.0),
		ramjet.get_dash_nova_damage(),
		1.2,
		2.0,
		"Ramjet contact versus charged entry nova"
	)

	var knot := _evolved_build(&"dash_nova", &"gravity_knot")
	var knot_base := knot.get_gravity_knot_damage() * knot.get_gravity_knot_radius() * knot.get_gravity_knot_pull_ratio()
	_apply_support(knot, &"event_horizon")
	var knot_peak := knot.get_gravity_knot_damage() * knot.get_gravity_knot_radius() * knot.get_gravity_knot_pull_ratio()
	_expect_ratio(knot_peak, knot_base, 3.0, 4.5, "Gravity Knot support")
	_expect(knot.get_gravity_knot_pull_ratio() <= 0.72, "Gravity Knot must not collapse every target onto one indistinguishable point.")


func _test_stormtrail_envelopes() -> void:
	var twin := _evolved_build(&"slipstream", &"twin_current")
	var twin_base := twin.get_twin_current_damage_multiplier() * 2.0 * twin.get_twin_current_offset()
	_apply_support(twin, &"parallel_flow")
	var twin_peak := twin.get_twin_current_damage_multiplier() * 2.0 * twin.get_twin_current_offset()
	_expect_ratio(twin_peak, twin_base, 1.5, 2.0, "Twin Current support")
	_expect(twin.get_twin_current_damage_multiplier() < 1.0, "Each Twin Current lane should remain weaker than one centered wake.")

	var anchor := _evolved_build(&"slipstream", &"tempest_anchor")
	var anchor_base := _anchor_pressure_index(anchor)
	_apply_support(anchor, &"storm_charge")
	var anchor_peak := _anchor_pressure_index(anchor)
	_expect_ratio(anchor_peak, anchor_base, 3.5, 5.0, "Tempest Anchor support")
	_expect(anchor.get_anchor_repeat_interval() >= 0.32 and anchor.get_anchor_stride() >= 3, "Tempest Anchor must preserve its periodic identity and bounded pulse rate.")


func _test_arcstorm_envelopes() -> void:
	var lance := _evolved_build(&"velocity_coil", &"storm_lance")
	var lance_base := lance.get_lance_damage(88.0) * lance.get_lance_target_limit() / lance.get_lance_interval()
	_apply_support(lance, &"lance_focus")
	var lance_peak := lance.get_lance_damage(88.0) * lance.get_lance_target_limit() / lance.get_lance_interval()
	_expect_ratio(lance_peak, lance_base, 3.0, 3.2, "Storm Lance support")

	var orbit := _evolved_build(&"velocity_coil", &"arc_orbit")
	var orbit_base := orbit.get_orbit_damage(88.0) * orbit.get_orbit_radius() / orbit.get_orbit_interval()
	_apply_support(orbit, &"orbit_flux")
	var orbit_peak := orbit.get_orbit_damage(88.0) * orbit.get_orbit_radius() / orbit.get_orbit_interval()
	_expect_ratio(orbit_peak, orbit_base, 2.1, 2.5, "Arc Orbit support")
	_expect(lance.get_lance_range() > orbit.get_orbit_radius() * 4.0, "Arcstorm's two evolutions should retain clearly different engagement geometry.")
	_expect(lance.get_lance_damage(88.0) > orbit.get_orbit_damage(88.0) * 2.0, "Storm Lance should trade Arc Orbit's coverage for heavier aimed hits.")


func _test_catalyst_tradeoff_envelopes() -> void:
	var redline := RunBuildScript.new()
	redline.catalyst_id = RunBuild.REDLINE_CORE
	var redline_average := (
		redline.get_catalyst_damage_multiplier(58.0, false, false) * 0.4
		+ redline.get_catalyst_damage_multiplier(88.0, false, false) * 0.4
		+ redline.get_catalyst_damage_multiplier(126.0, false, false) * 0.2
	)
	_expect(redline_average >= 0.95 and redline_average <= 1.08, "Redline Core's representative speed mix should trade timing for output instead of granting universal power.")

	var airframe := RunBuildScript.new()
	airframe.catalyst_id = RunBuild.AIRFRAME_CORE
	var airframe_average := airframe.get_catalyst_damage_multiplier(88.0, true, false) * 0.35 + airframe.get_catalyst_damage_multiplier(88.0, false, false) * 0.65
	_expect(airframe_average >= 0.95 and airframe_average <= 1.08, "Airframe Core should require substantial airtime to outperform an untuned drive.")

	var pulse := RunBuildScript.new()
	pulse.catalyst_id = RunBuild.PULSE_CORE
	var pulse_average := pulse.get_catalyst_damage_multiplier(88.0, false, true) * 0.45 + pulse.get_catalyst_damage_multiplier(88.0, false, false) * 0.55
	_expect(pulse_average >= 0.95 and pulse_average <= 1.08, "Pulse Core should require deliberate dash-window uptime to outperform an untuned drive.")


func _evolved_build(keystone: StringName, evolution: StringName) -> RunBuild:
	var build := RunBuildScript.new()
	for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
		build.apply_upgrade(keystone)
	build.apply_upgrade(evolution)
	return build


func _apply_support(build: RunBuild, support: StringName) -> void:
	for _rank in range(3):
		build.apply_upgrade(support)


func _anchor_pressure_index(build: RunBuild) -> float:
	var pulses_per_anchor := 1.0 + floorf(
		build.get_wake_duration()
		* build.get_anchor_duration_multiplier()
		/ build.get_anchor_repeat_interval()
	)
	return (
		pulses_per_anchor
		* build.get_anchor_damage_multiplier()
		* build.get_anchor_radius_multiplier()
		/ float(build.get_anchor_stride())
	)


func _expect_ratio(peak: float, base: float, minimum: float, maximum: float, label: String) -> void:
	var ratio := peak / maxf(base, 0.001)
	_expect(ratio >= minimum and ratio <= maximum, "%s scaling %.2fx should stay within %.2fx–%.2fx." % [label, ratio, minimum, maximum])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
