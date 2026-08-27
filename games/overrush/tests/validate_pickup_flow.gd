extends SceneTree

const ExperiencePickupScript = preload("res://scripts/experience_pickup.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_dash_speed_collection()
	await _validate_recovery_and_value_silhouettes()
	await _validate_integrity_recovery_flow()
	await _validate_zero_value_drops()
	if _failures.is_empty():
		print("Pickup flow validation passed — experience and bounded integrity cores catch fast runners, communicate purpose, and skip empty drops.")
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


func _validate_integrity_recovery_flow() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_manual_start", true)
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 77131
	root.add_child(scene)
	await process_frame
	scene.begin_run()
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director._spawn_timer = INF
	director._rewarding_defeats_since_recovery = director.RECOVERY_DROP_STRIDE - 1
	var enemy: EnemyAgent = director._spawn_enemy(&"pursuer")
	enemy.global_position = runner.global_position + Vector3.RIGHT * 28.0
	enemy.take_damage(enemy.health + 1.0, &"dash_nova")
	await process_frame
	var recovery: ExperiencePickup
	for child in director.get_children():
		if child is ExperiencePickup and child.is_integrity_pickup():
			recovery = child
			break
	_expect(is_instance_valid(recovery), "Every eighteenth rewarding defeat should create one deterministic integrity core.")
	if is_instance_valid(recovery):
		_expect(recovery.get_child_count() == 7, "Integrity cores should use a unique squat, ringed silhouette with four satellites.")
		recovery.global_position = runner.global_position
		await physics_frame
		_expect(is_instance_valid(recovery) and not recovery.is_queued_for_deletion(), "A full-integrity runner should be able to bank a recovery core instead of wasting it.")
		runner.take_damage(25.0, runner.global_position + Vector3.RIGHT, &"pursuer_contact")
		var damaged_integrity: float = runner.integrity
		for _frame in range(30):
			await physics_frame
			if not is_instance_valid(recovery) or recovery.is_queued_for_deletion():
				break
		_expect(is_equal_approx(runner.integrity, damaged_integrity + float(director.STANDARD_RECOVERY_VALUE)), "A banked standard integrity core should apply its bounded repair once the runner is damaged.")
		_expect(is_equal_approx(director.run_stats.integrity_recovered, float(director.STANDARD_RECOVERY_VALUE)) and director.run_stats.recovery_pickups == 1, "Applied recovery should be recorded once in run telemetry.")
	runner.repair_integrity(runner.maximum_integrity)
	var elite: EnemyAgent = director._spawn_enemy(&"pursuer", &"elite")
	elite.global_position = runner.global_position + Vector3.RIGHT * 34.0
	elite.take_damage(elite.health + 1.0, &"dash_nova")
	await process_frame
	var elite_recovery: ExperiencePickup
	for child in director.get_children():
		if child is ExperiencePickup and child.is_integrity_pickup():
			elite_recovery = child
			break
	_expect(is_instance_valid(elite_recovery) and elite_recovery.value == director.ELITE_RECOVERY_VALUE, "Every rewarding elite should guarantee a larger integrity core when the world cap has room.")
	_expect(director._rewarding_defeats_since_recovery == 1, "An elite bonus should not postpone the regular recovery cadence.")
	while director._count_active_recovery_pickups() < director.MAX_ACTIVE_RECOVERY_PICKUPS:
		director._spawn_pickup(runner.global_position + Vector3.FORWARD * (12.0 + director._count_active_recovery_pickups() * 3.0), director.STANDARD_RECOVERY_VALUE, ExperiencePickup.INTEGRITY)
	director._rewarding_defeats_since_recovery = director.RECOVERY_DROP_STRIDE - 1
	var capped_enemy: EnemyAgent = director._spawn_enemy(&"pursuer")
	capped_enemy.take_damage(capped_enemy.health + 1.0, &"dash_nova")
	await process_frame
	_expect(director._count_active_recovery_pickups() == director.MAX_ACTIVE_RECOVERY_PICKUPS and director._rewarding_defeats_since_recovery == director.RECOVERY_DROP_STRIDE, "Three banked integrity cores should cap world clutter without discarding an earned cadence drop.")
	for child in director.get_children():
		if child is ExperiencePickup and child.is_integrity_pickup():
			child.queue_free()
			break
	await process_frame
	var deferred_enemy: EnemyAgent = director._spawn_enemy(&"pursuer")
	deferred_enemy.take_damage(deferred_enemy.health + 1.0, &"dash_nova")
	await process_frame
	_expect(director._count_active_recovery_pickups() == director.MAX_ACTIVE_RECOVERY_PICKUPS and director._rewarding_defeats_since_recovery == 0, "A deferred cadence drop should appear on the next rewarding defeat once a world slot opens.")
	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
