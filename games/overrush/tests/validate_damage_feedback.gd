extends SceneTree

var _failures: Array[String] = []
var _reported_amount := 0.0
var _reported_direction := Vector3.ZERO
var _reported_integrity_ratio := 1.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	root.add_child(scene)
	await process_frame
	scene.begin_run()
	await process_frame

	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var marker: Label = scene.get_node("HUD/DamageDirection")
	var vignette: ColorRect = scene.get_node("HUD/DamageVignette")
	var integrity_label: Label = scene.get_node("HUD/IntegrityLabel")
	runner.damaged.connect(_capture_damage)
	var source_position := runner.global_position + Vector3.RIGHT * 12.0
	runner.take_damage(18.0, source_position)
	await process_frame

	_expect(is_equal_approx(_reported_amount, 18.0), "Runner damage should report the amount actually removed.")
	_expect(_reported_direction.dot(Vector3.RIGHT) > 0.99, "Runner damage should report the attack's planar direction.")
	_expect(is_equal_approx(_reported_integrity_ratio, 0.82), "Runner damage should report remaining integrity as a ratio.")
	_expect(marker.visible, "A directional marker should appear immediately after damage.")
	_expect(marker.text.contains("→") and marker.text.contains("-18"), "The marker should communicate direction and numeric severity without relying on color.")
	var screen_center_x := root.get_visible_rect().size.x * 0.5
	_expect(marker.position.x + marker.size.x * 0.5 > screen_center_x, "A hit from the right should place its marker on the right side of the view.")
	_expect(vignette.visible and vignette.color.a > 0.05, "Damage should create an immediate edge-to-edge impact flash.")
	_expect(integrity_label.text == "INTEGRITY  82 / 100", "The HUD should always expose exact remaining integrity.")

	await create_timer(0.8, true, false, true).timeout
	_expect(not marker.visible and not vignette.visible, "Damage feedback should clear quickly so it cannot obscure traversal.")

	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Damage feedback validation passed — hit direction, severity, integrity, and recovery remain readable at speed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _capture_damage(amount: float, source_direction: Vector3, integrity_ratio: float) -> void:
	_reported_amount = amount
	_reported_direction = source_direction
	_reported_integrity_ratio = integrity_ratio


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
