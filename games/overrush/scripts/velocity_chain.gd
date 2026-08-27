class_name VelocityChain
extends RefCounted

const QUALIFYING_SPEED := 52.0
const BREAK_SPEED := 38.0
const CHAIN_WINDOW := 2.6
const DASH_GRACE := 0.45
const MAX_TIMER := CHAIN_WINDOW + DASH_GRACE
const ELITE_WEIGHT := 3
const MAX_MOMENTUM_BONUS := 24
const TIER_THRESHOLDS: Array[int] = [1, 3, 8, 16, 30]
const TIER_NAMES: Array[String] = ["BUILDING", "LOCKED", "SURGE", "OVERDRIVE", "UNBROKEN"]

var current_count := 0
var best_count := 0
var timer := 0.0
var total_qualifying_defeats := 0


func reset() -> void:
	current_count = 0
	best_count = 0
	timer = 0.0
	total_qualifying_defeats = 0


func update(delta: float, horizontal_speed: float) -> bool:
	if current_count <= 0:
		return false
	var drain_multiplier := 1.85 if horizontal_speed < BREAK_SPEED else 1.0
	timer = maxf(0.0, timer - maxf(0.0, delta) * drain_multiplier)
	if timer > 0.0:
		return false
	current_count = 0
	return true


func record_defeat(horizontal_speed: float, is_elite: bool = false) -> bool:
	if horizontal_speed < QUALIFYING_SPEED:
		return false
	var previous_tier := get_tier()
	if timer <= 0.0:
		current_count = 0
	current_count += ELITE_WEIGHT if is_elite else 1
	total_qualifying_defeats += 1
	best_count = maxi(best_count, current_count)
	timer = CHAIN_WINDOW
	return get_tier() > maxi(0, previous_tier)


func record_dash() -> void:
	if current_count > 0:
		timer = minf(MAX_TIMER, timer + DASH_GRACE)


func get_tier() -> int:
	if current_count <= 0:
		return -1
	for index in range(TIER_THRESHOLDS.size() - 1, -1, -1):
		if current_count >= TIER_THRESHOLDS[index]:
			return index
	return 0


func get_tier_name() -> String:
	var tier := get_tier()
	return "" if tier < 0 else TIER_NAMES[tier]


func get_timer_ratio() -> float:
	return clampf(timer / MAX_TIMER, 0.0, 1.0)


func get_momentum_bonus() -> int:
	return get_momentum_bonus_for(best_count)


static func get_momentum_bonus_for(chain_count: int) -> int:
	return mini(MAX_MOMENTUM_BONUS, floori(float(maxi(0, chain_count)) / 4.0) * 2)
