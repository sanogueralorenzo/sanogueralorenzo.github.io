class_name CombatDirector
extends Node3D

signal build_changed(build: RunBuild)
signal level_up_requested(options: Array[StringName])
signal phase_changed(phase_id: StringName, phase_name: String)
signal event_announced(title: String, subtitle: String)
signal apex_health_changed(current: float, maximum: float)
signal run_victory
signal run_failed(reason: String)

const EnemyAgentScript = preload("res://scripts/enemy_agent.gd")
const ArcProjectileScript = preload("res://scripts/arc_projectile.gd")
const ExperiencePickupScript = preload("res://scripts/experience_pickup.gd")
const SlipstreamWakeScript = preload("res://scripts/slipstream_wake.gd")
const RunBuildScript = preload("res://scripts/run_build.gd")
const RunPacingModel = preload("res://scripts/run_pacing.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")

const INITIAL_SPAWN_DELAY := 1.25
const MINIMUM_SPAWN_INTERVAL := 0.24
const MAXIMUM_ENEMIES := 96
const TARGETING_RANGE := 105.0
const SPAWN_DISTANCE_MIN := 52.0
const SPAWN_DISTANCE_MAX := 94.0
const WAKE_DROP_INTERVAL := 0.2

@export var runner_path: NodePath
@export var world_path: NodePath

var build: RunBuild = RunBuildScript.new()
var pacing: RunPacing = RunPacingModel.new()
var elapsed_time := 0.0
var enemies_defeated := 0
var selected_protocol: StringName = RunProtocolCatalog.STANDARD

var _runner: CharacterBody3D
var _world: Node3D
var _rng := RandomNumberGenerator.new()
var _enemies: Array[EnemyAgent] = []
var _spawn_timer := INITIAL_SPAWN_DELAY
var _fire_timer := 0.4
var _wake_timer := 0.0
var _awaiting_upgrade := false
var _run_active := false
var _run_started := false
var _current_phase := &""
var _apex: EnemyAgent
var _spawn_interval_multiplier := 1.0
var _enemy_health_multiplier := 1.0
var _outgoing_damage_multiplier := 1.0
var _extra_elite_interval := 0.0
var _next_protocol_elite := INF
var _protocol_elite_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runner = get_node(runner_path)
	_world = get_node(world_path)
	_rng.seed = int(_world.generated_seed) ^ 0x4F564552
	_runner.dash_state_changed.connect(_on_dash_state_changed)
	_current_phase = pacing.get_phase_id(0.0)
	build_changed.emit(build)


func _physics_process(delta: float) -> void:
	if not _run_active or get_tree().paused:
		return
	var previous_time := elapsed_time
	elapsed_time += delta
	_update_run_pacing(previous_time)
	if not _run_active:
		return
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


func start_run(protocol_id: StringName) -> void:
	if _run_started:
		return
	selected_protocol = protocol_id if RunProtocolCatalog.is_valid(protocol_id) else RunProtocolCatalog.STANDARD
	var definition := RunProtocolCatalog.get_definition(selected_protocol)
	_spawn_interval_multiplier = float(definition.spawn_interval_multiplier)
	_enemy_health_multiplier = float(definition.enemy_health_multiplier)
	_outgoing_damage_multiplier = float(definition.outgoing_damage_multiplier)
	_extra_elite_interval = float(definition.extra_elite_interval)
	_next_protocol_elite = _extra_elite_interval if _extra_elite_interval > 0.0 else INF
	_runner.apply_integrity_multiplier(float(definition.integrity_multiplier))
	_run_started = true
	_run_active = true
	phase_changed.emit(_current_phase, pacing.get_phase_name(0.0))
	event_announced.emit("BREAKAWAY", "%s engaged" % str(definition.name))


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


func get_phase_name() -> String:
	return pacing.get_phase_name(elapsed_time)


func has_active_apex() -> bool:
	return is_instance_valid(_apex) and not _apex.is_queued_for_deletion()


func _update_spawning(delta: float) -> void:
	_spawn_timer -= delta
	var population_limit := mini(MAXIMUM_ENEMIES, pacing.get_population_limit(elapsed_time))
	if _spawn_timer > 0.0 or _enemies.size() >= population_limit:
		return
	var spawn_interval := maxf(MINIMUM_SPAWN_INTERVAL, pacing.get_spawn_interval(elapsed_time))
	_spawn_timer = maxf(MINIMUM_SPAWN_INTERVAL, spawn_interval * _spawn_interval_multiplier)
	var pack_size := pacing.get_pack_size(elapsed_time)
	for index in range(pack_size):
		if _enemies.size() >= population_limit:
			break
		_spawn_enemy()


func _spawn_enemy(archetype_override: StringName = &"", rank: StringName = &"standard") -> EnemyAgent:
	var enemy: EnemyAgent = EnemyAgentScript.new()
	var difficulty := 1.0 + elapsed_time / 240.0
	var archetype := archetype_override if not archetype_override.is_empty() else _choose_archetype()
	enemy.configure(_runner, _world, archetype, difficulty, rank)
	enemy.apply_health_multiplier(_enemy_health_multiplier)
	enemy.defeated.connect(_on_enemy_defeated)
	if rank == &"apex":
		enemy.health_changed.connect(_on_apex_health_changed)
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
	return enemy


func _choose_archetype() -> StringName:
	var roll := _rng.randf()
	var phase_index := pacing.get_phase_index(elapsed_time)
	if phase_index >= 1 and roll < 0.16 + phase_index * 0.025:
		return &"bulwark"
	if elapsed_time > 20.0 and roll < 0.46 + phase_index * 0.035:
		return &"skimmer"
	return &"pursuer"


func _update_arc_weapon(delta: float) -> void:
	if not build.is_arc_weapon_enabled():
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	_fire_timer += build.fire_interval
	var targets := _find_targets(build.projectile_count)
	var damage := build.get_arc_damage(_runner.get_horizontal_speed()) * _outgoing_damage_multiplier
	for target in targets:
		var projectile: ArcProjectile = ArcProjectileScript.new()
		add_child(projectile)
		projectile.global_position = _runner.global_position + Vector3.UP * 1.1
		var direction := (target.global_position - projectile.global_position).normalized()
		projectile.configure(target, damage, direction, build.arc_chain_count)


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
	_wake_timer = WAKE_DROP_INTERVAL
	var wake_position: Vector3 = _runner.global_position - _runner.heading.normalized() * 10.0
	wake_position.y = _world.get_surface_height(wake_position.x, wake_position.z) + 0.14
	var wake: SlipstreamWake = SlipstreamWakeScript.new()
	add_child(wake)
	wake.global_position = wake_position
	wake.configure(
		build.get_wake_radius(),
		build.get_wake_damage(_runner.get_horizontal_speed()) * _outgoing_damage_multiplier,
		build.get_wake_duration()
	)


func _on_dash_state_changed(active: bool) -> void:
	if build.dash_nova_level <= 0 or not _run_active:
		return
	if active:
		if build.phase_shell_level > 0:
			_runner.grant_damage_immunity(build.get_phase_shell_duration())
		_release_nova(
			_runner.global_position,
			build.get_dash_nova_damage(),
			build.get_dash_nova_radius(),
			Color(0.05, 0.82, 1.0, 0.42)
		)
	elif build.dash_echo_level > 0:
		_release_nova(
			_runner.global_position,
			build.get_dash_echo_damage(),
			build.get_dash_nova_radius() * 0.82,
			Color(0.52, 0.16, 1.0, 0.38)
		)


func _release_nova(position: Vector3, damage: float, radius: float, color: Color) -> void:
	damage *= _outgoing_damage_multiplier
	for enemy in _enemies.duplicate():
		if is_instance_valid(enemy) and enemy.global_position.distance_to(position) <= radius:
			enemy.take_damage(damage)
	_spawn_pulse(position, color, radius, 0.32)


func _on_enemy_defeated(enemy: EnemyAgent, experience_value: int) -> void:
	enemies_defeated += 1
	_enemies.erase(enemy)
	if enemy.is_apex:
		_apex = null
		_run_active = false
		apex_health_changed.emit(0.0, enemy.maximum_health)
		run_victory.emit()
		return
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


func _update_run_pacing(previous_time: float) -> void:
	var phase_id := pacing.get_phase_id(elapsed_time)
	if phase_id != _current_phase:
		_current_phase = phase_id
		var phase_name := pacing.get_phase_name(elapsed_time)
		phase_changed.emit(phase_id, phase_name)
		event_announced.emit(phase_name, _get_phase_subtitle(phase_id))
	for elite_index in pacing.get_crossed_elite_indices(previous_time, elapsed_time):
		_spawn_scheduled_elite(elite_index)
	while elapsed_time >= _next_protocol_elite and _next_protocol_elite < pacing.APEX_TIME:
		_spawn_scheduled_elite(_protocol_elite_index)
		_protocol_elite_index += 1
		_next_protocol_elite += _extra_elite_interval
	if pacing.crossed_apex_time(previous_time, elapsed_time) and not has_active_apex():
		_spawn_apex()
	if pacing.crossed_deadline(previous_time, elapsed_time) and has_active_apex():
		_run_active = false
		run_failed.emit("THE APEX HELD THE STORM")


func _spawn_scheduled_elite(elite_index: int) -> void:
	var elite_archetypes: Array[StringName] = [&"skimmer", &"bulwark", &"pursuer", &"skimmer"]
	var elite := _spawn_enemy(elite_archetypes[elite_index % elite_archetypes.size()], &"elite")
	event_announced.emit("ELITE INTERCEPT", "%s entered the jetstream" % _get_enemy_title(elite.archetype))


func _spawn_apex() -> void:
	_apex = _spawn_enemy(&"apex", &"apex")
	apex_health_changed.emit(_apex.health, _apex.maximum_health)
	event_announced.emit("THE APEX DESCENDS", "Break it before 20:00")


func _on_apex_health_changed(_enemy: EnemyAgent, current: float, maximum: float) -> void:
	apex_health_changed.emit(current, maximum)


func _get_phase_subtitle(phase_id: StringName) -> String:
	match phase_id:
		&"pressure":
			return "Elite signatures are entering the landscape"
		&"redline":
			return "Faster packs. Harder choices. Keep moving."
		&"overrun":
			return "The storm is saturating the route"
		&"apex":
			return "Two minutes to break the hunter"
		_:
			return "Build velocity. Shape the run."


func _get_enemy_title(archetype: StringName) -> String:
	match archetype:
		&"skimmer":
			return "Razor Skimmer"
		&"bulwark":
			return "Ember Bulwark"
		_:
			return "Overrun Pursuer"


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
