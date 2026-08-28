extends SceneTree

const TEST_SEED := 73013
const APPROACH_SPEED := 88.0
const TEST_PHYSICS_TICKS := 30
const NEAR_MISS_OFFSET := 1.55
const TIMEOUT_FRAMES := 180

var _crash_kind := &""
var _impact_speed := 0.0
var _failures: Array[String] = []


func _init() -> void:
	Engine.physics_ticks_per_second = TEST_PHYSICS_TICKS
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
	_expect(not paused and not scene.pause_overlay.visible, "The result panel should wait while the frozen impact feedback remains visible.")
	_expect(rider.landing_burst.emitting, "A fatal obstacle impact should produce immediate contact debris during the consequence beat.")
	await _wait_for_crash_overlay(scene)
	_expect(paused and scene.pause_overlay.visible, "A fatal impact should freeze play and show the run-ended overlay.")
	_expect(not scene.resume_button.visible and scene.restart_button.visible, "A crashed run may restart but must not resume through the obstacle.")
	_expect("TREE IMPACT" in scene.pause_title.text, "The run-ended overlay should explain the collision immediately.")
	_expect(
		rider.board_visual.position.y <= -0.1
			and absf(rider.torso_visual.rotation.x - rider._rider_base_rotations[0].x) >= deg_to_rad(18.0)
			and absf(rider.left_arm_visual.rotation.z - rider._rider_base_rotations[2].z) >= deg_to_rad(28.0),
		"A fatal impact should freeze the board and rider in a readable collision pose: board %.2f, torso %.1f°, arm %.1f°."
		% [
			rider.board_visual.position.y,
			rad_to_deg(absf(rider.torso_visual.rotation.x - rider._rider_base_rotations[0].x)),
			rad_to_deg(absf(rider.left_arm_visual.rotation.z - rider._rider_base_rotations[2].z)),
		],
	)

	scene.restart_run()
	_crash_kind = &""
	_impact_speed = 0.0
	var passed_tree := await _skim_target(scene, world, rider, tree_target.position)
	_expect(passed_tree, "The maximum-speed near-miss test should travel beyond the tree.")
	_expect(
		not scene._run_crashed and _crash_kind.is_empty(),
		"A close pass outside the combined rider/trunk envelope must remain recoverable.",
	)

	scene.restart_run()
	var rock_target := _find_obstacle_target(world, "RockFieldObstacles")
	_expect(not rock_target.is_empty(), "The collision test needs a streamed rock-field obstacle.")
	if not rock_target.is_empty():
		_crash_kind = &""
		_impact_speed = 0.0
		await _strike_target(scene, world, rider, rock_target.position)
		await _wait_for_crash_overlay(scene)
		_expect(scene._run_crashed and _crash_kind == &"rock", "A direct rock strike at speed should end the run as a rock impact.")
		_expect("ROCK IMPACT" in scene.pause_title.text, "The run-ended overlay should identify a rock collision immediately.")

	scene.restart_run()
	var ruin_target := _find_ruin_target(world, rider)
	_expect(not ruin_target.is_empty(), "The collision test needs a streamed ruin column obstacle.")
	if not ruin_target.is_empty():
		_crash_kind = &""
		_impact_speed = 0.0
		await _strike_target(scene, world, rider, ruin_target.position)
		await _wait_for_crash_overlay(scene)
		_expect(scene._run_crashed and _crash_kind == &"ruin", "A direct ruin strike at speed should end the run as a ruin impact.")
		_expect("RUIN IMPACT" in scene.pause_title.text, "The run-ended overlay should identify a ruin collision immediately.")

	scene.restart_run()
	_expect(not paused and scene.run_active and not scene._run_crashed, "Drop Again should start a clean run from the summit.")
	_expect(not rider._crashed and rider.velocity.is_zero_approx(), "Restart must clear the rider crash state and momentum.")
	_expect(
		rider.board_visual.position.is_zero_approx()
			and rider.torso_visual.rotation.is_equal_approx(rider._rider_base_rotations[0]),
		"Drop Again must clear the collision pose before returning to the summit.",
	)
	_expect(
		rider._carve_track_points.is_empty()
			and (scene.get_node("CarveTrack") as MeshInstance3D).mesh == null,
		"Drop Again must clear the previous run's carve track.",
	)
	await _finish(scene)


func _strike_target(scene: Node, world: ProceduralDesert, rider: Sandboarder, target_position: Vector3) -> void:
	var approach_direction := Vector3(1.0, 0.0, 0.0)
	var start_xz := Vector2(target_position.x, target_position.z) - Vector2(approach_direction.x, approach_direction.z) * 12.0
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


func _skim_target(scene: Node, world: ProceduralDesert, rider: Sandboarder, target_position: Vector3) -> bool:
	var approach_direction := Vector3(1.0, 0.0, 0.0)
	var target_xz := Vector2(target_position.x, target_position.z)
	var start_xz := (
		target_xz
		+ Vector2(0.0, NEAR_MISS_OFFSET)
		- Vector2(approach_direction.x, approach_direction.z) * 12.0
	)
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
			return false
		var logical_position := world.get_world_position(rider.global_position)
		if logical_position.x >= target_position.x + 8.0:
			return true
	return false


func _wait_for_crash_overlay(scene: Node) -> void:
	for _frame in range(60):
		if paused and scene.pause_overlay.visible:
			return
		await process_frame


func _find_obstacle_target(world: ProceduralDesert, obstacle_name: String) -> Dictionary:
	for chunk_value in world.loaded_chunks.values():
		var chunk := chunk_value as StaticBody3D
		var obstacle_body := chunk.get_node_or_null(obstacle_name) as StaticBody3D
		if obstacle_body == null:
			continue
		if obstacle_name == "ForestObstacles":
			var tree_positions: PackedVector3Array = obstacle_body.get_meta(&"tree_positions", PackedVector3Array())
			if not tree_positions.is_empty():
				var local_position: Vector3 = chunk.position + obstacle_body.position + tree_positions[0]
				return {"position": world.get_world_position(local_position)}
		for child in obstacle_body.get_children():
			if child is CollisionShape3D:
				var local_position: Vector3 = chunk.position + obstacle_body.position + child.position
				return {"position": world.get_world_position(local_position)}
	return {}


func _find_ruin_target(world: ProceduralDesert, rider: Sandboarder) -> Dictionary:
	var nearest_coord := Vector2i(2147483647, 2147483647)
	var nearest_distance := INF
	for y in range(-8, 9):
		for x in range(-8, 9):
			var coord := Vector2i(x, y)
			if not world.chunk_has_ruin(coord):
				continue
			var distance := Vector2(coord).length_squared()
			if distance < nearest_distance:
				nearest_coord = coord
				nearest_distance = distance
	if nearest_coord.x == 2147483647:
		return {}
	var focus := Vector2(nearest_coord) * world.chunk_size
	rider.global_position = world.world_to_local_position(Vector3(
		focus.x,
		world.get_surface_height(focus.x, focus.y) + 0.5,
		focus.y,
	))
	world.maintain_streaming(true)
	for ruin in world.get_loaded_ruin_bodies():
		if ruin.name != "Ruin_%d_%d" % [nearest_coord.x, nearest_coord.y]:
			continue
		var column := ruin.get_node_or_null("LeftColumnCollision") as CollisionShape3D
		if column != null:
			return {"position": world.get_world_position(column.global_position)}
	return {}


func _on_crashed(obstacle_kind: StringName, impact_speed: float) -> void:
	_crash_kind = obstacle_kind
	_impact_speed = impact_speed


func _finish(scene: Node) -> void:
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print(
			"Fatal obstacle collision passed — 88 m/s tree, rock, and ruin strikes remain fatal at 30 Hz, a 1.55 m tree skim stays fair, and Drop Again resets cleanly."
		)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
