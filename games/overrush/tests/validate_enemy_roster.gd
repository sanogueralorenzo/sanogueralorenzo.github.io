extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 128110
	root.add_child(scene)
	await process_frame
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.stop_run()
	for enemy in director._enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	director._enemies.clear()
	await process_frame
	runner.cruise_speed = 0.0
	runner.boost_speed = 0.0
	runner.velocity = Vector3.ZERO

	_validate_phase_roster(director)
	_validate_rift_weaver(director, runner)
	await process_frame
	_validate_swarm_foundry(director, runner)
	await process_frame

	director.stop_run()
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Enemy roster validation passed — phase gates, remote blast, and bounded foundry reinforcements are active.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_phase_roster(director: CombatDirector) -> void:
	var pressure := director._get_roster_weights(1, 240.0)
	var redline := director._get_roster_weights(2, 600.0)
	_expect(_roster_has(pressure, &"rift_weaver"), "Pressure should introduce positional Rift Weaver attacks.")
	_expect(not _roster_has(pressure, &"swarm_foundry"), "Swarm Foundries should wait until Redline before multiplying packs.")
	_expect(_roster_has(redline, &"swarm_foundry"), "Redline should introduce target-priority Swarm Foundries.")
	_expect(is_equal_approx(_roster_total(redline), 1.0), "Enemy roster weights should form a complete probability distribution.")

	director.elapsed_time = 13.0 * 60.0
	director._rng.seed = 78123
	var counts := {}
	for _sample in range(600):
		var archetype := director._choose_archetype()
		counts[archetype] = int(counts.get(archetype, 0)) + 1
	for archetype in [&"pursuer", &"skimmer", &"bulwark", &"rift_weaver", &"swarm_foundry"]:
		_expect(int(counts.get(archetype, 0)) >= 35, "Redline sampling should retain the %s role instead of collapsing into a dominant roster." % archetype)


func _validate_rift_weaver(director: CombatDirector, runner: CharacterBody3D) -> void:
	director._run_active = true
	var weaver: EnemyAgent = director._spawn_enemy(&"rift_weaver")
	weaver.global_position = runner.global_position + Vector3.RIGHT * 72.0
	weaver._special_cooldown = 0.0
	var warnings: Array[StringName] = []
	weaver.attack_telegraphed.connect(func(_enemy: EnemyAgent, kind: StringName) -> void: warnings.append(kind))
	weaver._update_chase(runner.global_position - weaver.global_position, 72.0, 0.016)
	_expect(not warnings.is_empty() and warnings[0] == &"rift_blast", "Rift Weaver should identify its remote blast through the shared warning channel.")
	_expect(weaver.get_attack_state() == EnemyAgent.AttackState.TELEGRAPH, "Rift Weaver damage should begin with a telegraph state.")
	_expect(weaver._telegraph_mesh.top_level and weaver._telegraph_mesh.visible, "The Rift Weaver warning should be a world-space marker rather than an ambiguous aura around the caster.")
	_expect(Vector2(weaver._attack_center.x - runner.global_position.x, weaver._attack_center.z - runner.global_position.z).length() < 0.1, "A stationary runner should see the Rift Weaver marker centered on its current route.")
	var integrity_before: float = runner.integrity
	weaver._update_telegraph(0.5)
	_expect(is_equal_approx(runner.integrity, integrity_before), "Rift Weaver blast should remain harmless during its readable warning window.")
	weaver._update_telegraph(0.6)
	_expect(runner.integrity < integrity_before, "Ignoring a completed Rift Weaver marker should deal damage.")
	runner.velocity = runner.heading.normalized() * 58.0
	weaver._begin_special(runner.global_position - weaver.global_position)
	var projected_offset := Vector2(
		weaver._attack_center.x - runner.global_position.x,
		weaver._attack_center.z - runner.global_position.z
	).length()
	_expect(is_equal_approx(projected_offset, 58.0 * EnemyAgent.RIFT_PREDICTION_SECONDS), "Rift Weaver should lead normal cruise far enough that continuing straight remains unsafe when the blast resolves.")
	runner.velocity = Vector3.ZERO
	weaver.queue_free()
	director._enemies.erase(weaver)


func _validate_swarm_foundry(director: CombatDirector, runner: CharacterBody3D) -> void:
	director._run_active = true
	var foundry: EnemyAgent = director._spawn_enemy(&"swarm_foundry")
	foundry.global_position = runner.global_position + Vector3.FORWARD * 76.0
	foundry._special_cooldown = 0.0
	var count_before := director.get_enemy_count()
	foundry._update_chase(runner.global_position - foundry.global_position, 76.0, 0.016)
	_expect(foundry._attack_kind == &"foundry_bloom" and foundry.get_attack_state() == EnemyAgent.AttackState.TELEGRAPH, "Swarm Foundry should visibly charge before adding pressure.")
	foundry._update_telegraph(1.0)
	var drones := 0
	for enemy in director._enemies:
		if is_instance_valid(enemy) and enemy.archetype == &"drone":
			drones += 1
			_expect(enemy.experience_value == 0 and enemy.maximum_health < foundry.maximum_health * 0.2, "Summoned drones should be fragile pressure, not an experience exploit.")
	_expect(director.get_enemy_count() == count_before + 2 and drones == 2, "A standard Foundry bloom should add exactly two bounded drones.")
	for enemy in director._enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	director._enemies.clear()


func _roster_has(roster: Array, archetype: StringName) -> bool:
	for entry in roster:
		if StringName(entry[0]) == archetype:
			return true
	return false


func _roster_total(roster: Array) -> float:
	var total := 0.0
	for entry in roster:
		total += float(entry[1])
	return total


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
