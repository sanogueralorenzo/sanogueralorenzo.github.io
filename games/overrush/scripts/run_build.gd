class_name RunBuild
extends RefCounted

const DASHBREAKER := &"dashbreaker"
const STORMTRAIL := &"stormtrail"
const ARCSTORM := &"arcstorm"
const EVOLUTION_UNLOCK_RANK := 4
const CATALYST_UNLOCK_RANK := 7
const PULSE_WINDOW_SECONDS := 0.42

const KEYSTONE_IDS: Array[StringName] = [&"dash_nova", &"slipstream", &"velocity_coil"]
const PATH_UPGRADES := {
	DASHBREAKER: [&"dash_nova", &"dash_echo", &"phase_shell", &"kinetic_repair"],
	STORMTRAIL: [&"slipstream", &"wake_duration", &"wake_width", &"wake_voltage", &"kinetic_repair"],
	ARCSTORM: [&"velocity_coil", &"arc_capacitor", &"forked_current", &"arc_chain", &"arc_payload", &"kinetic_repair"],
}
const PATH_EVOLUTIONS := {
	DASHBREAKER: [&"ramjet", &"gravity_knot"],
	STORMTRAIL: [&"twin_current", &"tempest_anchor"],
	ARCSTORM: [&"storm_lance", &"arc_orbit"],
}
const EVOLUTION_SUPPORT := {
	&"ramjet": &"ramjet_mass",
	&"gravity_knot": &"event_horizon",
	&"twin_current": &"parallel_flow",
	&"tempest_anchor": &"storm_charge",
	&"storm_lance": &"lance_focus",
	&"arc_orbit": &"orbit_flux",
}
const REDLINE_CORE := &"redline_core"
const AIRFRAME_CORE := &"airframe_core"
const PULSE_CORE := &"pulse_core"
const CATALYST_IDS: Array[StringName] = [REDLINE_CORE, AIRFRAME_CORE, PULSE_CORE]

const UPGRADE_NAMES := {
	&"dash_nova": "DASHBREAKER",
	&"slipstream": "STORMTRAIL",
	&"velocity_coil": "ARCSTORM",
	&"dash_echo": "EXIT WOUND",
	&"phase_shell": "PHASE SHELL",
	&"wake_duration": "LONG WAKE",
	&"wake_width": "CROSSWIND",
	&"wake_voltage": "STATIC PRESSURE",
	&"arc_capacitor": "ARC CAPACITOR",
	&"forked_current": "FORKED CURRENT",
	&"arc_chain": "CHAIN LIGHTNING",
	&"arc_payload": "ION PAYLOAD",
	&"kinetic_repair": "KINETIC REPAIR",
	&"ramjet": "RAMJET",
	&"gravity_knot": "GRAVITY KNOT",
	&"twin_current": "TWIN CURRENT",
	&"tempest_anchor": "TEMPEST ANCHOR",
	&"storm_lance": "STORM LANCE",
	&"arc_orbit": "ARC ORBIT",
	&"ramjet_mass": "IMPACT MASS",
	&"event_horizon": "EVENT HORIZON",
	&"parallel_flow": "PARALLEL FLOW",
	&"storm_charge": "STORM CHARGE",
	&"lance_focus": "LANCE FOCUS",
	&"orbit_flux": "ORBIT FLUX",
	REDLINE_CORE: "REDLINE CORE",
	AIRFRAME_CORE: "AIRFRAME CORE",
	PULSE_CORE: "PULSE CORE",
}

const UPGRADE_DESCRIPTIONS := {
	&"dash_nova": "Commit to dash combat. Dash entry detonates a shockwave; further ranks widen and strengthen it.",
	&"slipstream": "Commit to route control. Movement leaves persistent damaging wakes; further ranks strengthen them.",
	&"velocity_coil": "Commit to ranged chaining. Arc damage scales with speed; further ranks amplify the scaling.",
	&"dash_echo": "Dash exit detonates a second, smaller shockwave.",
	&"phase_shell": "Gain a brief damage-immunity window whenever a dash begins.",
	&"wake_duration": "Stormtrail zones remain active 0.7 seconds longer.",
	&"wake_width": "Stormtrail zones grow wider and catch more enemies.",
	&"arc_capacitor": "Arcstorm fires 18% faster.",
	&"forked_current": "Arcstorm launches one additional bolt at a different target.",
	&"arc_chain": "Each Arcstorm bolt jumps to one additional nearby target at reduced damage.",
	&"wake_voltage": "Stormtrail crossings deal 3 additional damage.",
	&"arc_payload": "Arcstorm bolts deal 4 additional base damage.",
	&"kinetic_repair": "Gain 20 maximum integrity and immediately repair 30.",
	&"ramjet": "Evolve Dashbreaker into a direct-impact engine. Every dash can strike each enemy along its path once.",
	&"gravity_knot": "Evolve Dashbreaker into a setup engine. Dash exits pull threats inward before a delayed collapse.",
	&"twin_current": "Evolve Stormtrail into two parallel wake lanes that reward weaving through enemy packs.",
	&"tempest_anchor": "Evolve Stormtrail to periodically leave large storm zones that strike the same threats repeatedly.",
	&"storm_lance": "Evolve Arcstorm into a forward piercing beam. Line up distant packs and keep your heading committed.",
	&"arc_orbit": "Evolve Arcstorm into a close-range electrical orbit that rewards threading through dense threats.",
	&"ramjet_mass": "Ramjet impacts gain damage and a wider collision corridor.",
	&"event_horizon": "Gravity Knot pulls from farther away and its delayed collapse hits harder.",
	&"parallel_flow": "Twin Current lanes spread farther and retain more Stormtrail damage.",
	&"storm_charge": "Tempest Anchors occur more often, pulse faster, and grow more violent.",
	&"lance_focus": "Storm Lance reaches farther, widens, pierces more targets, and gains damage.",
	&"orbit_flux": "Arc Orbit expands, strikes faster, and gains damage.",
	REDLINE_CORE: "-22% at cruise; scales to +50% at dash speed. Keep accelerating.",
	AIRFRAME_CORE: "+40% to attacks created airborne; -20% grounded. Commit to hops and hills.",
	PULSE_CORE: "+35% to attacks created during a dash and 0.42 seconds after; -25% otherwise.",
}

const PATH_NAMES := {
	DASHBREAKER: "DASHBREAKER",
	STORMTRAIL: "STORMTRAIL",
	ARCSTORM: "ARCSTORM",
}

var level := 1
var experience := 0
var experience_to_next := 12
var pending_levels := 0
var core_path: StringName = &""
var evolution_id: StringName = &""
var catalyst_id: StringName = &""

var weapon_damage := 18.0
var fire_interval := 0.58
var projectile_count := 1
var speed_damage_bonus := 0.0
var arc_chain_count := 0
var dash_nova_level := 0
var dash_echo_level := 0
var phase_shell_level := 0
var slipstream_level := 0
var wake_duration_bonus := 0.0
var wake_width_bonus := 0.0
var wake_damage_bonus := 0.0
var maximum_integrity_bonus := 0.0
var ramjet_mass_level := 0
var event_horizon_level := 0
var parallel_flow_level := 0
var storm_charge_level := 0
var lance_focus_level := 0
var orbit_flux_level := 0
var upgrade_ranks: Dictionary = {}
var banished_upgrades: Dictionary = {}


func add_experience(amount: int) -> int:
	experience += maxi(amount, 0)
	var levels_gained := 0
	while experience >= experience_to_next:
		experience -= experience_to_next
		level += 1
		levels_gained += 1
		pending_levels += 1
		experience_to_next = _experience_requirement(level)
	return levels_gained


func get_upgrade_options(rng: RandomNumberGenerator, avoid_options: Array[StringName] = []) -> Array[StringName]:
	if core_path.is_empty():
		return KEYSTONE_IDS.duplicate()
	var candidates := _get_available_path_upgrades()
	if evolution_id.is_empty() and get_specialization_rank() >= EVOLUTION_UNLOCK_RANK:
		var evolution_options: Array[StringName] = []
		for upgrade_id in PATH_EVOLUTIONS[core_path]:
			evolution_options.append(StringName(upgrade_id))
		if not candidates.is_empty():
			var standard_options := _draw_options(candidates, rng, avoid_options, 1)
			if not standard_options.is_empty():
				evolution_options.append(standard_options[0])
		return evolution_options
	if not evolution_id.is_empty() and catalyst_id.is_empty() and get_specialization_rank() >= CATALYST_UNLOCK_RANK:
		return CATALYST_IDS.duplicate()
	return _draw_options(candidates, rng, avoid_options, 3)


func apply_upgrade(upgrade_id: StringName) -> Dictionary:
	if not UPGRADE_NAMES.has(upgrade_id) or not _is_upgrade_allowed(upgrade_id) or _is_capped(upgrade_id):
		return {}
	if core_path.is_empty():
		core_path = _path_for_keystone(upgrade_id)
	upgrade_ranks[upgrade_id] = int(upgrade_ranks.get(upgrade_id, 0)) + 1
	match upgrade_id:
		&"dash_nova":
			dash_nova_level += 1
		&"dash_echo":
			dash_echo_level += 1
		&"phase_shell":
			phase_shell_level += 1
		&"slipstream":
			slipstream_level += 1
		&"wake_duration":
			wake_duration_bonus += 0.7
		&"wake_width":
			wake_width_bonus += 2.6
		&"wake_voltage":
			wake_damage_bonus += 3.0
		&"velocity_coil":
			speed_damage_bonus += 0.006
		&"arc_capacitor":
			fire_interval = maxf(0.18, fire_interval * 0.82)
		&"forked_current":
			projectile_count = mini(5, projectile_count + 1)
		&"arc_chain":
			arc_chain_count = mini(4, arc_chain_count + 1)
		&"arc_payload":
			weapon_damage += 4.0
		&"kinetic_repair":
			maximum_integrity_bonus += 20.0
		&"ramjet", &"gravity_knot", &"twin_current", &"tempest_anchor", &"storm_lance", &"arc_orbit":
			evolution_id = upgrade_id
		&"ramjet_mass":
			ramjet_mass_level += 1
		&"event_horizon":
			event_horizon_level += 1
		&"parallel_flow":
			parallel_flow_level += 1
		&"storm_charge":
			storm_charge_level += 1
		&"lance_focus":
			lance_focus_level += 1
		&"orbit_flux":
			orbit_flux_level += 1
		REDLINE_CORE, AIRFRAME_CORE, PULSE_CORE:
			catalyst_id = upgrade_id
	return {
		"id": upgrade_id,
		"rank": int(upgrade_ranks[upgrade_id]),
		"repair": 30.0 if upgrade_id == &"kinetic_repair" else 0.0,
		"maximum_integrity": 20.0 if upgrade_id == &"kinetic_repair" else 0.0,
	}


func consume_pending_level() -> void:
	pending_levels = maxi(0, pending_levels - 1)


func get_arc_damage(horizontal_speed: float) -> float:
	var speed_over_cruise := maxf(0.0, horizontal_speed - 45.0)
	return weapon_damage * (1.0 + speed_over_cruise * speed_damage_bonus)


func is_arc_weapon_enabled() -> bool:
	return core_path.is_empty() or core_path == ARCSTORM


func get_dash_nova_damage() -> float:
	return 24.0 + dash_nova_level * 14.0


func get_dash_nova_radius() -> float:
	return 15.0 + dash_nova_level * 4.0


func get_dash_echo_damage() -> float:
	return get_dash_nova_damage() * (0.5 + dash_echo_level * 0.14)


func get_phase_shell_duration() -> float:
	return 0.16 + phase_shell_level * 0.12


func get_wake_duration() -> float:
	return 1.45 + slipstream_level * 0.15 + wake_duration_bonus


func get_wake_radius() -> float:
	return 7.5 + slipstream_level * 2.0 + wake_width_bonus


func get_wake_damage(horizontal_speed: float) -> float:
	return (5.0 + slipstream_level * 2.5 + wake_damage_bonus) * maxf(1.0, horizontal_speed / 58.0)


func get_build_name() -> String:
	var path_name := str(PATH_NAMES.get(core_path, "UNCOMMITTED"))
	return path_name if evolution_id.is_empty() else "%s • %s" % [path_name, get_upgrade_name(evolution_id)]


func get_upgrade_name(upgrade_id: StringName) -> String:
	return str(UPGRADE_NAMES.get(upgrade_id, "UNKNOWN UPGRADE"))


func get_upgrade_description(upgrade_id: StringName) -> String:
	return str(UPGRADE_DESCRIPTIONS.get(upgrade_id, ""))


func get_upgrade_rank(upgrade_id: StringName) -> int:
	return int(upgrade_ranks.get(upgrade_id, 0))


func is_evolution_upgrade(upgrade_id: StringName) -> bool:
	return upgrade_id in PATH_EVOLUTIONS.get(core_path, [])


func is_catalyst_upgrade(upgrade_id: StringName) -> bool:
	return upgrade_id in CATALYST_IDS


func can_banish_upgrade(upgrade_id: StringName) -> bool:
	if core_path.is_empty() or is_evolution_upgrade(upgrade_id) or is_catalyst_upgrade(upgrade_id) or banished_upgrades.has(upgrade_id):
		return false
	var candidates := _get_available_path_upgrades()
	if upgrade_id not in candidates:
		return false
	candidates.erase(upgrade_id)
	return candidates.size() >= 3


func banish_upgrade(upgrade_id: StringName) -> bool:
	if not can_banish_upgrade(upgrade_id):
		return false
	banished_upgrades[upgrade_id] = true
	return true


func has_alternative_upgrade_options(current_options: Array[StringName]) -> bool:
	if core_path.is_empty():
		return false
	for upgrade_id in current_options:
		if is_catalyst_upgrade(upgrade_id):
			return false
	for upgrade_id in _get_available_path_upgrades():
		if StringName(upgrade_id) not in current_options:
			return true
	return false


func is_upgrade_banished(upgrade_id: StringName) -> bool:
	return banished_upgrades.has(upgrade_id)


func get_progress_ratio() -> float:
	return float(experience) / float(maxi(experience_to_next, 1))


func get_specialization_rank() -> int:
	if core_path.is_empty():
		return 0
	var total := 0
	for upgrade_id in PATH_UPGRADES[core_path]:
		if upgrade_id != &"kinetic_repair":
			total += get_upgrade_rank(StringName(upgrade_id))
	return total


func get_catalyst_name() -> String:
	return get_upgrade_name(catalyst_id) if not catalyst_id.is_empty() else "UNTUNED DRIVE"


func get_catalyst_damage_multiplier(horizontal_speed: float, airborne: bool, pulse_active: bool) -> float:
	match catalyst_id:
		REDLINE_CORE:
			var speed_ratio := clampf((horizontal_speed - 58.0) / (126.0 - 58.0), 0.0, 1.0)
			return lerpf(0.78, 1.5, speed_ratio)
		AIRFRAME_CORE:
			return 1.4 if airborne else 0.8
		PULSE_CORE:
			return 1.35 if pulse_active else 0.75
		_:
			return 1.0


func is_ramjet() -> bool:
	return evolution_id == &"ramjet"


func get_ramjet_damage(horizontal_speed: float) -> float:
	return (18.0 + ramjet_mass_level * 5.0) * maxf(1.0, horizontal_speed / 58.0)


func get_ramjet_radius() -> float:
	return 2.8 + ramjet_mass_level * 0.35


func is_gravity_knot() -> bool:
	return evolution_id == &"gravity_knot"


func get_gravity_knot_radius() -> float:
	return 24.0 + event_horizon_level * 3.0


func get_gravity_knot_damage() -> float:
	return 18.0 + event_horizon_level * 6.0


func get_gravity_knot_pull_ratio() -> float:
	return minf(0.66, 0.42 + event_horizon_level * 0.06)


func is_twin_current() -> bool:
	return evolution_id == &"twin_current"


func get_twin_current_offset() -> float:
	return 9.0 + parallel_flow_level


func get_twin_current_damage_multiplier() -> float:
	return minf(0.86, 0.58 + parallel_flow_level * 0.09)


func is_tempest_anchor() -> bool:
	return evolution_id == &"tempest_anchor"


func get_anchor_stride() -> int:
	return maxi(3, 5 - storm_charge_level)


func get_anchor_repeat_interval() -> float:
	return maxf(0.32, 0.58 - storm_charge_level * 0.08)


func get_anchor_radius_multiplier() -> float:
	return 1.6 + storm_charge_level * 0.1


func get_anchor_duration_multiplier() -> float:
	return 1.7 + storm_charge_level * 0.15


func get_anchor_damage_multiplier() -> float:
	return 1.05 + storm_charge_level * 0.12


func is_storm_lance() -> bool:
	return evolution_id == &"storm_lance"


func get_lance_interval() -> float:
	return maxf(0.32, fire_interval * 1.35)


func get_lance_range() -> float:
	return 115.0 + lance_focus_level * 10.0


func get_lance_width() -> float:
	return 6.0 + lance_focus_level * 1.2


func get_lance_damage(horizontal_speed: float) -> float:
	return get_arc_damage(horizontal_speed) * (2.0 + lance_focus_level * 0.25)


func get_lance_target_limit() -> int:
	return 5 + lance_focus_level * 2


func is_arc_orbit() -> bool:
	return evolution_id == &"arc_orbit"


func get_orbit_interval() -> float:
	return maxf(0.24, fire_interval * 0.95 - orbit_flux_level * 0.04)


func get_orbit_radius() -> float:
	return 20.0 + orbit_flux_level * 2.5


func get_orbit_damage(horizontal_speed: float) -> float:
	return get_arc_damage(horizontal_speed) * (0.72 + orbit_flux_level * 0.1)


func _is_upgrade_allowed(upgrade_id: StringName) -> bool:
	if banished_upgrades.has(upgrade_id):
		return false
	if core_path.is_empty():
		return upgrade_id in KEYSTONE_IDS
	if upgrade_id in PATH_UPGRADES[core_path]:
		return true
	if evolution_id.is_empty():
		return get_specialization_rank() >= EVOLUTION_UNLOCK_RANK and upgrade_id in PATH_EVOLUTIONS[core_path]
	if catalyst_id.is_empty() and get_specialization_rank() >= CATALYST_UNLOCK_RANK and upgrade_id in CATALYST_IDS:
		return true
	return upgrade_id == EVOLUTION_SUPPORT[evolution_id]


func _path_for_keystone(upgrade_id: StringName) -> StringName:
	match upgrade_id:
		&"dash_nova":
			return DASHBREAKER
		&"slipstream":
			return STORMTRAIL
		&"velocity_coil":
			return ARCSTORM
		_:
			return &""


func _filter_capped_upgrades(candidates: Array) -> void:
	for upgrade_id in candidates.duplicate():
		if _is_capped(StringName(upgrade_id)) or banished_upgrades.has(upgrade_id):
			candidates.erase(upgrade_id)


func _get_available_path_upgrades() -> Array:
	if core_path.is_empty():
		return []
	var candidates: Array = PATH_UPGRADES[core_path].duplicate()
	if not evolution_id.is_empty():
		candidates.append(EVOLUTION_SUPPORT[evolution_id])
	_filter_capped_upgrades(candidates)
	return candidates


func _draw_options(
	candidates: Array,
	rng: RandomNumberGenerator,
	avoid_options: Array[StringName],
	limit: int
) -> Array[StringName]:
	var preferred: Array = []
	var fallback: Array = []
	for upgrade_id in candidates:
		if StringName(upgrade_id) in avoid_options:
			fallback.append(upgrade_id)
		else:
			preferred.append(upgrade_id)
	var options: Array[StringName] = []
	_draw_from_pool(preferred, rng, options, limit)
	_draw_from_pool(fallback, rng, options, limit)
	return options


func _draw_from_pool(pool: Array, rng: RandomNumberGenerator, options: Array[StringName], limit: int) -> void:
	while options.size() < limit and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		options.append(StringName(pool.pop_at(index)))


func _is_capped(upgrade_id: StringName) -> bool:
	if upgrade_id in CATALYST_IDS:
		return not catalyst_id.is_empty()
	if upgrade_id in PATH_EVOLUTIONS.get(core_path, []):
		return not evolution_id.is_empty()
	if upgrade_id in EVOLUTION_SUPPORT.values():
		return get_upgrade_rank(upgrade_id) >= 3
	match upgrade_id:
		&"forked_current":
			return projectile_count >= 5
		&"arc_capacitor":
			return fire_interval <= 0.1801
		&"arc_chain":
			return arc_chain_count >= 4
		&"phase_shell":
			return get_upgrade_rank(upgrade_id) >= 3
		&"kinetic_repair":
			return get_upgrade_rank(upgrade_id) >= 3
		&"wake_duration":
			return get_upgrade_rank(upgrade_id) >= 4
		&"wake_width":
			return get_upgrade_rank(upgrade_id) >= 6
		_:
			return false


func _experience_requirement(target_level: int) -> int:
	return roundi(12.0 + pow(float(target_level - 1), 1.32) * 7.5)
