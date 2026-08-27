extends SceneTree

const EARLY_SIMULATION_FRAMES := 600
const TOTAL_SIMULATION_FRAMES := 2400


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = 41777
	root.add_child(scene)
	await physics_frame
	var rider: Sandboarder = scene.get_node("Sandboarder")
	var start_position := rider.global_position
	scene.begin_run()
	Input.action_press(OverrushInputBindings.MOVE_FORWARD)
	var peak_speed := 0.0
	for _frame in range(EARLY_SIMULATION_FRAMES):
		await physics_frame
		peak_speed = maxf(peak_speed, rider.get_horizontal_speed())

	var planar_distance := Vector2(
		rider.global_position.x - start_position.x,
		rider.global_position.z - start_position.z
	).length()
	var descent := start_position.y - rider.global_position.y
	if planar_distance < 18.0:
		push_error("Sandboarder only travelled %.1f m after deliberate carve input." % planar_distance)
		await _finish(scene, 1)
		return
	if descent < 0.5:
		push_error("Sandboarder did not begin descending from the central summit: %.2f m." % descent)
		await _finish(scene, 1)
		return
	if rider.get_horizontal_speed() < 10.0:
		push_error("Slope-driven movement did not gather useful speed: %.1f m/s." % rider.get_horizontal_speed())
		await _finish(scene, 1)
		return
	for _frame in range(TOTAL_SIMULATION_FRAMES - EARLY_SIMULATION_FRAMES):
		await physics_frame
		peak_speed = maxf(peak_speed, rider.get_horizontal_speed())
	Input.action_release(OverrushInputBindings.MOVE_FORWARD)
	if peak_speed < 28.0:
		push_error(
			"Extended downhill carving never reached a satisfying speed: %.1f m/s across %.1f m (final y %.1f)."
			% [peak_speed, rider.distance_traveled, rider.global_position.y]
		)
		await _finish(scene, 1)
		return
	if rider.distance_traveled < 420.0:
		push_error("Extended downhill carving covered too little terrain: %.1f m." % rider.distance_traveled)
		await _finish(scene, 1)
		return
	print(
		"Sandboard motion passed — %.1f m early travel, %.1f m early descent, %.1f m/s peak across %.1f m of sustained carving."
		% [planar_distance, descent, peak_speed, rider.distance_traveled]
	)
	await _finish(scene, 0)


func _finish(scene: Node, exit_code: int) -> void:
	scene.queue_free()
	await process_frame
	quit(exit_code)
