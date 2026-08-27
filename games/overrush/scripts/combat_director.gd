class_name CombatDirector
extends Node3D

signal build_changed(build: RunBuild)
signal level_up_requested(options: Array[StringName])

const EnemyAgentScript = preload("res://scripts/enemy_agent.gd")
const ArcProjectileScript = preload("res://scripts/arc_projectile.gd")
const ExperiencePickupScript = preload("res://scripts/experience_pickup.gd")
const RunBuildScript = preload("res://scripts/run_build.gd")

const INITIAL_SPAWN_DELAY := 1.25
const MINIMUM_SPAWN_INTERVAL := 0.24
const MAXIMUM_ENEMIES := 96
const TARGETING_RANGE := 105.0
const SPAWN_DISTANCE_MIN := 52.0
const SPAWN_DISTANCE_MAX := 94.0
const WAKE_TICK_INTERVAL := 0.22

@export var runner_path: NodePath
@export var world_path: NodePath

var build: RunBuild = RunBuildScript.new()
var elapsed_time := 0.0
var enemies_defeated := 0

var _runner: CharacterBody3D
var _world: Node3D
var _rng := RandomNumberGenerator.new()
var _enemies: Array[EnemyAgent] = []
var _spawn_timer := INITIAL_SPAWN_DELAY
var _fire_timer := 0.4
var _wake_timer := 0.0
var _awaiting_upgrade := false
var _run_active := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runner = get_node(runner_path)
	_world = get_node(world_path)
	_rng.seed = int(_world.generated_seed) ^ 0x4F564552
	_runner.dash_state_changed.connect(_on_dash_state_changed)
	build_changed.emit(build)


func _physics_process(delta: float) -> void:
	if not _run_active or get_tree().paused:
		return
	elapsed_time += delta
	_cleanup_enemies()
	_update_spawning(delta)
	_update_arc_weapon(delta)
	_update_slipstream(delta)


func choose_upgrade(option_index: int) -> void:
	if not _awaiting_upgrade:
		return
	var options := build.get_meta("current_options", []) as Array
	if option_index < 0 or option_index >= options.size():
		return
	var result := build.apply_upgrade(StringName(options[option_index]))
	if result.is_empty():
		return
	if float(result.maximum_integrity) > 0.0:
		_runner.increase_maximum_integrity(float(result.maximum_integrity), float(result.repair))
	build.consume_pending_level()
	build_changed.emit(build)
	if build.pending_levels > 0:
		_offer_level_up()
	else:
		_awaiting_upgrade = false
		build.remove_meta("current_options")
		get_tree().paused = false


func stop_run() -> void:
	_run_active = false


func get_enemy_count() -> int:
	_cleanup_enemies()
	return _enemies.size()


func is_choosing_upgrade() -> bool:
	return _awaiting_upgrade


func get_formatted_time() -> String:
	var total_seconds := floori(elapsed_time)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _update_spawning(delta: float) -> void:
	_spawn_timer -= delta
	var population_limit := mini(MAXIMUM_ENEMIES, 16 + floori(elapsed_time / 8.0))
	if _spawn_timer > 0.0 or _enemies.size() >= population_limit:
		return
	var spawn_interval := maxf(MINIMUM_SPAWN_INTERVAL, 1.05 - elapsed_time * 0.0014)
	_spawn_timer = spawn_interval
	var pack_size := 1 + mini(3, floori(elapsed_time / 150.0))
	for index in range(pack_size):
		if _enemies.size() >= population_limit:
			break
		_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy: EnemyAgent = EnemyAgentScript.new()
	var difficulty := 1.0 + elapsed_time / 210.0
	var archetype := _choose_archetype()
	enemy.configure(_runner, _world, archetype, difficulty)
	enemy.defeated.connect(_on_enemy_defeated)
	add_child(enemy)

	var forward: Vector3 = _runner.heading.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var forward_distance := _rng.randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
	var lateral_distance := _rng.randf_range(-48.0, 48.0)
	var spawn_position: Vector3 = _runner.global_position + forward * forward_distance + side * lateral_distance
	spawn_position.x = clampf(spawn_position.x, -_world.map_size * 0.48, _world.map_size * 0.48)
	spawn_position.z = clampf(spawn_position.z, -_world.map_size * 0.48, _world.map_size * 0.48)
	spawn_position.y = _world.get_surface_height(spawn_position.x, spawn_position.z) + enemy.body_radius
	enemy.global_position = spawn_position
	_enemies.append(enemy)


func _choose_archetype() -> StringName:
	var roll := _rng.randf()
	if elapsed_time > 75.0 and roll < 0.16:
		return &"bulwark"
	if elapsed_time > 20.0 and roll < 0.48:
		return &"skimmer"
	return &"pursuer"


func _update_arc_weapon(delta: float) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	_fire_timer += build.fire_interval
	var targets := _find_targets(build.projectile_count)
	var damage := build.get_arc_damage(_runner.get_horizontal_speed())
	for target in targets:
		var projectile: ArcProjectile = ArcProjectileScript.new()
		add_child(projectile)
		projectile.global_position = _runner.global_position + Vector3.UP * 1.1
		var direction := (target.global_position - projectile.global_position).normalized()
		projectile.configure(target, damage, direction)


func _find_targets(count: int) -> Array[EnemyAgent]:
	var candidates: Array[EnemyAgent] = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(_runner.global_position) <= TARGETING_RANGE:
			candidates.append(enemy)
	candidates.sort_custom(func(a: EnemyAgent, b: EnemyAgent) -> bool:
		return a.global_position.distance_squared_to(_runner.global_position) < b.global_position.distance_squared_to(_runner.global_position)
	)
	if candidates.size() > count:
		candidates.resize(count)
	return candidates


func _update_slipstream(delta: float) -> void:
	if build.slipstream_level <= 0:
		return
	_wake_timer -= delta
	if _wake_timer > 0.0:
		return
	_wake_timer = WAKE_TICK_INTERVAL
	var wake_radius := 8.0 + build.slipstream_level * 2.5
	var wake_position: Vector3 = _runner.global_position - _runner.heading.normalized() * 10.0
	var damage := (4.0 + build.slipstream_level * 2.0) * maxf(1.0, _runner.get_horizontal_speed() / 58.0)
	var hit_anything := false
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(wake_position) <= wake_radius:
			enemy.take_damage(damage)
			hit_anything = true
	if hit_anything:
		_spawn_pulse(wake_position, Color(0.12, 0.9, 1.0, 0.26), wake_radius, 0.22)


func _on_dash_state_changed(active: bool) -> void:
	if not active or build.dash_nova_level <= 0 or not _run_active:
		return
	var radius := 15.0 + build.dash_nova_level * 4.0
	var damage := 24.0 + build.dash_nova_level * 14.0
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(_runner.global_position) <= radius:
			enemy.take_damage(damage)
	_spawn_pulse(_runner.global_position, Color(0.05, 0.82, 1.0, 0.42), radius, 0.32)


func _on_enemy_defeated(enemy: EnemyAgent, experience_value: int) -> void:
	enemies_defeated += 1
	_enemies.erase(enemy)
	var pickup: ExperiencePickup = ExperiencePickupScript.new()
	add_child(pickup)
	pickup.global_position = enemy.global_position + Vector3.UP * 1.2
	pickup.configure(_runner, experience_value, 38.0)
	pickup.collected.connect(_on_experience_collected)


func _on_experience_collected(value: int) -> void:
	build.add_experience(value)
	build_changed.emit(build)
	if build.pending_levels > 0 and not _awaiting_upgrade:
		_offer_level_up()


func _offer_level_up() -> void:
	_awaiting_upgrade = true
	var options := build.get_upgrade_options(_rng)
	build.set_meta("current_options", options)
	get_tree().paused = true
	level_up_requested.emit(options)


func _spawn_pulse(position: Vector3, color: Color, radius: float, duration: float) -> void:
	var pulse := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.08
	disc.radial_segments = 48
	pulse.mesh = disc
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 3.0
	pulse.material_override = material
	add_child(pulse)
	pulse.global_position = position + Vector3.UP * 0.15
	pulse.scale = Vector3(0.1, 1.0, 0.1)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "transparency", 1.0, duration)
	tween.set_parallel(false)
	tween.tween_callback(pulse.queue_free)


func _cleanup_enemies() -> void:
	var living: Array[EnemyAgent] = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			living.append(enemy)
	_enemies = living
