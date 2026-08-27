extends SceneTree

const AtmosphereModel = preload("res://scripts/world_atmosphere.gd")

var _failures: Array[String] = []


func _init() -> void:
	var verdant := AtmosphereModel.sample_palette(Vector3(1.0, 0.0, 0.0))
	var ember := AtmosphereModel.sample_palette(Vector3(0.0, 1.0, 0.0))
	var prism := AtmosphereModel.sample_palette(Vector3(0.0, 0.0, 1.0))
	_expect(Color(verdant.sky_horizon).b > Color(verdant.sky_horizon).r * 3.0, "Verdant Reach should preserve a clear cyan-blue horizon.")
	_expect(Color(ember.sky_horizon).r > Color(ember.sky_horizon).b * 5.0, "Ember Basin should have an unmistakably warm horizon.")
	_expect(Color(prism.sky_horizon).b > Color(prism.sky_horizon).r, "Prism Highlands should have a cold violet horizon.")
	_expect(float(verdant.fog_density) < float(ember.fog_density) and float(ember.fog_density) < float(prism.fog_density), "Region depth should increase gradually without hiding high-speed sightlines.")

	var midpoint := AtmosphereModel.sample_palette(Vector3(0.5, 0.5, 0.0))
	_expect(Color(midpoint.sky_top).is_equal_approx(Color(verdant.sky_top).lerp(Color(ember.sky_top), 0.5)), "Atmosphere boundaries should blend instead of snapping between palettes.")
	_expect(is_equal_approx(float(midpoint.sun_energy), (float(verdant.sun_energy) + float(ember.sun_energy)) * 0.5), "Lighting energy should blend with the visible sky.")
	var normalized := AtmosphereModel.sample_palette(Vector3(4.0, 4.0, 0.0))
	_expect(Color(normalized.sky_horizon).is_equal_approx(Color(midpoint.sky_horizon)), "Palette sampling should normalize arbitrary non-negative region weights.")
	var fallback := AtmosphereModel.sample_palette(Vector3.ZERO)
	_expect(Color(fallback.sky_top).is_equal_approx(Color(verdant.sky_top)), "Invalid empty weights should safely fall back to the opening region.")

	_expect(AtmosphereModel.REGION_ORDER.size() == 3 and AtmosphereModel.REGION_SUBTITLES.size() == 3, "Every procedural region should have one concise discovery identity.")
	if _failures.is_empty():
		print("World atmosphere validation passed — three distinct palettes, normalized blending, and sightline-safe depth agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
