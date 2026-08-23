class_name SeedService
extends RefCounted

## Domain-separated SHA-256 seeds keep route, reward, weather, and decoration RNG
## consumption independent. RandomNumberGenerator behavior is pinned with Godot.

const GENERATOR_VERSION := 1


static func derive_seed(root_seed: int, domain: StringName, stable_id: String = "") -> int:
	var context := HashingContext.new()
	var error := context.start(HashingContext.HASH_SHA256)
	assert(error == OK)
	var domain_text := String(domain)
	var payload := "%d|%d|%d:%s|%d:%s" % [
		GENERATOR_VERSION,
		root_seed,
		domain_text.to_utf8_buffer().size(),
		domain_text,
		stable_id.to_utf8_buffer().size(),
		stable_id,
	]
	error = context.update(payload.to_utf8_buffer())
	assert(error == OK)
	var digest := context.finish()
	return digest.decode_u64(0) & 0x7fffffffffffffff


static func create_rng(root_seed: int, domain: StringName, stable_id: String = "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(root_seed, domain, stable_id)
	return rng


static func parse_user_seed(text: String) -> int:
	var normalized := text.strip_edges()
	if normalized.is_empty():
		return int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	if normalized.is_valid_int():
		return normalized.to_int()
	return derive_seed(0, &"user_text", normalized.to_lower())


static func signature(root_seed: int, domain: StringName, stable_id: String = "") -> String:
	return "%016x" % derive_seed(root_seed, domain, stable_id)
