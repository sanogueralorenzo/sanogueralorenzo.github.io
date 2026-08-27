class_name JumpAssistState
extends RefCounted

var buffer_duration := 0.13
var coyote_duration := 0.1
var buffer_remaining := 0.0
var coyote_remaining := 0.0


func configure(new_buffer_duration: float, new_coyote_duration: float) -> void:
	buffer_duration = maxf(0.0, new_buffer_duration)
	coyote_duration = maxf(0.0, new_coyote_duration)
	reset()


func reset() -> void:
	buffer_remaining = 0.0
	coyote_remaining = 0.0


func tick(delta: float, on_floor: bool) -> void:
	buffer_remaining = maxf(0.0, buffer_remaining - delta)
	if on_floor:
		coyote_remaining = coyote_duration
	else:
		coyote_remaining = maxf(0.0, coyote_remaining - delta)


func queue_jump() -> void:
	buffer_remaining = buffer_duration


func try_consume(on_floor: bool) -> bool:
	if buffer_remaining <= 0.0 or (not on_floor and coyote_remaining <= 0.0):
		return false
	buffer_remaining = 0.0
	coyote_remaining = 0.0
	return true
