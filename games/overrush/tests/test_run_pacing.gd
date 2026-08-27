extends SceneTree

const RunPacingModel = preload("res://scripts/run_pacing.gd")

var _failures: Array[String] = []


func _init() -> void:
	var pacing := RunPacingModel.new()
	_expect(pacing.get_phase_id(0.0) == &"breakaway", "Runs should begin in Breakaway.")
	_expect(pacing.get_phase_id(180.0) == &"pressure", "The first elite should begin Pressure Rises.")
	_expect(pacing.get_phase_id(420.0) == &"redline", "Seven minutes should begin Redline.")
	_expect(pacing.get_phase_id(720.0) == &"overrun", "Twelve minutes should begin Overrun.")
	_expect(pacing.get_phase_id(1080.0) == &"apex", "Eighteen minutes should begin the Apex climax.")
	_expect(pacing.get_objective_status(0.0) == "APEX IN 18:00", "The live objective should state when the climax begins.")
	_expect(pacing.get_objective_status(1079.2) == "APEX IN 00:01", "The pre-Apex countdown should round up so it never announces the climax early.")
	_expect(pacing.get_objective_status(1080.0) == "BREAK THE APEX  • 02:00 LEFT", "The climax should replace arrival timing with the actual victory deadline.")
	_expect(pacing.get_objective_status(1300.0) == "BREAK THE APEX  • 00:00 LEFT", "The objective clock should remain bounded after the run deadline.")
	_expect(pacing.get_crossed_elite_indices(179.0, 181.0) == PackedInt32Array([0]), "Crossing three minutes should schedule exactly the first elite.")
	_expect(pacing.get_crossed_elite_indices(181.0, 419.0).is_empty(), "Elite events should not repeat between milestones.")
	_expect(pacing.crossed_apex_time(1079.9, 1080.1), "Crossing eighteen minutes should schedule the Apex.")
	_expect(pacing.crossed_deadline(1199.9, 1200.1), "Crossing twenty minutes should resolve an unfinished run.")
	_expect(pacing.get_intensity(900.0) > pacing.get_intensity(300.0), "Run intensity should escalate materially over time.")
	_expect(pacing.get_spawn_interval(900.0) < pacing.get_spawn_interval(300.0), "Later phases should spawn threats faster.")
	_expect(not pacing.is_build_milestone_available(&"arsenal", 149.9) and pacing.is_build_milestone_available(&"arsenal", 150.0), "The arsenal beat should open exactly at its authored lower bound.")
	_expect(not pacing.is_build_milestone_available(&"catalyst", 359.9) and pacing.is_build_milestone_available(&"catalyst", 360.0), "The Drive beat should remain protected until six minutes.")
	var intentional_cadence := {
		&"engine": 12.0,
		&"evolution": 90.0,
		&"arsenal": 240.0,
		&"catalyst": 600.0,
	}
	_expect(pacing.get_build_cadence_failures(intentional_cadence).is_empty(), "The authored progression windows should accept a staged full-build arc before Overrun.")
	intentional_cadence.erase(&"arsenal")
	_expect(pacing.get_build_cadence_failures(intentional_cadence) == [&"arsenal"], "Cadence validation should identify a missing build fork instead of treating partial progression as complete.")

	if _failures.is_empty():
		print("Run pacing validation passed — phases, elites, Apex, and deadline are scheduled.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
