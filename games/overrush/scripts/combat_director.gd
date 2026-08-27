class_name CombatDirector
extends Node3D

signal build_changed(build: RunBuild)
signal level_up_requested(options: Array[StringName])
signal upgrade_options_refreshed(options: Array[StringName])
signal phase_changed(phase_id: StringName, phase_name: String)
signal event_announced(title: String, subtitle: String)
signal apex_health_changed(current: float, maximum: float)
signal run_victory
signal run_failed(reason: String)
signal enemy_defeated_feedback(is_elite: bool, is_apex: bool)
signal enemy_hit_feedback(is_apex: bool)
signal experience_collected_feedback(value: int)
signal integrity_collected_feedback(value: float)
signal attack_warning_feedback(attack_kind: StringName, is_elite: bool, is_apex: bool)

const EnemyAgentScript = preload("res://scripts/enemy_agent.gd")
const ArcProjectileScript = preload("res://scripts/arc_projectile.gd")
const ExperiencePickupScript = preload("res://scripts/experience_pickup.gd")
const SlipstreamWakeScript = preload("res://scripts/slipstream_wake.gd")
const RunBuildScript = preload("res://scripts/run_build.gd")
const RunStatsScript = preload("res://scripts/run_stats.gd")
const RunPacingModel = preload("res://scripts/run_pacing.gd")
const RunProtocolCatalog = preload("res://scripts/run_protocols.gd")
const ApexCatalogModel = preload("res://scripts/apex_catalog.gd")

const INITIAL_SPAWN_DELAY := 1.25
const MINIMUM_SPAWN_INTERVAL := 0.24
const MAXIMUM_ENEMIES := 96
const TARGETING_RANGE := 105.0
const SPAWN_DISTANCE_MIN := 52.0
const SPAWN_DISTANCE_MAX := 94.0
const INITIAL_REROLLS := 3
const INITIAL_BANISHES := 1
const RECOVERY_DROP_STRIDE := 18
const STANDARD_RECOVERY_VALUE := 14
const ELITE_RECOVERY_VALUE := 30
const MAX_ACTIVE_RECOVERY_PICKUPS := 3

@export var runner_path: NodePath
@export var world_path: NodePath

var build: RunBuild = RunBuildScript.new()
var run_stats: OverrushRunStats = RunStatsScript.new()
var pacing: RunPacing = RunPacingModel.new()
var elapsed_time := 0.0
var enemies_defeated := 0
var selected_protocol: StringName = RunProtocolCatalog.STANDARD
var rerolls_remaining := INITIAL_REROLLS
var banishes_remaining := INITIAL_BANISHES

var _runner: CharacterBody3D
var _world: Node3D
var _rng := RandomNumberGenerator.new()
var _enemies: Array[EnemyAgent] = []
var _spawn_timer := INITIAL_SPAWN_DELAY
var _fire_timer := 0.4
var _wake_timer := 0.0
var _arsenal_timer := 0.0
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
var _reduced_motion := false
var _high_contrast_telegraphs := false
var _dash_hit_ids: Dictionary = {}
var _wake_drop_count := 0
var _pending_evolution_announcement := ""
var _pending_catalyst_announcement := ""
var _pending_arsenal_announcement := ""
var _catalyst_dash_window := 0.0
var _dash_nova_recharge := 0.0
var _introduced_archetypes: Dictionary = {}
var _rewarding_defeats_since_recovery := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runner = get_node(runner_path)
	_world = get_node(world_path)
	_rng.seed = int(_world.generated_seed) ^ 0x4F564552
	_runner.dash_state_changed.connect(_on_dash_state_changed)
	_runner.damaged.connect(_on_runner_damaged)
	_current_phase = pacing.get_phase_id(0.0)
	build_changed.emit(build)


func _physics_process(delta: float) -> void:
	if not _run_active or get_tree().paused:
		return
	var previous_time := elapsed_time
	elapsed_time += delta
	_catalyst_dash_window = maxf(0.0, _catalyst_dash_window - delta)
	_dash_nova_recharge = maxf(0.0, _dash_nova_recharge - delta)
	run_stats.record_traversal(_runner.global_position, _runner.get_horizontal_speed())
	if not build.catalyst_id.is_empty():
		run_stats.record_catalyst_state(delta, build.get_catalyst_damage_multiplier(
			_runner.get_horizontal_speed(),
			_runner.is_airborne_attack_window(),
			_catalyst_dash_window > 0.0
		) > 1.0)
	_update_run_pacing(previous_time)
	if not _run_active:
		return
	_cleanup_enemies()
	_update_spawning(delta)
	_update_arc_weapon(delta)
	_update_slipstream(delta)
	_update_arsenal(delta)
	_update_ramjet()


func choose_upgrade(option_index: int) -> void:
	if not _run_active or not _awaiting_upgrade:
		return
	var options := build.get_meta("current_options", []) as Array
	if option_index < 0 or option_index >= options.size():
		return
	var chosen_upgrade := StringName(options[option_index])
	var choosing_engine := build.core_path.is_empty()
	var choosing_evolution := build.is_evolution_upgrade(chosen_upgrade)
	var choosing_catalyst := build.is_catalyst_upgrade(chosen_upgrade)
	var choosing_arsenal := build.is_arsenal_upgrade(chosen_upgrade)
	var result := build.apply_upgrade(chosen_upgrade)
	if result.is_empty():
		return
	if choosing_evolution:
		_pending_evolution_announcement = build.get_upgrade_name(chosen_upgrade)
	if choosing_catalyst:
		_pending_catalyst_announcement = build.get_upgrade_name(chosen_upgrade)
	if choosing_arsenal:
		_pending_arsenal_announcement = build.get_upgrade_name(chosen_upgrade)
	var milestone_kind := &"standard"
	if choosing_engine:
		milestone_kind = &"engine"
	elif choosing_evolution:
		milestone_kind = &"evolution"
	elif choosing_arsenal:
		milestone_kind = &"arsenal"
	elif choosing_catalyst:
		milestone_kind = &"catalyst"
	run_stats.record_upgrade(chosen_upgrade, elapsed_time, build.level, milestone_kind)
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
		if not _pending_evolution_announcement.is_empty():
			event_announced.emit(
				"%s ONLINE" % _pending_evolution_announcement,
				"Exclusive evolution locked for this run"
			)
			_pending_evolution_announcement = ""
		if not _pending_catalyst_announcement.is_empty():
			event_announced.emit(
				"%s TUNED" % _pending_catalyst_announcement,
				"Your damage now follows this movement rhythm"
			)
			_pending_catalyst_announcement = ""
		if not _pending_arsenal_announcement.is_empty():
			event_announced.emit("%s ONLINE" % _pending_arsenal_announcement, "Secondary weapon locked for this run")
			_pending_arsenal_announcement = ""


func reroll_upgrade_options() -> bool:
	if not _run_active or not _awaiting_upgrade or rerolls_remaining <= 0:
		return false
	var current_options := _get_current_upgrade_options()
	if not build.has_alternative_upgrade_options(current_options):
		return false
	var options := build.get_upgrade_options(_rng, current_options, _get_available_fork_stage())
	if _same_option_set(options, current_options):
		return false
	rerolls_remaining -= 1
	run_stats.record_reroll()
	_set_current_upgrade_options(options)
	upgrade_options_refreshed.emit(options)
	return true


func banish_upgrade_option(option_index: int) -> bool:
	if not _run_active or not _awaiting_upgrade or banishes_remaining <= 0:
		return false
	var current_options := _get_current_upgrade_options()
	if option_index < 0 or option_index >= current_options.size():
		return false
	if not build.banish_upgrade(current_options[option_index]):
		return false
	banishes_remaining -= 1
	run_stats.record_banish()
	var options := build.get_upgrade_options(_rng, current_options, _get_available_fork_stage())
	_set_current_upgrade_options(options)
	upgrade_options_refreshed.emit(options)
	return true


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
	rerolls_remaining = INITIAL_REROLLS
	banishes_remaining = INITIAL_BANISHES
	_catalyst_dash_window = 0.0
	_dash_nova_recharge = 0.0
	_arsenal_timer = 0.0
	_rewarding_defeats_since_recovery = 0
	run_stats.reset(_runner.global_position)
	run_stats.set_phase(_current_phase)
	_run_started = true
	_run_active = true
	phase_changed.emit(_current_phase, pacing.get_phase_name(0.0))
	event_announced.emit("BREAKAWAY", "%s engaged" % str(definition.name))


func stop_run() -> void:
	_run_active = false
	_awaiting_upgrade = false
	build.remove_meta("current_options")


func set_accessibility(reduced_motion: bool, high_contrast_telegraphs: bool) -> void:
	_reduced_motion = reduced_motion
	_high_contrast_telegraphs = high_contrast_telegraphs
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.apply_accessibility(_reduced_motion, _high_contrast_telegraphs)


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


func get_apex_archetype_for_run() -> StringName:
	return ApexCatalogModel.get_for_seed(int(_world.generated_seed))


func get_active_apex_title() -> String:
	if not has_active_apex():
		return "THE APEX"
	return ApexCatalogModel.get_title(_apex.archetype)


func get_catalyst_status() -> String:
	if build.catalyst_id.is_empty():
		return ""
	var multiplier := build.get_catalyst_damage_multiplier(
		_runner.get_horizontal_speed(),
		_runner.is_airborne_attack_window(),
		_catalyst_dash_window > 0.0
	)
	return "%s  •  OUTPUT %d%%" % [build.get_catalyst_name(), roundi(multiplier * 100.0)]


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
	enemy.apply_accessibility(_reduced_motion, _high_contrast_telegraphs)
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.damaged.connect(_on_enemy_damaged)
	enemy.health_changed.connect(_on_enemy_health_changed)
	enemy.attack_telegraphed.connect(_on_enemy_attack_telegraphed)
	enemy.reinforcements_requested.connect(_on_reinforcements_requested)
	if rank == &"apex":
		enemy.health_changed.connect(_on_apex_health_changed)
		enemy.apex_enraged.connect(_on_apex_enraged)
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
	_announce_archetype_once(archetype)
	return enemy


func _choose_archetype() -> StringName:
	var phase_index := pacing.get_phase_index(elapsed_time)
	var roster := _get_roster_weights(phase_index, elapsed_time)
	var roll := _rng.randf()
	var cumulative := 0.0
	for entry in roster:
		cumulative += float(entry[1])
		if roll <= cumulative:
			return StringName(entry[0])
	return &"pursuer"


func _get_roster_weights(phase_index: int, run_time: float) -> Array:
	if phase_index <= 0:
		return [[&"pursuer", 1.0]] if run_time <= 20.0 else [
			[&"pursuer", 0.7],
			[&"skimmer", 0.3],
		]
	if phase_index == 1:
		return [
			[&"pursuer", 0.45],
			[&"skimmer", 0.25],
			[&"bulwark", 0.18],
			[&"rift_weaver", 0.12],
		]
	if phase_index == 2:
		return [
			[&"pursuer", 0.31],
			[&"skimmer", 0.25],
			[&"bulwark", 0.19],
			[&"rift_weaver", 0.16],
			[&"swarm_foundry", 0.09],
		]
	return [
		[&"pursuer", 0.24],
		[&"skimmer", 0.24],
		[&"bulwark", 0.20],
		[&"rift_weaver", 0.18],
		[&"swarm_foundry", 0.14],
	]


func _update_arc_weapon(delta: float) -> void:
	if not build.is_arc_weapon_enabled():
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	if build.is_storm_lance():
		_fire_timer += build.get_lance_interval()
		if _fire_storm_lance() == 0:
			_fire_arc_bolts(1)
		return
	if build.is_arc_orbit():
		_fire_timer += build.get_orbit_interval()
		_release_nova(
			_runner.global_position,
			build.get_orbit_damage(_runner.get_horizontal_speed()),
			build.get_orbit_radius(),
			Color(0.1, 0.9, 1.0, 0.34),
			&"arc_orbit"
		)
		return
	_fire_timer += build.fire_interval
	_fire_arc_bolts(build.projectile_count)


func _fire_arc_bolts(target_count: int) -> void:
	var targets := _find_targets(target_count)
	var damage := build.get_arc_damage(_runner.get_horizontal_speed()) * _get_outgoing_damage_multiplier()
	for target in targets:
		var projectile: ArcProjectile = ArcProjectileScript.new()
		add_child(projectile)
		projectile.global_position = _runner.global_position + Vector3.UP * 1.1
		var direction := (target.global_position - projectile.global_position).normalized()
		projectile.configure(target, damage, direction, build.arc_chain_count, &"arc_bolt")


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
	_wake_timer = build.get_wake_drop_interval()
	_wake_drop_count += 1
	var heading: Vector3 = _runner.heading.normalized()
	var wake_position: Vector3 = _runner.global_position - heading * 10.0
	var radius := build.get_wake_radius()
	var damage := build.get_wake_damage(_runner.get_horizontal_speed()) * _get_outgoing_damage_multiplier()
	var duration := build.get_wake_duration()
	if build.is_twin_current():
		var side := Vector3(-heading.z, 0.0, heading.x) * build.get_twin_current_offset()
		var twin_damage := damage * build.get_twin_current_damage_multiplier()
		_spawn_wake(wake_position + side, radius, twin_damage, duration, 0.0, &"twin_current")
		_spawn_wake(wake_position - side, radius, twin_damage, duration, 0.0, &"twin_current")
		return
	if build.is_tempest_anchor() and _wake_drop_count % build.get_anchor_stride() == 0:
		_spawn_wake(
			wake_position,
			radius * build.get_anchor_radius_multiplier(),
			damage * build.get_anchor_damage_multiplier(),
			duration * build.get_anchor_duration_multiplier(),
			build.get_anchor_repeat_interval(),
			&"tempest_anchor"
		)
		return
	_spawn_wake(wake_position, radius, damage, duration, 0.0, &"stormtrail")


func _update_arsenal(delta: float) -> void:
	if build.arsenal_id.is_empty() or build.arsenal_id == RunBuild.BACKDRAFT_MINE:
		return
	_arsenal_timer -= delta
	if _arsenal_timer > 0.0:
		return
	if build.arsenal_id == RunBuild.HUNTER_ARRAY:
		_arsenal_timer = build.get_hunter_interval()
		for target in _find_targets(build.get_hunter_count()):
			var projectile: ArcProjectile = ArcProjectileScript.new()
			add_child(projectile)
			projectile.global_position = _runner.global_position + Vector3.UP * 1.4
			projectile.configure(target, build.get_hunter_damage() * _get_outgoing_damage_multiplier(), (_runner.heading + Vector3.UP * 0.15).normalized(), 0, &"hunter_array")
	elif build.arsenal_id == RunBuild.DRIFT_BLADES:
		_arsenal_timer = build.get_drift_interval()
		_release_nova(_runner.global_position, build.get_drift_damage(), build.get_drift_radius(), Color(0.85, 0.28, 1.0, 0.32), &"drift_blades")


func _on_dash_state_changed(active: bool) -> void:
	if not _run_active:
		return
	_catalyst_dash_window = RunBuild.PULSE_WINDOW_SECONDS
	if active:
		run_stats.record_dash()
		_dash_hit_ids.clear()
		if build.phase_shell_level > 0:
			_runner.grant_damage_immunity(build.get_phase_shell_duration())
		if build.dash_nova_level > 0 and _dash_nova_recharge <= 0.0:
			_dash_nova_recharge = RunBuild.DASH_NOVA_RECHARGE_SECONDS
			_release_nova(
				_runner.global_position,
				build.get_dash_nova_damage(),
				build.get_dash_nova_radius(),
				Color(0.05, 0.82, 1.0, 0.42),
				&"dash_nova"
			)
	else:
		if build.dash_echo_level > 0:
			_release_nova(
				_runner.global_position,
				build.get_dash_echo_damage(),
				build.get_dash_nova_radius() * 0.82,
				Color(0.52, 0.16, 1.0, 0.38),
				&"dash_echo"
			)
		if build.is_gravity_knot():
			_release_gravity_knot(_runner.global_position)
		if build.arsenal_id == RunBuild.BACKDRAFT_MINE:
			_drop_backdraft_mine(_runner.global_position)


func _drop_backdraft_mine(center: Vector3) -> void:
	var radius := build.get_backdraft_radius()
	var damage := build.get_backdraft_damage()
	_spawn_pulse(center, Color(1.0, 0.36, 0.08, 0.24), radius, 0.42)
	get_tree().create_timer(0.42, false).timeout.connect(func() -> void:
		if is_inside_tree() and _run_active:
			_release_nova(center, damage, radius, Color(1.0, 0.22, 0.04, 0.46), &"backdraft_mine")
	)


func _update_ramjet() -> void:
	if not _run_active or not _runner.is_dashing() or not build.is_ramjet():
		return
	var hit_count := 0
	for enemy in _enemies.duplicate():
		if not is_instance_valid(enemy) or _dash_hit_ids.has(enemy.get_instance_id()):
			continue
		var planar_distance := Vector2(
			enemy.global_position.x - _runner.global_position.x,
			enemy.global_position.z - _runner.global_position.z
		).length()
		if planar_distance > build.get_ramjet_radius() + enemy.body_radius:
			continue
		_dash_hit_ids[enemy.get_instance_id()] = true
		enemy.take_damage(build.get_ramjet_damage(_runner.get_horizontal_speed()) * _get_outgoing_damage_multiplier(), &"ramjet")
		hit_count += 1
	if hit_count > 0:
		_spawn_pulse(_runner.global_position, Color(1.0, 0.42, 0.05, 0.42), build.get_ramjet_radius() * 1.6, 0.12)


func _release_gravity_knot(center: Vector3) -> void:
	var radius := build.get_gravity_knot_radius()
	var damage := build.get_gravity_knot_damage()
	var pull_ratio := build.get_gravity_knot_pull_ratio()
	for enemy in _enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		var planar_offset := Vector3(center.x - enemy.global_position.x, 0.0, center.z - enemy.global_position.z)
		if planar_offset.length() > radius:
			continue
		enemy.global_position += planar_offset * pull_ratio
		enemy.global_position.y = _world.get_surface_height(enemy.global_position.x, enemy.global_position.z) + enemy.body_radius * 0.72
	_spawn_pulse(center, Color(0.62, 0.16, 1.0, 0.42), radius, 0.28)
	get_tree().create_timer(0.28, false).timeout.connect(func() -> void:
		if is_inside_tree() and _run_active:
			_release_nova(center, damage, radius * 0.62, Color(0.9, 0.28, 1.0, 0.48), &"gravity_knot")
	)


func _spawn_wake(
	position: Vector3,
	radius: float,
	damage: float,
	duration: float,
	repeat_interval: float = 0.0,
	source_id: StringName = &"stormtrail"
) -> void:
	position.y = _world.get_surface_height(position.x, position.z) + 0.14
	var wake: SlipstreamWake = SlipstreamWakeScript.new()
	add_child(wake)
	wake.global_position = position
	wake.configure(radius, damage, duration, repeat_interval, source_id)


func _fire_storm_lance() -> int:
	var heading: Vector3 = _runner.heading.normalized()
	var lance_range := build.get_lance_range()
	var lance_width := build.get_lance_width()
	var targets: Array[EnemyAgent] = []
	for enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		var offset := enemy.global_position - _runner.global_position
		offset.y = 0.0
		var forward_distance := offset.dot(heading)
		var lateral_distance := (offset - heading * forward_distance).length()
		if forward_distance > 0.0 and forward_distance <= lance_range and lateral_distance <= lance_width + enemy.body_radius:
			targets.append(enemy)
	targets.sort_custom(func(a: EnemyAgent, b: EnemyAgent) -> bool:
		return (a.global_position - _runner.global_position).dot(heading) < (b.global_position - _runner.global_position).dot(heading)
	)
	if targets.size() > build.get_lance_target_limit():
		targets.resize(build.get_lance_target_limit())
	var damage := build.get_lance_damage(_runner.get_horizontal_speed()) * _get_outgoing_damage_multiplier()
	for target in targets:
		target.take_damage(damage, &"storm_lance")
	_spawn_lance_visual(_runner.global_position, heading, lance_range, lance_width)
	return targets.size()


func _spawn_lance_visual(origin: Vector3, heading: Vector3, lance_range: float, lance_width: float) -> void:
	var lance := MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(lance_width * 2.0, 0.22, lance_range)
	lance.mesh = beam
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.94, 1.0, 0.34)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.72, 1.0)
	material.emission_energy_multiplier = 4.5
	lance.material_override = material
	add_child(lance)
	lance.global_position = origin + heading * lance_range * 0.5 + Vector3.UP * 0.45
	lance.look_at(lance.global_position + heading, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(lance, "transparency", 1.0, 0.16)
	tween.tween_callback(lance.queue_free)


func _release_nova(position: Vector3, damage: float, radius: float, color: Color, source_id: StringName) -> void:
	damage *= _get_outgoing_damage_multiplier()
	for enemy in _enemies.duplicate():
		if is_instance_valid(enemy) and enemy.global_position.distance_to(position) <= radius:
			enemy.take_damage(damage, source_id)
	_spawn_pulse(position, color, radius, 0.32)


func _get_outgoing_damage_multiplier() -> float:
	return _outgoing_damage_multiplier * build.get_catalyst_damage_multiplier(
		_runner.get_horizontal_speed(),
		_runner.is_airborne_attack_window(),
		_catalyst_dash_window > 0.0
	)


func _on_enemy_defeated(enemy: EnemyAgent, experience_value: int) -> void:
	enemies_defeated += 1
	run_stats.record_defeat(enemy.archetype, enemy.is_elite)
	_enemies.erase(enemy)
	enemy_defeated_feedback.emit(enemy.is_elite, enemy.is_apex)
	if enemy.is_apex:
		_apex = null
		stop_run()
		apex_health_changed.emit(0.0, enemy.maximum_health)
		run_victory.emit()
		return
	if experience_value <= 0:
		return
	_rewarding_defeats_since_recovery += 1
	var cadence_recovery_due := _rewarding_defeats_since_recovery >= RECOVERY_DROP_STRIDE
	var should_drop_recovery := enemy.is_elite or cadence_recovery_due
	if should_drop_recovery and _count_active_recovery_pickups() < MAX_ACTIVE_RECOVERY_PICKUPS:
		var recovery_value := ELITE_RECOVERY_VALUE if enemy.is_elite else STANDARD_RECOVERY_VALUE
		_spawn_pickup(enemy.global_position + Vector3.RIGHT * 3.0, recovery_value, ExperiencePickup.INTEGRITY)
		if cadence_recovery_due:
			_rewarding_defeats_since_recovery = 0
	_spawn_pickup(enemy.global_position, experience_value, ExperiencePickup.EXPERIENCE)


func _spawn_pickup(position: Vector3, value: int, pickup_kind: StringName) -> void:
	var pickup: ExperiencePickup = ExperiencePickupScript.new()
	add_child(pickup)
	pickup.global_position = position + Vector3.UP * 1.2
	pickup.configure(_runner, value, 38.0, pickup_kind)
	if pickup_kind == ExperiencePickup.INTEGRITY:
		pickup.integrity_collected.connect(_on_integrity_collected)
	else:
		pickup.collected.connect(_on_experience_collected)


func _count_active_recovery_pickups() -> int:
	var count := 0
	for child in get_children():
		if child is ExperiencePickup and child.is_integrity_pickup() and not child.is_queued_for_deletion():
			count += 1
	return count


func _on_experience_collected(value: int) -> void:
	if not _run_active:
		return
	experience_collected_feedback.emit(value)
	build.add_experience(value)
	build_changed.emit(build)
	if build.pending_levels > 0 and not _awaiting_upgrade:
		_offer_level_up()


func _on_integrity_collected(value: float) -> void:
	if not _run_active:
		return
	var applied: float = _runner.repair_integrity(value)
	if applied <= 0.0:
		return
	run_stats.record_integrity_recovery(applied)
	integrity_collected_feedback.emit(applied)
	_spawn_pulse(_runner.global_position, Color(1.0, 0.16, 0.42, 0.42), 8.0, 0.24)


func _on_enemy_attack_telegraphed(enemy: EnemyAgent, attack_kind: StringName) -> void:
	attack_warning_feedback.emit(attack_kind, enemy.is_elite, enemy.is_apex)


func _on_enemy_damaged(_enemy: EnemyAgent, amount: float, source_id: StringName) -> void:
	run_stats.record_damage(source_id, amount)


func _on_runner_damaged(amount: float, _source_direction: Vector3, _integrity_ratio: float, source_id: StringName) -> void:
	run_stats.record_damage_taken(amount, source_id)


func _on_reinforcements_requested(source: EnemyAgent, count: int) -> void:
	if not _run_active or not is_instance_valid(source):
		return
	var available_slots := maxi(0, MAXIMUM_ENEMIES - _enemies.size())
	var spawn_count := mini(maxi(count, 0), available_slots)
	var reinforcement_archetype := &"rift_spawn" if source.archetype == ApexCatalogModel.RIFT_MATRIARCH else &"drone"
	for index in range(spawn_count):
		var drone := _spawn_enemy(reinforcement_archetype)
		var angle := TAU * float(index) / float(maxi(spawn_count, 1)) + float(source.get_instance_id() % 17) * 0.21
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * (source.body_radius + drone.body_radius + 2.4)
		drone.global_position = source.global_position + offset
		drone.global_position.y = _world.get_surface_height(drone.global_position.x, drone.global_position.z) + drone.body_radius * 0.72


func _on_enemy_health_changed(enemy: EnemyAgent, _current: float, _maximum: float) -> void:
	enemy_hit_feedback.emit(enemy.is_apex)


func _offer_level_up() -> void:
	if not _run_active:
		return
	_awaiting_upgrade = true
	var options := build.get_upgrade_options(_rng, [], _get_available_fork_stage())
	_set_current_upgrade_options(options)
	get_tree().paused = true
	level_up_requested.emit(options)


func _get_available_fork_stage() -> int:
	if pacing.is_build_milestone_available(&"catalyst", elapsed_time):
		return RunBuild.FORK_STAGE_CATALYST
	if pacing.is_build_milestone_available(&"arsenal", elapsed_time):
		return RunBuild.FORK_STAGE_ARSENAL
	if pacing.is_build_milestone_available(&"evolution", elapsed_time):
		return RunBuild.FORK_STAGE_EVOLUTION
	return RunBuild.FORK_STAGE_STANDARD


func _set_current_upgrade_options(options: Array[StringName]) -> void:
	build.set_meta("current_options", options)


func _get_current_upgrade_options() -> Array[StringName]:
	var options: Array[StringName] = []
	for upgrade_id in build.get_meta("current_options", []):
		options.append(StringName(upgrade_id))
	return options


func _same_option_set(first: Array[StringName], second: Array[StringName]) -> bool:
	if first.size() != second.size():
		return false
	for upgrade_id in first:
		if upgrade_id not in second:
			return false
	return true


func _update_run_pacing(previous_time: float) -> void:
	var phase_id := pacing.get_phase_id(elapsed_time)
	if phase_id != _current_phase:
		_current_phase = phase_id
		run_stats.set_phase(phase_id)
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
		stop_run()
		run_failed.emit("%s HELD THE STORM" % get_active_apex_title())


func _spawn_scheduled_elite(elite_index: int) -> void:
	var elite_archetypes: Array[StringName] = [&"skimmer", &"bulwark", &"rift_weaver", &"swarm_foundry"]
	var elite := _spawn_enemy(elite_archetypes[elite_index % elite_archetypes.size()], &"elite")
	event_announced.emit("ELITE INTERCEPT", "%s entered the jetstream" % _get_enemy_title(elite.archetype))


func _spawn_apex(apex_override: StringName = &"") -> void:
	var apex_id := apex_override if ApexCatalogModel.is_valid(apex_override) else get_apex_archetype_for_run()
	var definition := ApexCatalogModel.get_definition(apex_id)
	_apex = _spawn_enemy(apex_id, &"apex")
	run_stats.set_apex_identity(apex_id)
	apex_health_changed.emit(_apex.health, _apex.maximum_health)
	event_announced.emit(str(definition.title), str(definition.arrival))


func _on_apex_health_changed(_enemy: EnemyAgent, current: float, maximum: float) -> void:
	apex_health_changed.emit(current, maximum)


func _on_apex_enraged(enemy: EnemyAgent) -> void:
	var definition := ApexCatalogModel.get_definition(enemy.archetype)
	event_announced.emit(str(definition.enrage_title), str(definition.enrage_subtitle))


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
		&"rift_weaver":
			return "Rift Weaver"
		&"swarm_foundry":
			return "Swarm Foundry"
		&"drone":
			return "Foundry Drone"
		&"rift_spawn":
			return "Rift Spawn"
		ApexCatalogModel.VELOCITY_REAVER:
			return "Velocity Reaver"
		ApexCatalogModel.RIFT_MATRIARCH:
			return "Rift Matriarch"
		_:
			return "Overrun Pursuer"


func _announce_archetype_once(archetype: StringName) -> void:
	if archetype not in [&"rift_weaver", &"swarm_foundry"] or _introduced_archetypes.has(archetype):
		return
	_introduced_archetypes[archetype] = true
	if archetype == &"rift_weaver":
		event_announced.emit("RIFT WEAVER", "Marked ground detonates — change lanes")
	else:
		event_announced.emit("SWARM FOUNDRY", "Break the source before it multiplies")


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
