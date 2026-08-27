extends SceneTree

const TEST_SEED := 41001
const MAX_COLLISION_ERROR := 1.0
const SETTLE_FRAMES := 120


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.get_node("World").seed = TEST_SEED
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var world = scene.get_node("World")
	var ball: CharacterBody3D = scene.get_node("RunnerBall")
	var space := root.world_3d.direct_space_state
	var maximum_error := 0.0
	for sample_index in range(3, world.grammar.primary_samples.size(), 4):
		var route_position: Vector3 = world.grammar.primary_samples[sample_index].position
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(route_position.x, 500.0, route_position.z),
			Vector3(route_position.x, -500.0, route_position.z)
		)
		query.exclude = [ball.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			push_error("Heightmap ray missed route sample %d." % sample_index)
			quit(1)
			return
		var expected_height: float = world.grammar.sample_height(route_position.x, route_position.z)
		maximum_error = maxf(maximum_error, absf(hit.position.y - expected_height))
	if maximum_error > MAX_COLLISION_ERROR:
		push_error("Heightmap differs from sampled terrain by %.3f m." % maximum_error)
		quit(1)
		return
	for frame in range(SETTLE_FRAMES):
		await physics_frame
	if not ball.is_on_floor():
		push_error("Runner did not settle on the heightmap collision.")
		quit(1)
		return
	print("Heightmap collision passed — maximum route error %.3f m; runner grounded." % maximum_error)
	quit(0)
