class_name ApexCatalog
extends RefCounted

const VELOCITY_REAVER := &"velocity_reaver"
const RIFT_MATRIARCH := &"rift_matriarch"
const HORIZON_WARDEN := &"horizon_warden"
const IDS: Array[StringName] = [RIFT_MATRIARCH, HORIZON_WARDEN, VELOCITY_REAVER]

const DEFINITIONS := {
	VELOCITY_REAVER: {
		"title": "VELOCITY REAVER",
		"arrival": "It hunts your line — break its charge before 20:00",
		"enrage_title": "VELOCITY REAVER UNBOUND",
		"enrage_subtitle": "Charge recovery collapsing — keep changing lanes",
		"maximum_health": 2600.0,
		"movement_speed": 66.0,
		"contact_damage": 24.0,
		"body_radius": 6.2,
	},
	RIFT_MATRIARCH: {
		"title": "RIFT MATRIARCH",
		"arrival": "It predicts your route and seeds the storm — break it before 20:00",
		"enrage_title": "RIFT MATRIARCH FRACTURES",
		"enrage_subtitle": "Wider rifts. Faster broods. Refuse the marked ground.",
		"maximum_health": 2350.0,
		"movement_speed": 54.0,
		"contact_damage": 22.0,
		"body_radius": 6.6,
	},
	HORIZON_WARDEN: {
		"title": "HORIZON WARDEN",
		"arrival": "It folds the route into gates — break its geometry before 20:00",
		"enrage_title": "HORIZON WARDEN CONVERGES",
		"enrage_subtitle": "Wider gates. Faster cuts. Read the line before it closes.",
		"maximum_health": 2400.0,
		"movement_speed": 58.0,
		"contact_damage": 23.0,
		"body_radius": 6.4,
	},
}


static func get_for_seed(world_seed: int) -> StringName:
	return IDS[absi(world_seed) % IDS.size()]


static func is_valid(apex_id: StringName) -> bool:
	return DEFINITIONS.has(apex_id)


static func get_definition(apex_id: StringName) -> Dictionary:
	return DEFINITIONS.get(apex_id, DEFINITIONS[VELOCITY_REAVER]).duplicate(true)


static func get_title(apex_id: StringName) -> String:
	return str(get_definition(apex_id).title)
