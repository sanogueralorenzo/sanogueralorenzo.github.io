extends SceneTree

const RunBuildScript = preload("res://scripts/run_build.gd")
const RunStatsScript = preload("res://scripts/run_stats.gd")

var _failures: Array[String] = []


func _init() -> void:
	var stats: OverrushRunStats = RunStatsScript.new()
	stats.reset(Vector3.ZERO)
	stats.record_traversal(Vector3(3.0, 8.0, 4.0), 58.0)
	stats.record_traversal(Vector3(403.0, 8.0, 404.0), 126.0)
	stats.record_traversal(Vector3(409.0, 8.0, 412.0), 88.0)
	_expect(is_equal_approx(stats.distance_traveled, 15.0), "Run distance should include planar movement while rejecting teleport-sized discontinuities.")
	_expect(is_equal_approx(stats.maximum_speed, 126.0), "Peak speed should preserve the fastest sampled traversal state.")

	stats.record_damage(&"dash_nova", 80.0)
	stats.record_damage(&"arc_bolt", 20.0)
	stats.record_damage(&"dash_nova", 20.0)
	stats.record_damage(&"unknown_source", 5.0)
	stats.record_damage_taken(14.0, &"skimmer_charge")
	stats.record_damage_taken(8.0, &"pursuer_contact")
	stats.record_integrity_recovery(12.0)
	stats.record_integrity_recovery(0.0)
	stats.record_dash()
	stats.record_dash()
	stats.record_velocity_chain(5, 4)
	stats.record_velocity_chain(12, 11)
	stats.record_reroll()
	stats.record_reroll()
	stats.record_banish()
	stats.record_catalyst_state(0.6, true)
	stats.record_catalyst_state(0.4, false)
	stats.record_upgrade(&"dash_nova", 12.4, 2, &"engine")
	stats.record_upgrade(&"ramjet", 183.2, 6, &"evolution")
	stats.record_upgrade(RunBuild.HUNTER_ARRAY, 315.0, 8, &"arsenal")
	stats.record_upgrade(RunBuild.REDLINE_CORE, 612.8, 10, &"catalyst")
	stats.set_apex_identity(&"velocity_reaver")
	stats.record_defeat(&"rift_weaver", true, &"horizon")
	stats.set_phase(&"overrun")
	var top_sources := stats.get_top_damage_sources()
	_expect(top_sources.size() == 3 and str(top_sources[0].id) == "dash_nova", "Damage sources should rank by actual applied damage.")
	_expect(int(top_sources[0].hits) == 2 and roundi(float(top_sources[0].damage)) == 100, "Damage accounting should retain hit count and source total.")
	_expect("DASH NOVA 80%" in stats.get_damage_breakdown_text(), "The recap breakdown should expose a readable contribution percentage.")
	_expect("SKIMMER CHARGE 64%" in stats.get_damage_taken_breakdown_text(), "The recap should identify the attack responsible for most incoming damage.")

	var build: RunBuild = RunBuildScript.new()
	for _rank in range(RunBuild.EVOLUTION_UNLOCK_RANK):
		build.apply_upgrade(&"dash_nova")
	build.apply_upgrade(&"ramjet")
	build.catalyst_id = RunBuild.REDLINE_CORE
	build.level = 9
	var summary := stats.snapshot(743.2, 88, build)
	_expect(str(summary.build_name) == "DASHBREAKER • RAMJET" and int(summary.level) == 9, "Run snapshots should identify the demonstrated build and level.")
	_expect(int(summary.elite_defeats) == 1 and str(summary.phase_reached) == "overrun", "Run snapshots should preserve encounter progress.")
	_expect(int(summary.elite_traits_defeated.horizon) == 1, "Run snapshots should identify which elite doctrines the build defeated for encounter balance review.")
	_expect(int(summary.dash_count) == 2 and is_equal_approx(float(summary.damage_taken), 22.0), "Run snapshots should preserve movement and survivability evidence.")
	_expect(int(summary.best_velocity_chain) == 12 and int(summary.velocity_chain_defeats) == 11, "Run snapshots should preserve best-chain and qualifying-defeat evidence without altering combat output.")
	_expect(is_equal_approx(float(summary.integrity_recovered), 12.0) and int(summary.recovery_pickups) == 1, "Run snapshots should measure applied recovery without counting empty pickups.")
	_expect(is_equal_approx(float(summary.damage_taken_by_source.skimmer_charge), 14.0) and int(summary.hits_taken_by_source.skimmer_charge) == 1, "Run snapshots should retain incoming damage and hit counts by attack source.")
	_expect(int(summary.rerolls_used) == 2 and int(summary.banishes_used) == 1, "Run snapshots should distinguish draft agency from favorable random rolls.")
	_expect(str(summary.apex_id) == "velocity_reaver", "Run snapshots should retain which climax encounter the build faced.")
	_expect(str(summary.catalyst_id) == "redline_core" and is_equal_approx(float(summary.catalyst_uptime), 0.6), "Run snapshots should retain the catalyst identity and measured empowered uptime.")
	_expect((summary.upgrade_history as Array).size() == 4 and (summary.upgrade_events as Array).size() == 4, "Run snapshots should retain timestamped choice history used for balance review.")
	var milestones := stats.get_build_milestone_times()
	_expect(is_equal_approx(float(milestones.engine), 12.4) and is_equal_approx(float(milestones.catalyst), 612.8), "Run telemetry should preserve the first occurrence of every major build milestone.")
	_expect("ENGINE 00:12" in stats.get_build_cadence_text() and "DRIVE 10:12" in stats.get_build_cadence_text(), "Cadence evidence should be readable in the player-facing recap.")
	var warden_stats: OverrushRunStats = RunStatsScript.new()
	warden_stats.reset(Vector3.ZERO)
	warden_stats.record_damage_taken(12.0, &"apex_gate")
	warden_stats.record_damage_taken(8.0, &"apex_lane")
	_expect("HORIZON GATE 60%" in warden_stats.get_damage_taken_breakdown_text() and "HORIZON CUT 40%" in warden_stats.get_damage_taken_breakdown_text(), "Warden gate and lane hits should remain distinguishable in playtest recaps.")

	if _failures.is_empty():
		print("Run statistics validation passed — damage attribution, traversal evidence, and bounded snapshots are deterministic.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
