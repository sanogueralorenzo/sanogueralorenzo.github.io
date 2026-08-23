extends SceneTree

const SUITES := [
	preload("res://tests/test_seed_service.gd"),
	preload("res://tests/test_settings_schema.gd"),
	preload("res://tests/test_input_binding_codec.gd"),
	preload("res://tests/test_game_state_machine.gd"),
	preload("res://tests/test_profile_schema.gd"),
	preload("res://tests/test_safe_config_file.gd"),
]
const TEST_CASE := preload("res://tests/test_case.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("AEOLIAN foundation tests")
	var suite: RefCounted = TEST_CASE.new()
	for test_suite: GDScript in SUITES:
		test_suite.run(suite)
	print("Assertions: %d · Failures: %d" % [suite.assertions, suite.failures])
	quit(0 if suite.failures == 0 else mini(suite.failures, 125))
