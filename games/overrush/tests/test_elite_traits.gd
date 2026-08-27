extends SceneTree

const EliteTraitCatalog = preload("res://scripts/elite_traits.gd")

var _failures: Array[String] = []


func _init() -> void:
	var sequence: Array[StringName] = []
	for index in range(6):
		sequence.append(EliteTraitCatalog.get_for_seed(41001, index))
	for trait_id in EliteTraitCatalog.ORDER:
		_expect(sequence.count(trait_id) == 2, "A six-elite seed sequence should expose %s exactly twice instead of rolling streaks." % trait_id)
	_expect(sequence == _sequence_for(41001), "Elite doctrine rotation should be deterministic for a reproducible world seed.")
	_expect(sequence != _sequence_for(41002), "Adjacent world seeds should rotate the opening doctrine without changing the complete catalog.")

	var razor := EliteTraitCatalog.get_definition(EliteTraitCatalog.RAZOR)
	var horizon := EliteTraitCatalog.get_definition(EliteTraitCatalog.HORIZON)
	var tempest := EliteTraitCatalog.get_definition(EliteTraitCatalog.TEMPEST)
	_expect(float(razor.movement_multiplier) > 1.0 and float(razor.telegraph_multiplier) < 1.0 and float(razor.health_multiplier) < 1.0 and float(razor.damage_multiplier) < 0.8, "Razor should exchange durability and impact for a faster, tighter intercept.")
	_expect(float(horizon.radius_multiplier) > 1.2 and float(horizon.telegraph_multiplier) > 1.4 and float(horizon.movement_multiplier) < 0.8 and float(horizon.damage_multiplier) < 0.6, "Horizon should exchange pursuit speed, impact, and cadence for large, generously warned geometry.")
	_expect(float(tempest.cooldown_multiplier) < 0.75 and float(tempest.health_multiplier) < 0.7 and float(tempest.damage_multiplier) < 0.6 and is_equal_approx(float(tempest.radius_multiplier), 1.0), "Tempest should repeat standard geometry quickly through a brittle, lower-impact shell.")
	for trait_id in EliteTraitCatalog.ORDER:
		var definition := EliteTraitCatalog.get_definition(trait_id)
		_expect(not str(definition.name).is_empty() and "•" in str(definition.subtitle), "%s should have concise player-facing identity and counterplay." % trait_id)
		_expect(float(definition.health_multiplier) < 1.0 or float(definition.movement_multiplier) < 1.0 or float(definition.telegraph_multiplier) > 1.0, "%s should expose a real concession instead of being an opaque universal buff." % trait_id)
	_expect(EliteTraitCatalog.get_color(EliteTraitCatalog.RAZOR) != EliteTraitCatalog.get_color(EliteTraitCatalog.HORIZON) and EliteTraitCatalog.get_color(EliteTraitCatalog.HORIZON) != EliteTraitCatalog.get_color(EliteTraitCatalog.TEMPEST), "Every doctrine should remain distinguishable without reading its banner.")

	if _failures.is_empty():
		print("Elite doctrine validation passed — deterministic rotation, readable identities, and non-dominant tradeoffs agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _sequence_for(seed: int) -> Array[StringName]:
	var sequence: Array[StringName] = []
	for index in range(6):
		sequence.append(EliteTraitCatalog.get_for_seed(seed, index))
	return sequence


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
