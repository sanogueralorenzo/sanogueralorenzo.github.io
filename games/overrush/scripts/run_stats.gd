class_name OverrushRunStats
extends RefCounted

const SOURCE_NAMES := {
	&"arc_bolt": "ARC BOLT",
	&"dash_nova": "DASH NOVA",
	&"dash_echo": "EXIT WOUND",
	&"ramjet": "RAMJET",
	&"gravity_knot": "GRAVITY KNOT",
	&"stormtrail": "STORMTRAIL",
	&"twin_current": "TWIN CURRENT",
	&"tempest_anchor": "TEMPEST ANCHOR",
	&"storm_lance": "STORM LANCE",
	&"arc_orbit": "ARC ORBIT",
	&"unattributed": "OTHER",
}

var damage_by_source: Dictionary = {}
var hits_by_source: Dictionary = {}
var damage_taken := 0.0
var distance_traveled := 0.0
var maximum_speed := 0.0
var dash_count := 0
var rerolls_used := 0
var banishes_used := 0
var catalyst_active_seconds := 0.0
var catalyst_total_seconds := 0.0
var elite_defeats := 0
var defeats_by_archetype: Dictionary = {}
var upgrade_history: Array[StringName] = []
var phase_reached := &"breakaway"
var apex_id := &""

var _last_position := Vector3.ZERO
var _has_position := false


func reset(start_position: Vector3) -> void:
	damage_by_source.clear()
	hits_by_source.clear()
	damage_taken = 0.0
	distance_traveled = 0.0
	maximum_speed = 0.0
	dash_count = 0
	rerolls_used = 0
	banishes_used = 0
	catalyst_active_seconds = 0.0
	catalyst_total_seconds = 0.0
	elite_defeats = 0
	defeats_by_archetype.clear()
	upgrade_history.clear()
	phase_reached = &"breakaway"
	apex_id = &""
	_last_position = start_position
	_has_position = true


func record_damage(source_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	var safe_source := source_id if SOURCE_NAMES.has(source_id) else &"unattributed"
	damage_by_source[safe_source] = float(damage_by_source.get(safe_source, 0.0)) + amount
	hits_by_source[safe_source] = int(hits_by_source.get(safe_source, 0)) + 1


func record_damage_taken(amount: float) -> void:
	damage_taken += maxf(0.0, amount)


func record_traversal(position: Vector3, horizontal_speed: float) -> void:
	maximum_speed = maxf(maximum_speed, maxf(0.0, horizontal_speed))
	if not _has_position:
		_last_position = position
		_has_position = true
		return
	var segment := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
	if segment <= 300.0:
		distance_traveled += segment
	_last_position = position


func record_dash() -> void:
	dash_count += 1


func record_reroll() -> void:
	rerolls_used += 1


func record_banish() -> void:
	banishes_used += 1


func record_catalyst_state(delta: float, active: bool) -> void:
	var safe_delta := maxf(0.0, delta)
	catalyst_total_seconds += safe_delta
	if active:
		catalyst_active_seconds += safe_delta


func record_upgrade(upgrade_id: StringName) -> void:
	upgrade_history.append(upgrade_id)


func record_defeat(archetype: StringName, is_elite: bool) -> void:
	defeats_by_archetype[archetype] = int(defeats_by_archetype.get(archetype, 0)) + 1
	if is_elite:
		elite_defeats += 1


func set_phase(phase_id: StringName) -> void:
	phase_reached = phase_id


func set_apex_identity(new_apex_id: StringName) -> void:
	apex_id = new_apex_id


func get_total_damage() -> float:
	var total := 0.0
	for amount in damage_by_source.values():
		total += float(amount)
	return total


func get_top_damage_sources(limit: int = 3) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var total := get_total_damage()
	for source_id in damage_by_source:
		var amount := float(damage_by_source[source_id])
		sources.append({
			"id": str(source_id),
			"name": str(SOURCE_NAMES.get(source_id, "OTHER")),
			"damage": amount,
			"share": amount / maxf(total, 0.001),
			"hits": int(hits_by_source.get(source_id, 0)),
		})
	sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.damage) > float(b.damage))
	if sources.size() > limit:
		sources.resize(limit)
	return sources


func get_damage_breakdown_text() -> String:
	var parts: Array[String] = []
	for source in get_top_damage_sources():
		parts.append("%s %d%%" % [str(source.name), roundi(float(source.share) * 100.0)])
	return "NO DAMAGE RECORDED" if parts.is_empty() else "  •  ".join(parts)


func snapshot(elapsed_time: float, enemies_defeated: int, build: RunBuild) -> Dictionary:
	var serialized_damage := {}
	for source_id in damage_by_source:
		serialized_damage[str(source_id)] = snappedf(float(damage_by_source[source_id]), 0.1)
	var serialized_hits := {}
	for source_id in hits_by_source:
		serialized_hits[str(source_id)] = int(hits_by_source[source_id])
	var serialized_defeats := {}
	for archetype in defeats_by_archetype:
		serialized_defeats[str(archetype)] = int(defeats_by_archetype[archetype])
	var serialized_upgrades: Array[String] = []
	for upgrade_id in upgrade_history:
		serialized_upgrades.append(str(upgrade_id))
	return {
		"elapsed_seconds": snappedf(maxf(0.0, elapsed_time), 0.1),
		"enemies_defeated": maxi(0, enemies_defeated),
		"elite_defeats": elite_defeats,
		"damage_dealt": snappedf(get_total_damage(), 0.1),
		"damage_taken": snappedf(damage_taken, 0.1),
		"damage_by_source": serialized_damage,
		"hits_by_source": serialized_hits,
		"distance_meters": snappedf(distance_traveled, 0.1),
		"maximum_speed": snappedf(maximum_speed, 0.1),
		"dash_count": dash_count,
		"rerolls_used": rerolls_used,
		"banishes_used": banishes_used,
		"catalyst_id": str(build.catalyst_id),
		"catalyst_uptime": snappedf(catalyst_active_seconds / maxf(catalyst_total_seconds, 0.001), 0.001),
		"phase_reached": str(phase_reached),
		"apex_id": str(apex_id),
		"build_name": build.get_build_name(),
		"level": build.level,
		"upgrade_history": serialized_upgrades,
		"defeats_by_archetype": serialized_defeats,
	}
