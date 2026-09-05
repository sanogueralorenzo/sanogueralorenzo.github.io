class_name SeabreezeRandom
extends RefCounted
var state: int = 1
var seed: int = 1:
	set(value):
		seed = value
		state = value & 0xffffffff


func randf() -> float:
	state = (state + 1831565813) & 0xffffffff
	var mixed: int = ((state ^ (state >> 15)) * (1 | state)) & 0xffffffff
	mixed = ((mixed + (((mixed ^ (mixed >> 7)) * (61 | mixed)) & 0xffffffff)) ^ mixed) & 0xffffffff
	return float((mixed ^ (mixed >> 14)) & 0xffffffff) / 4294967296.0


func randf_range(low: float, high: float) -> float:
	return low + (high - low) * self.randf()


func randi_range(low: int, high: int) -> int:
	return low + floori(self.randf() * (high - low + 1))
