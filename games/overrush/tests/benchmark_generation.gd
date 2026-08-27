extends SceneTree

const TARGET_MILLISECONDS := 2000.0
const BENCHMARK_SEEDS := [48920, 41001]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	for seed in BENCHMARK_SEEDS:
		var scene: Node = load("res://main.tscn").instantiate()
		scene.get_node("World").seed = seed
		var start := Time.get_ticks_usec()
		root.add_child(scene)
		await process_frame
		var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
		var has_alternate: bool = scene.get_node("World").grammar.has_alternate_route
		print(
			"GENERATION seed %d — alternate %s, %.2f ms (target < %.0f ms)"
			% [seed, str(has_alternate), elapsed_ms, TARGET_MILLISECONDS]
		)
		if elapsed_ms >= TARGET_MILLISECONDS:
			failures.append("seed %d took %.2f ms" % [seed, elapsed_ms])
		root.remove_child(scene)
		scene.free()
	if failures.is_empty():
		print("GENERATION BENCHMARK PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
