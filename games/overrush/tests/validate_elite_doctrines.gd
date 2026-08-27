extends SceneTree

const EliteTraitCatalog = preload("res://scripts/elite_traits.gd")

const ELITE_ROLES: Array[StringName] = [&"skimmer", &"bulwark", &"rift_weaver", &"swarm_foundry"]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = 41001
	root.add_child(scene)
	await process_frame
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	director.stop_run()
	_clear_enemies(director)
	await process_frame
	runner.cruise_speed = 0.0
	runner.boost_speed = 0.0
	runner.velocity = Vector3.ZERO

	_validate_role_doctrine_matrix(director, runner)
	await process_frame
	_validate_scheduled_rotation(director)

	director.stop_run()
	_clear_enemies(director)
	paused = false
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Elite doctrine runtime validation passed — all role pairings, warning tradeoffs, silhouettes, rotation, and telemetry are active.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_role_doctrine_matrix(director: CombatDirector, runner: CharacterBody3D) -> void:
	for role_id in ELITE_ROLES:
		var measurements := {}
		for trait_id in EliteTraitCatalog.ORDER:
			var enemy: EnemyAgent = director._spawn_enemy(role_id, &"elite", trait_id)
			enemy.global_position = runner.global_position + Vector3.RIGHT * 64.0
			enemy._begin_special(runner.global_position - enemy.global_position)
			var expected_color := EliteTraitCatalog.get_color(trait_id)
			var warning_color: Color = enemy._telegraph_material.albedo_color
			_expect(enemy.elite_trait_id == trait_id, "%s should retain its assigned %s doctrine." % [role_id, trait_id])
			_expect(_has_doctrine_silhouette(enemy, trait_id), "%s %s should expose its doctrine through a unique silhouette." % [trait_id, role_id])
			_expect(Color(warning_color.r, warning_color.g, warning_color.b).is_equal_approx(expected_color), "%s %s warning geometry should match its shell identity." % [trait_id, role_id])
			enemy._set_telegraph_scale(1.0)
			_expect(is_equal_approx(enemy._telegraph_outline_mesh.scale.x, enemy._get_attack_radius()), "%s %s outline should exactly communicate its final attack footprint." % [trait_id, role_id])
			var telegraph_duration: float = enemy._state_duration
			var attack_radius: float = enemy._get_attack_radius()
			enemy._begin_recovery()
			measurements[trait_id] = {
				"health": enemy.maximum_health,
				"movement": enemy.movement_speed,
				"damage": enemy.contact_damage,
				"telegraph": telegraph_duration,
				"cooldown": enemy._special_cooldown,
				"radius": attack_radius,
				"charge_hit_distance": enemy._get_charge_hit_distance(),
			}
			enemy.queue_free()
			director._enemies.erase(enemy)
		var razor: Dictionary = measurements[EliteTraitCatalog.RAZOR]
		var horizon: Dictionary = measurements[EliteTraitCatalog.HORIZON]
		var tempest: Dictionary = measurements[EliteTraitCatalog.TEMPEST]
		_expect(float(razor.movement) > float(tempest.movement) and float(razor.health) < float(horizon.health), "%s Razor should be the fast, brittle intercept." % role_id)
		_expect(float(horizon.telegraph) > float(tempest.telegraph) and float(horizon.radius) > float(tempest.radius) and float(horizon.damage) < float(razor.damage), "%s Horizon should expose its larger, lower-impact geometry for longer." % role_id)
		_expect(float(tempest.cooldown) < float(razor.cooldown) and float(tempest.health) < float(horizon.health) and is_equal_approx(float(tempest.damage), float(horizon.damage)), "%s Tempest should repeat its lower-impact signature fastest through a brittle shell." % role_id)
		if role_id == &"skimmer":
			_expect(float(horizon.charge_hit_distance) > float(tempest.charge_hit_distance) and float(razor.charge_hit_distance) < float(tempest.charge_hit_distance), "Skimmer doctrine warning widths should match their actual charge hit distances.")


func _validate_scheduled_rotation(director: CombatDirector) -> void:
	var announcements: Array[Dictionary] = []
	director.event_announced.connect(func(title: String, subtitle: String) -> void:
		announcements.append({"title": title, "subtitle": subtitle})
	)
	director._elite_spawn_sequence = 0
	for index in range(3):
		director._spawn_scheduled_elite(index)
	_expect(director._elite_spawn_sequence == 3, "Scheduled and protocol elites should share one deterministic doctrine sequence.")
	_expect(announcements.size() == 3, "Every scheduled elite should announce its doctrine and role exactly once.")
	if announcements.size() < 3:
		return
	var observed: Array[StringName] = []
	for index in range(3):
		var expected_trait := EliteTraitCatalog.get_for_seed(int(director._world.generated_seed), index)
		var enemy: EnemyAgent = director._enemies[index]
		observed.append(enemy.elite_trait_id)
		_expect(enemy.elite_trait_id == expected_trait, "Scheduled elite %d should follow the world-seed doctrine rotation." % index)
		_expect(EliteTraitCatalog.get_title(expected_trait) in str(announcements[index].title), "Scheduled elite banner should name the doctrine before combat begins.")
		_expect(str(announcements[index].subtitle) == EliteTraitCatalog.get_subtitle(expected_trait), "Scheduled elite banner should explain the doctrine tradeoff.")
	_expect(observed.all(func(trait_id: StringName) -> bool: return observed.count(trait_id) == 1), "The first three elites should expose all doctrines exactly once without random streaks.")

	var defeated: EnemyAgent = director._enemies[0]
	var defeated_trait := defeated.elite_trait_id
	director._on_enemy_defeated(defeated, 0)
	_expect(int(director.run_stats.elite_traits_defeated.get(defeated_trait, 0)) == 1, "Defeating an elite should record its doctrine for playtest balance evidence.")


func _has_doctrine_silhouette(enemy: EnemyAgent, trait_id: StringName) -> bool:
	var prefix := "RazorDoctrine" if trait_id == EliteTraitCatalog.RAZOR else ("HorizonDoctrine" if trait_id == EliteTraitCatalog.HORIZON else "TempestDoctrine")
	for child in enemy.get_children():
		if child.name.begins_with(prefix):
			return true
	return false


func _clear_enemies(director: CombatDirector) -> void:
	for enemy in director._enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	director._enemies.clear()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
