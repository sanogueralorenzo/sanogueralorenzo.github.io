class_name RunBuild
extends RefCounted

const UPGRADE_IDS: Array[StringName] = [
	&"dash_nova",
	&"slipstream",
	&"velocity_coil",
	&"arc_capacitor",
	&"forked_current",
	&"kinetic_repair",
]

const UPGRADE_NAMES := {
	&"dash_nova": "DASH NOVA",
	&"slipstream": "SLIPSTREAM",
	&"velocity_coil": "VELOCITY COIL",
	&"arc_capacitor": "ARC CAPACITOR",
	&"forked_current": "FORKED CURRENT",
	&"kinetic_repair": "KINETIC REPAIR",
}

const UPGRADE_DESCRIPTIONS := {
	&"dash_nova": "Dashing releases a damaging shockwave. Further picks widen and strengthen it.",
	&"slipstream": "High-speed travel leaves a damaging wake. Further picks improve its reach.",
	&"velocity_coil": "Arc damage scales with your current movement speed.",
	&"arc_capacitor": "Fire arcs 18% faster.",
	&"forked_current": "Fire one additional arc at a different target.",
	&"kinetic_repair": "Gain 20 maximum integrity and immediately repair 30.",
}

var level := 1
var experience := 0
var experience_to_next := 12
var pending_levels := 0

var weapon_damage := 18.0
var fire_interval := 0.58
var projectile_count := 1
var speed_damage_bonus := 0.0
var dash_nova_level := 0
var slipstream_level := 0
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
	if upgrade_ranks.is_empty():
		return [&"dash_nova", &"slipstream", &"velocity_coil"]
	var candidates := UPGRADE_IDS.duplicate()
	var options: Array[StringName] = []
	while options.size() < 3 and not candidates.is_empty():
		var index := rng.randi_range(0, candidates.size() - 1)
		options.append(candidates.pop_at(index))
	return options


func apply_upgrade(upgrade_id: StringName) -> Dictionary:
	if not UPGRADE_NAMES.has(upgrade_id):
		return {}
	upgrade_ranks[upgrade_id] = int(upgrade_ranks.get(upgrade_id, 0)) + 1
	match upgrade_id:
		&"dash_nova":
			dash_nova_level += 1
		&"slipstream":
			slipstream_level += 1
		&"velocity_coil":
			speed_damage_bonus += 0.006
		&"arc_capacitor":
			fire_interval = maxf(0.18, fire_interval * 0.82)
		&"forked_current":
			projectile_count = mini(5, projectile_count + 1)
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


func get_upgrade_name(upgrade_id: StringName) -> String:
	return str(UPGRADE_NAMES.get(upgrade_id, "UNKNOWN UPGRADE"))


func get_upgrade_description(upgrade_id: StringName) -> String:
	return str(UPGRADE_DESCRIPTIONS.get(upgrade_id, ""))


func get_upgrade_rank(upgrade_id: StringName) -> int:
	return int(upgrade_ranks.get(upgrade_id, 0))


func get_progress_ratio() -> float:
	return float(experience) / float(maxi(experience_to_next, 1))


func _experience_requirement(target_level: int) -> int:
	return roundi(12.0 + pow(float(target_level - 1), 1.32) * 7.5)
