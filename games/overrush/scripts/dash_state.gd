class_name DashState
extends RefCounted

enum Event {
	NONE,
	STARTED,
	ENDED,
}

var minimum_duration: float
var maximum_duration: float
var cooldown: float

var is_active := false
var air_dash_available := true
var started_in_air := false
var elapsed := 0.0
var cooldown_remaining := 0.0
var _release_requested := false


func _init(minimum: float = 0.08, maximum: float = 0.24, recovery: float = 0.14) -> void:
	minimum_duration = minimum
	maximum_duration = maximum
	cooldown = recovery


func step(delta: float, pressed: bool, just_pressed: bool, grounded: bool) -> Event:
	cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
	if grounded:
		air_dash_available = true

	if is_active:
		elapsed += delta
		if not pressed:
			_release_requested = true
		if elapsed >= maximum_duration or (_release_requested and elapsed >= minimum_duration):
			is_active = false
			cooldown_remaining = cooldown
			return Event.ENDED
		return Event.NONE

	if just_pressed and cooldown_remaining <= 0.0 and (grounded or air_dash_available):
		is_active = true
		started_in_air = not grounded
		if started_in_air:
			air_dash_available = false
		elapsed = 0.0
		_release_requested = not pressed
		return Event.STARTED

	return Event.NONE


func reset() -> void:
	is_active = false
	air_dash_available = true
	started_in_air = false
	elapsed = 0.0
	cooldown_remaining = 0.0
	_release_requested = false
