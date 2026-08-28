extends SceneTree

const EXPECTED_SCRIPTS: Array[String] = [
	"air_boost_state.gd",
	"audio_director.gd",
	"desert_feature_grammar.gd",
	"follow_camera.gd",
	"freeride_main.gd",
	"input_bindings.gd",
	"jump_assist_state.gd",
	"landscape_layout.gd",
	"procedural_desert.gd",
	"sandboard_motion.gd",
	"sandboarder.gd",
]

const EXPECTED_SHADERS: Array[String] = ["desert.gdshader"]
const LEGACY_ENTRY_POINTS: Array[String] = [
	"res://main.tscn",
	"res://scripts/combat_director.gd",
	"res://scripts/enemy_agent.gd",
	"res://scripts/runner_ball.gd",
	"res://scripts/run_build.gd",
	"res://scripts/progress_profile.gd",
	"res://scripts/procedural_world.gd",
]

var _failures: Array[String] = []


func _init() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_expect(main_scene == "res://freeride.tscn", "The project must ship only the focused freeride scene.")
	for path in LEGACY_ENTRY_POINTS:
		_expect(not FileAccess.file_exists(path), "Legacy survivor entry point still exists: %s." % path)

	var actual_scripts := _source_files_in("res://scripts", ".gd")
	var expected_scripts := EXPECTED_SCRIPTS.duplicate()
	expected_scripts.sort()
	_expect(actual_scripts == expected_scripts, "Runtime scripts should match the focused freeride architecture: %s." % str(actual_scripts))
	var actual_shaders := _source_files_in("res://shaders", ".gdshader")
	var expected_shaders := EXPECTED_SHADERS.duplicate()
	expected_shaders.sort()
	_expect(actual_shaders == expected_shaders, "Only the final desert shader should remain: %s." % str(actual_shaders))

	_expect(OverrushInputBindings.ALL_ACTIONS.size() == 11, "Only traversal, camera, jump, boost, and pause inputs should remain.")
	var effect_ids: Array[String] = []
	for effect_id in OverrushAudioDirector.EFFECT_DURATIONS:
		effect_ids.append(str(effect_id))
	effect_ids.sort()
	var expected_effects: Array[String] = ["air_boost", "jump", "landing_clean", "landing_rough", "landing_solid", "obstacle_impact"]
	_expect(effect_ids == expected_effects, "Audio should contain only core movement feedback: %s." % str(effect_ids))
	var motion_loop_ids: Array[String] = []
	for loop_id in OverrushAudioDirector.MOTION_LOOP_IDS:
		motion_loop_ids.append(str(loop_id))
	motion_loop_ids.sort()
	_expect(
		motion_loop_ids == ["grass_surface", "sand_surface", "wind"],
		"Continuous audio should remain limited to the three traversal layers: %s." % str(motion_loop_ids),
	)

	if _failures.is_empty():
		print("Project scope passed — one freeride scene, 11 runtime scripts, one shader, 11 inputs, 3 traversal loops, and 6 event cues remain.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _source_files_in(path: String, suffix: String) -> Array[String]:
	var files: Array[String] = []
	for file_name in DirAccess.get_files_at(path):
		if file_name.ends_with(suffix):
			files.append(file_name)
	files.sort()
	return files


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
