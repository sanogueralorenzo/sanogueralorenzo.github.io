class_name CozyMapRegistry
extends Resource
@export var maps: Array[CozyMapDefinition] = []

func find_map(id: StringName) -> CozyMapDefinition:
	for destination in maps:
		if destination.id == id: return destination
	return null

func validation_error() -> String:
	var ids := {}
	for destination in maps:
		if destination == null or destination.id.is_empty(): return "A destination needs a stable ID."
		if ids.has(destination.id): return "Destination IDs must be unique."
		ids[destination.id] = true
		if destination.title.is_empty() or destination.preview == null: return "A destination needs a title and preview."
		if not ResourceLoader.exists(destination.scene): return "A destination scene is unavailable."
	return "No destinations are registered." if maps.is_empty() else ""
