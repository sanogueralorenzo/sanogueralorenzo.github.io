class_name RunBuild
extends RefCounted

const DASHBREAKER := &"dashbreaker"
const STORMTRAIL := &"stormtrail"
const ARCSTORM := &"arcstorm"

const KEYSTONE_IDS: Array[StringName] = [&"dash_nova", &"slipstream", &"velocity_coil"]
const PATH_UPGRADES := {
	DASHBREAKER: [&"dash_nova", &"dash_echo", &"phase_shell", &"kinetic_repair"],
	STORMTRAIL: [&"slipstream", &"wake_duration", &"wake_width", &"wake_voltage", &"kinetic_repair"],
	ARCSTORM: [&"velocity_coil", &"arc_capacitor", &"forked_current", &"arc_chain", &"arc_payload", &"kinetic_repair"],
}

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
var upgrade_ranks: Dictionary = {}


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


func get_upgrade_options(rng: RandomNumberGenerator) -> Array[StringName]:
	if core_path.is_empty():
		return KEYSTONE_IDS.duplicate()
	var candidates: Array = PATH_UPGRADES[core_path].duplicate()
	_filter_capped_upgrades(candidates)
	var options: Array[StringName] = []
	while options.size() < 3 and not candidates.is_empty():
		var index := rng.randi_range(0, candidates.size() - 1)
		options.append(StringName(candidates.pop_at(index)))
	return options


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
	return str(PATH_NAMES.get(core_path, "UNCOMMITTED"))


func get_upgrade_name(upgrade_id: StringName) -> String:
	return str(UPGRADE_NAMES.get(upgrade_id, "UNKNOWN UPGRADE"))


func get_upgrade_description(upgrade_id: StringName) -> String:
	return str(UPGRADE_DESCRIPTIONS.get(upgrade_id, ""))


func get_upgrade_rank(upgrade_id: StringName) -> int:
	return int(upgrade_ranks.get(upgrade_id, 0))


func get_progress_ratio() -> float:
	return float(experience) / float(maxi(experience_to_next, 1))


func _is_upgrade_allowed(upgrade_id: StringName) -> bool:
	if core_path.is_empty():
		return upgrade_id in KEYSTONE_IDS
	return upgrade_id in PATH_UPGRADES[core_path]


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
		if _is_capped(StringName(upgrade_id)):
			candidates.erase(upgrade_id)


func _is_capped(upgrade_id: StringName) -> bool:
	match upgrade_id:
		&"forked_current":
			return projectile_count >= 5
		&"arc_capacitor":
			return fire_interval <= 0.1801
		&"arc_chain":
			return arc_chain_count >= 4
		&"phase_shell":
			return get_upgrade_rank(upgrade_id) >= 3
		&"wake_duration":
			return get_upgrade_rank(upgrade_id) >= 4
		&"wake_width":
			return get_upgrade_rank(upgrade_id) >= 6
		_:
			return false


func _experience_requirement(target_level: int) -> int:
	return roundi(12.0 + pow(float(target_level - 1), 1.32) * 7.5)
