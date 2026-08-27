class_name RunProtocols
extends RefCounted

const STANDARD := &"standard"
const REDLINE := &"redline"
const GLASS_VELOCITY := &"glass_velocity"
const ELITE_HUNT := &"elite_hunt"

const ORDER: Array[StringName] = [STANDARD, REDLINE, GLASS_VELOCITY, ELITE_HUNT]
const DEFINITIONS := {
	STANDARD: {
		"name": "OPEN CIRCUIT",
		"description": "The intended baseline run. No protocol modifiers.",
		"unlock_momentum": 0,
		"spawn_interval_multiplier": 1.0,
		"enemy_health_multiplier": 1.0,
		"outgoing_damage_multiplier": 1.0,
		"integrity_multiplier": 1.0,
		"extra_elite_interval": 0.0,
		"reward_multiplier": 1.0,
	},
	REDLINE: {
		"name": "REDLINE PROTOCOL",
		"description": "Threats arrive 28% faster. Momentum rewards are multiplied by 1.35.",
		"unlock_momentum": 120,
		"spawn_interval_multiplier": 0.72,
		"enemy_health_multiplier": 1.0,
		"outgoing_damage_multiplier": 1.0,
		"integrity_multiplier": 1.0,
		"extra_elite_interval": 0.0,
		"reward_multiplier": 1.35,
	},
	GLASS_VELOCITY: {
		"name": "GLASS VELOCITY",
		"description": "Deal 40% more damage, but maximum integrity falls by 35%. Rewards are multiplied by 1.30.",
		"unlock_momentum": 300,
		"spawn_interval_multiplier": 1.0,
		"enemy_health_multiplier": 1.0,
		"outgoing_damage_multiplier": 1.4,
		"integrity_multiplier": 0.65,
		"extra_elite_interval": 0.0,
		"reward_multiplier": 1.3,
	},
	ELITE_HUNT: {
		"name": "ELITE HUNT",
		"description": "Enemies gain 15% integrity and extra elites intercept every five minutes. Rewards are multiplied by 1.55.",
		"unlock_momentum": 550,
		"spawn_interval_multiplier": 0.9,
		"enemy_health_multiplier": 1.15,
		"outgoing_damage_multiplier": 1.0,
		"integrity_multiplier": 1.0,
		"extra_elite_interval": 300.0,
		"reward_multiplier": 1.55,
	},
}


static func get_definition(protocol_id: StringName) -> Dictionary:
	return DEFINITIONS.get(protocol_id, DEFINITIONS[STANDARD])


static func get_unlocked(momentum: int) -> Array[StringName]:
	var unlocked: Array[StringName] = []
	for protocol_id in ORDER:
		if momentum >= int(get_definition(protocol_id).unlock_momentum):
			unlocked.append(protocol_id)
	return unlocked


static func get_next_unlock(momentum: int) -> Dictionary:
	for protocol_id in ORDER:
		var definition := get_definition(protocol_id)
		if momentum < int(definition.unlock_momentum):
			return {
				"id": protocol_id,
				"name": str(definition.name),
				"required": int(definition.unlock_momentum),
			}
	return {}


static func is_valid(protocol_id: StringName) -> bool:
	return DEFINITIONS.has(protocol_id)
