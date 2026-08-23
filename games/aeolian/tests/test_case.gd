class_name AeolianTestCase
extends RefCounted

var assertions := 0
var failures := 0
var current_test := ""


func run_test(name: String, test: Callable) -> void:
	current_test = name
	var failures_before := failures
	test.call()
	if failures == failures_before:
		print("  PASS %s" % name)


func assert_true(condition: bool, message := "Expected condition to be true") -> void:
	assertions += 1
	if not condition:
		_fail(message)


func assert_false(condition: bool, message := "Expected condition to be false") -> void:
	assert_true(not condition, message)


func assert_equal(actual: Variant, expected: Variant, message := "") -> void:
	assertions += 1
	if actual != expected:
		_fail(message if not message.is_empty() else "Expected %s, got %s" % [expected, actual])


func assert_not_equal(actual: Variant, unexpected: Variant, message := "") -> void:
	assertions += 1
	if actual == unexpected:
		_fail(message if not message.is_empty() else "Did not expect %s" % unexpected)


func assert_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_fail(message if not message.is_empty() else "Expected %.6f ± %.6f, got %.6f" % [
			expected, tolerance, actual,
		])


func _fail(message: String) -> void:
	failures += 1
	printerr("  FAIL %s: %s" % [current_test, message])

