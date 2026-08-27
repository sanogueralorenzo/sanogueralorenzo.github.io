class_name AirBoostState
extends RefCounted

var available := true
var airborne := false


func reset_on_sand() -> void:
	available = true
	airborne = false


func leave_surface() -> void:
	airborne = true


func try_use() -> bool:
	if not airborne or not available:
		return false
	available = false
	return true


func land(valid_sand: bool) -> bool:
	airborne = false
	if not valid_sand:
		return false
	var refreshed := not available
	available = true
	return refreshed
