extends SceneTree

const TEST_SEED := 73013
const APPROACH_SPEED := 28.0
const TIMEOUT_FRAMES := 180

var _crash_kind := &""
var _impact_speed := 0.0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://freeride.tscn").instantiate()
	scene.set_meta(&"overrush_manual_start", true)
	scene.get_node("Desert").seed = TEST_SEED
	root.add_child(scene)
	await physics_frame
	var world: ProceduralDesert = scene.get_node("Desert")
	var rider: Sandboarder = scene.get_node("Sandboarder")
	rider.crashed.connect(_on_crashed)
	var tree_target := _find_obstacle_target(world, "ForestObstacles")
	_expect(not tree_target.is_empty(), "The collision test needs a streamed tree obstacle.")
	if tree_target.is_empty():
		await _finish(scene)
		return
	scene.begin_run()
	await _strike_target(scene, world, rider, tree_target.position)

	_expect(scene._run_crashed and not scene.run_active, "A direct tree strike at speed should end the active run.")
	_expect(_crash_kind == &"tree", "The crash should identify the contacted tree, received %s." % _crash_kind)
	_expect(_impact_speed >= rider.fatal_obstacle_impact_speed, "The reported impact must meet the fatal closing-speed threshold.")
	_expect(paused and scene.pause_overlay.visible, "A fatal impact should freeze play and show the run-ended overlay.")
	_expect(not scene.resume_button.visible and scene.restart_button.visible, "A crashed run may restart but must not resume through the obstacle.")
	_expect("TREE IMPACT" in scene.pause_title.text, "The run-ended overlay should explain the collision immediately.")

	scene.restart_run()
	var rock_target := _find_obstacle_target(world, "RockFieldObstacles")
	_expect(not rock_target.is_empty(), "The collision test needs a streamed rock-field obstacle.")
	if not rock_target.is_empty():
		_crash_kind = &""
		_impact_speed = 0.0
		await _strike_target(scene, world, rider, rock_target.position)
		_expect(scene._run_crashed and _crash_kind == &"rock", "A direct rock strike at speed should end the run as a rock impact.")
		_expect("ROCK IMPACT" in scene.pause_title.text, "The run-ended overlay should identify a rock collision immediately.")

	scene.restart_run()
	_expect(not paused and scene.run_active and not scene._run_crashed, "Drop Again should start a clean run from the summit.")
	_expect(not rider._crashed and rider.velocity.is_zero_approx(), "Restart must clear the rider crash state and momentum.")
	await _finish(scene)


func _strike_target(scene: Node, world: ProceduralDesert, rider: Sandboarder, target_position: Vector3) -> void:
	var approach_direction := Vector3(1.0, 0.0, 0.0)
	var start_xz := Vector2(target_position.x, target_position.z) - Vector2(approach_direction.x, approach_direction.z) * 7.0
	var start_logical := Vector3(
		start_xz.x,
		world.get_surface_height(start_xz.x, start_xz.y) + 0.5,
		start_xz.y,
	)
	rider.global_position = world.world_to_local_position(start_logical)
	rider._last_position = rider.global_position
	rider.velocity = Vector3.ZERO
	for _frame in range(5):
		await physics_frame
	rider.velocity = approach_direction * APPROACH_SPEED
	for _frame in range(TIMEOUT_FRAMES):
		await physics_frame
		if scene._run_crashed:
			return


func _find_obstacle_target(world: ProceduralDesert, obstacle_name: String) -> Dictionary:
	for chunk_value in world.loaded_chunks.values():
		var chunk := chunk_value as StaticBody3D
		var obstacle_body := chunk.get_node_or_null(obstacle_name) as StaticBody3D
		if obstacle_body == null:
			continue
		for child in obstacle_body.get_children():
			if child is CollisionShape3D:
				var local_position: Vector3 = chunk.position + obstacle_body.position + child.position
				return {"position": world.get_world_position(local_position)}
	return {}


func _on_crashed(obstacle_kind: StringName, impact_speed: float) -> void:
	_crash_kind = obstacle_kind
	_impact_speed = impact_speed


func _finish(scene: Node) -> void:
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Fatal obstacle collision passed — direct tree and rock strikes end the run while Drop Again resets cleanly.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
