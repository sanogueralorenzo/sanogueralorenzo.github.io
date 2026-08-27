class_name EliteTraits
extends RefCounted

const RAZOR := &"razor"
const HORIZON := &"horizon"
const TEMPEST := &"tempest"
const ORDER: Array[StringName] = [RAZOR, HORIZON, TEMPEST]

const DEFINITIONS := {
	RAZOR: {
		"name": "RAZOR",
		"subtitle": "Fast intercept • tighter warning • brittle shell",
		"health_multiplier": 0.72,
		"movement_multiplier": 1.1,
		"damage_multiplier": 0.72,
		"telegraph_multiplier": 0.92,
		"cooldown_multiplier": 1.0,
		"radius_multiplier": 0.9,
		"color": Color(0.08, 0.88, 1.0),
	},
	HORIZON: {
		"name": "HORIZON",
		"subtitle": "Wide geometry • longer warning • slower pursuit",
		"health_multiplier": 0.95,
		"movement_multiplier": 0.78,
		"damage_multiplier": 0.58,
		"telegraph_multiplier": 1.45,
		"cooldown_multiplier": 1.2,
		"radius_multiplier": 1.22,
		"color": Color(1.0, 0.3, 0.72),
	},
	TEMPEST: {
		"name": "TEMPEST",
		"subtitle": "Rapid signatures • standard geometry • fractured armor",
		"health_multiplier": 0.65,
		"movement_multiplier": 0.92,
		"damage_multiplier": 0.58,
		"telegraph_multiplier": 1.08,
		"cooldown_multiplier": 0.72,
		"radius_multiplier": 1.0,
		"color": Color(0.44, 1.0, 0.34),
	},
}


static func get_for_seed(world_seed: int, elite_index: int) -> StringName:
	var seed_offset := posmod(absi(world_seed), ORDER.size())
	return ORDER[posmod(seed_offset + maxi(0, elite_index), ORDER.size())]


static func is_valid(trait_id: StringName) -> bool:
	return DEFINITIONS.has(trait_id)


static func get_definition(trait_id: StringName) -> Dictionary:
	return DEFINITIONS.get(trait_id, DEFINITIONS[RAZOR]).duplicate(true)


static func get_title(trait_id: StringName) -> String:
	return str(get_definition(trait_id).name)


static func get_subtitle(trait_id: StringName) -> String:
	return str(get_definition(trait_id).subtitle)


static func get_color(trait_id: StringName) -> Color:
	return Color(get_definition(trait_id).color)
