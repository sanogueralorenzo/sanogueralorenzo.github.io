extends SceneTree

const ApexCatalogModel = preload("res://scripts/apex_catalog.gd")

var _failures: Array[String] = []
var _attack_kind := &""
var _enrage_announced := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog()
	await _validate_velocity_reaver()
	await _validate_rift_matriarch()
	await _validate_horizon_warden()
	if _failures.is_empty():
		print("Apex variant validation passed — three deterministic encounters provide distinct charges, rifts, broods, gates, lanes, escalation, and HUD identity.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_catalog() -> void:
	_expect(ApexCatalogModel.IDS.size() == 3, "The deterministic Apex rotation should expose three encounters.")
	_expect(ApexCatalogModel.get_for_seed(41001) == ApexCatalogModel.RIFT_MATRIARCH, "Seed 41001 should preserve the Rift Matriarch climax.")
	_expect(ApexCatalogModel.get_for_seed(41002) == ApexCatalogModel.HORIZON_WARDEN, "Seed 41002 should select the Horizon Warden.")
	_expect(ApexCatalogModel.get_for_seed(48920) == ApexCatalogModel.VELOCITY_REAVER, "Seed 48920 should preserve the Velocity Reaver climax.")
	var titles := {}
	for apex_id in ApexCatalogModel.IDS:
		titles[ApexCatalogModel.get_title(apex_id)] = true
	_expect(titles.size() == ApexCatalogModel.IDS.size(), "Each Apex should expose a distinct player-facing identity.")


func _validate_velocity_reaver() -> void:
	var scene := await _create_scene(48920)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var world: Node3D = scene.get_node("World")
	director._spawn_apex(ApexCatalogModel.VELOCITY_REAVER)
	var reaver: EnemyAgent = director._apex
	reaver.global_position = runner.global_position + Vector3.FORWARD * 58.0
	reaver.global_position.y = world.get_surface_height(reaver.global_position.x, reaver.global_position.z) + reaver.body_radius
	_attack_kind = &""
	reaver.attack_telegraphed.connect(func(_enemy: EnemyAgent, kind: StringName) -> void: _attack_kind = kind)
	reaver._special_cooldown = 0.0
	await physics_frame
	await physics_frame
	_expect(_attack_kind == &"apex_charge", "The Velocity Reaver should open with a committed line charge that rewards lateral traversal.")
	_expect(not reaver._telegraph_mesh.top_level, "The Velocity Reaver warning should remain attached to its pursuing body.")
	var speed_before_enrage := reaver.movement_speed
	_enrage_announced = false
	director.event_announced.connect(_capture_enrage_event)
	reaver.take_damage(reaver.maximum_health * 0.51)
	await process_frame
	_expect(reaver.is_apex_enraged() and reaver.movement_speed > speed_before_enrage, "The Velocity Reaver should enter a faster second phase below half health.")
	_expect(_enrage_announced, "Crossing the Apex health threshold should clearly announce the second phase.")
	await _destroy_scene(scene)


func _validate_rift_matriarch() -> void:
	var scene := await _create_scene(41001)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var world: Node3D = scene.get_node("World")
	director._spawn_apex(ApexCatalogModel.RIFT_MATRIARCH)
	var matriarch: EnemyAgent = director._apex
	runner.velocity = Vector3(0.0, 0.0, 72.0)
	matriarch.global_position = runner.global_position + Vector3.RIGHT * 82.0
	matriarch.global_position.y = world.get_surface_height(matriarch.global_position.x, matriarch.global_position.z) + matriarch.body_radius
	_attack_kind = &""
	matriarch.attack_telegraphed.connect(func(_enemy: EnemyAgent, kind: StringName) -> void: _attack_kind = kind)
	matriarch._special_cooldown = 0.0
	await physics_frame
	await physics_frame
	_expect(_attack_kind == &"apex_rift", "The Rift Matriarch should open by marking the runner's projected route rather than charging directly.")
	_expect(matriarch._telegraph_mesh.top_level and matriarch._attack_center.distance_to(matriarch.global_position) > 35.0, "The Matriarch's rift warning should remain on remote world space and visibly separate from the boss.")

	matriarch._attack_state = EnemyAgent.AttackState.CHASE
	matriarch._special_sequence = 2
	matriarch._special_cooldown = 0.0
	var enemies_before := director.get_enemy_count()
	matriarch._begin_special(Vector3.LEFT)
	_expect(matriarch._attack_kind == &"apex_bloom", "Every third Matriarch special should seed a brood instead of repeating the same damage zone.")
	matriarch._update_telegraph(2.0)
	await process_frame
	var rift_spawn_count := 0
	for enemy in director._enemies:
		if is_instance_valid(enemy) and enemy.archetype == &"rift_spawn":
			rift_spawn_count += 1
			_expect(enemy.experience_value == 0, "Boss broods should not become a farmable experience exploit.")
	_expect(director.get_enemy_count() == enemies_before + 3 and rift_spawn_count == 3, "The first Matriarch brood should create exactly three bounded rift spawn.")
	var cooldown_before_enrage := matriarch._special_cooldown
	matriarch.take_damage(matriarch.maximum_health * 0.51)
	matriarch._begin_recovery()
	_expect(matriarch.is_apex_enraged() and matriarch._special_cooldown < cooldown_before_enrage, "The Matriarch's second phase should shorten the gap between route-denial attacks.")
	_expect(scene.get_node("HUD/ApexLabel").text.begins_with("RIFT MATRIARCH"), "The active boss name should remain readable in the HUD during combat.")
	await _destroy_scene(scene)


func _validate_horizon_warden() -> void:
	var scene := await _create_scene(41002)
	var director: CombatDirector = scene.get_node("CombatDirector")
	var runner: CharacterBody3D = scene.get_node("RunnerBall")
	var world: Node3D = scene.get_node("World")
	director._spawn_apex(ApexCatalogModel.HORIZON_WARDEN)
	var warden: EnemyAgent = director._apex
	runner.velocity = Vector3(0.0, 0.0, 72.0)
	warden.global_position = runner.global_position + Vector3.RIGHT * 76.0
	warden.global_position.y = world.get_surface_height(warden.global_position.x, warden.global_position.z) + warden.body_radius
	_attack_kind = &""
	warden.attack_telegraphed.connect(func(_enemy: EnemyAgent, kind: StringName) -> void: _attack_kind = kind)
	warden._special_cooldown = 0.0
	await physics_frame
	await physics_frame
	_expect(_attack_kind == &"apex_gate", "The Horizon Warden should open with a transverse gate across the projected route.")
	_expect(warden._telegraph_mesh.top_level and warden._attack_center.distance_to(warden.global_position) > 25.0, "Warden gates should remain fixed in remote world space instead of following the boss.")
	var runner_direction := Vector3(runner.velocity.x, 0.0, runner.velocity.z).normalized()
	_expect(absf(warden._charge_direction.dot(runner_direction)) > 0.9, "Warden attack geometry should align to the runner's current travel direction.")
	var gate_extents := warden._get_warden_attack_half_extents()
	_expect(gate_extents.x > gate_extents.y * 5.0, "The gate should read as a broad transverse obstacle rather than another circular blast.")

	var forward := warden._charge_direction.normalized()
	var lateral := Vector3(-forward.z, 0.0, forward.x)
	runner.global_position = warden._attack_center + lateral * (gate_extents.x + 3.0)
	runner._damage_invulnerability_remaining = 0.0
	var integrity_before_safe_resolution: float = runner.integrity
	warden._resolve_pulse()
	_expect(is_equal_approx(runner.integrity, integrity_before_safe_resolution), "Clearing the visible side of a Warden gate should avoid its damage.")
	runner.global_position = warden._attack_center
	runner._damage_invulnerability_remaining = 0.0
	warden._resolve_pulse()
	_expect(runner.integrity < integrity_before_safe_resolution, "Remaining inside a Warden gate should apply attributed damage.")

	warden._attack_state = EnemyAgent.AttackState.CHASE
	warden._special_sequence = 1
	warden._special_cooldown = 0.0
	warden._begin_special(Vector3.LEFT)
	_expect(warden._attack_kind == &"apex_lane", "The Warden should alternate its transverse gate with a longitudinal lane cut.")
	var lane_extents := warden._get_warden_attack_half_extents()
	_expect(lane_extents.y > lane_extents.x * 5.0, "The lane cut should demand a lateral turn instead of reusing gate geometry.")

	warden._begin_recovery()
	var cooldown_before_enrage := warden._special_cooldown
	_enrage_announced = false
	director.event_announced.connect(_capture_enrage_event)
	warden.take_damage(warden.maximum_health * 0.51)
	warden._begin_recovery()
	await process_frame
	_expect(warden.is_apex_enraged() and warden._special_cooldown < cooldown_before_enrage, "The Warden's second phase should widen its geometry and shorten its attack cycle.")
	_expect(_enrage_announced, "The Warden's converging second phase should be announced clearly.")
	_expect(scene.get_node("HUD/ApexLabel").text.begins_with("HORIZON WARDEN"), "The Horizon Warden identity should remain readable in the HUD during combat.")
	await _destroy_scene(scene)


func _create_scene(world_seed: int) -> Node:
	var scene: Node = load("res://main.tscn").instantiate()
	scene.set_meta("overrush_disable_persistence", true)
	scene.get_node("World").seed = world_seed
	root.add_child(scene)
	await process_frame
	await process_frame
	var director: CombatDirector = scene.get_node("CombatDirector")
	director.stop_run()
	director._run_active = true
	return scene


func _destroy_scene(scene: Node) -> void:
	paused = false
	scene.queue_free()
	await process_frame


func _capture_enrage_event(title: String, _subtitle: String) -> void:
	if "UNBOUND" in title or "FRACTURES" in title or "CONVERGES" in title:
		_enrage_announced = true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
