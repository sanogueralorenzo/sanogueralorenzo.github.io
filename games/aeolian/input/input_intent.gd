class_name InputIntent
extends RefCounted

var steer := 0.0
var tuck := 0.0
var brake := 0.0
var jump_pressed := false
var jump_held := false
var restart_pressed := false


func duplicate_intent() -> InputIntent:
	var copy := InputIntent.new()
	copy.steer = steer
	copy.tuck = tuck
	copy.brake = brake
	copy.jump_pressed = jump_pressed
	copy.jump_held = jump_held
	copy.restart_pressed = restart_pressed
	return copy
