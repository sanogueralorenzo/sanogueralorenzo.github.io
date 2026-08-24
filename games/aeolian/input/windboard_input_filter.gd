class_name WindboardInputFilter
extends RefCounted

var filtered_steer := 0.0


func reset() -> void:
	filtered_steer = 0.0


func step(
		raw: InputIntent,
		delta: float,
		is_gamepad: bool,
		sensitivity: float,
		tuning: WindboardTuning
	) -> InputIntent:
	var output := raw.duplicate_intent()
	var raw_steer := clampf(raw.steer, -1.0, 1.0) if is_finite(raw.steer) else 0.0
	var safe_sensitivity := clampf(sensitivity, 0.25, 2.0) if is_finite(sensitivity) else 1.0
	var target := 0.0
	if is_gamepad:
		target = signf(raw_steer) * pow(absf(raw_steer), tuning.analog_steer_curve_power)
		target = clampf(target * safe_sensitivity, -1.0, 1.0)
		filtered_steer = target
	else:
		target = clampf(raw_steer * safe_sensitivity, -1.0, 1.0)
		var same_direction := is_zero_approx(filtered_steer) \
			or is_zero_approx(target) \
			or signf(filtered_steer) == signf(target)
		var increasing := same_direction and absf(target) > absf(filtered_steer)
		var rate := tuning.keyboard_steer_attack_per_second if increasing \
			else tuning.keyboard_steer_release_per_second
		filtered_steer = move_toward(filtered_steer, target, rate * maxf(delta, 0.0))
	output.steer = filtered_steer
	return output
