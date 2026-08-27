extends SceneTree

const ExperiencePickupScript = preload("res://scripts/experience_pickup.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_dash_speed_collection()
	await _validate_recovery_and_value_silhouettes()
	await _validate_zero_value_drops()
	if _failures.is_empty():
		print("Pickup flow validation passed — cores catch dash-speed runners, recover stale rewards, communicate value, and skip empty drops.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_dash_speed_collection() -> void:
	var target := CharacterBody3D.new()
	root.add_child(target)
	target.velocity = Vector3.RIGHT * 126.0
	var pickup: ExperiencePickup = ExperiencePickupScript.new()
	root.add_child(pickup)
	pickup.global_position = Vector3.LEFT * 20.0
	pickup.configure(target, 7, 38.0)
	var collected_values: Array[int] = []
	pickup.collected.connect(func(collected_value: int) -> void:
		collected_values.append(collected_value)
	)
	for _frame in range(90):
		await physics_frame
		target.global_position += target.velocity / 60.0
		if not collected_values.is_empty():
			break
	_expect(collected_values == [7], "A latched core should overtake and collect against a 126 m/s dash-speed target.")
	await process_frame
	target.queue_free()
	await process_frame


func _validate_recovery_and_value_silhouettes() -> void:
	var target := CharacterBody3D.new()
	root.add_child(target)
	target.velocity = Vector3.FORWARD * 88.0
	var stale_pickup: ExperiencePickup = ExperiencePickupScript.new()
	root.add_child(stale_pickup)
	stale_pickup.global_position = Vector3.BACK * 400.0
	stale_pickup.configure(target, 3, 38.0)
	var starting_distance := stale_pickup.global_position.distance_to(target.global_position)
	stale_pickup._age = stale_pickup.RECOVERY_DELAY
	await physics_frame
	await physics_frame
	_expect(stale_pickup.is_magnetized(), "An old off-route core should enter recovery even outside the normal magnet radius.")
	_expect(stale_pickup.global_position.distance_to(target.global_position) < starting_distance, "Recovery should immediately move a stale core toward the runner.")

	var elite_pickup: ExperiencePickup = ExperiencePickupScript.new()
	root.add_child(elite_pickup)
	elite_pickup.global_position = Vector3.LEFT * 80.0
	elite_pickup.configure(target, 35, 38.0)
	_expect(stale_pickup.get_visual_tier() == 0 and elite_pickup.get_visual_tier() == 2, "Pickup value should select distinct standard and elite silhouettes.")
	_expect(elite_pickup.get_child_count() > stale_pickup.get_child_count(), "Elite rewards should use additional geometric rings instead of relying on color alone.")
	elite_pickup.queue_free()
	var recovered_values: Array[int] = []
	stale_pickup.collected.connect(func(collected_value: int) -> void:
		recovered_values.append(collected_value)
	)
	for _frame in range(240):
		await physics_frame
		target.global_position += target.velocity / 60.0
		if not recovered_values.is_empty():
			break
	_expect(recovered_values == [3], "A recovered core should catch and collect against a continuously boosted target within four seconds.")
	target.queue_free()
	await process_frame


func _validate_zero_value_drops() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	root.add_child(scene)
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var drone: EnemyAgent = director._spawn_enemy(&"drone")
	drone.take_damage(drone.health + 1.0)
	await process_frame
	var pickup_count := 0
	for child in director.get_children():
		if child is ExperiencePickup:
			pickup_count += 1
	_expect(pickup_count == 0, "Zero-reward summons should not leave deceptive or permanent pickup nodes.")
	paused = false
	scene.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
