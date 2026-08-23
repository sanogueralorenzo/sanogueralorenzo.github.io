class_name ProfileConfigCodec
extends RefCounted

## Adapts on-disk ConfigFile layouts into schema-owned primitive dictionaries.
## Version-specific layouts stay here so migrations receive the format they expect.


static func decode(config: ConfigFile) -> Dictionary:
	var schema_version := int(config.get_value("meta", "schema_version", 0))
	if schema_version == 0:
		return {
			"schema_version": 0,
			"unlocks": config.get_value("progress", "unlocks", PackedStringArray()),
			"runs": config.get_value("stats", "runs", 0),
			"completions": config.get_value("stats", "completions", 0),
			"best_time_ms": config.get_value("stats", "best_time_ms", -1),
		}
	return {
		"schema_version": schema_version,
		"unlocks": config.get_value("progress", "unlocks", PackedStringArray()),
		"stats": {
			"runs_started": config.get_value("stats", "runs_started", 0),
			"runs_completed": config.get_value("stats", "runs_completed", 0),
			"best_time_ms": config.get_value("stats", "best_time_ms", -1),
		},
		"checkpoint": {
			"valid": config.get_value("checkpoint", "valid", false),
			"seed": config.get_value("checkpoint", "seed", 0),
			"plan_signature": config.get_value("checkpoint", "plan_signature", ""),
			"biome_index": config.get_value("checkpoint", "biome_index", 0),
			"upgrade_ids": config.get_value("checkpoint", "upgrade_ids", PackedStringArray()),
		},
	}

