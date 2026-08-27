class_name RunOnboarding
extends RefCounted

const STEER := 0
const DASH := 1
const HOP := 2
const THREATS := 3
const BUILD := 4
const OBJECTIVE := 5
const COMPLETE := 6
const AUTOMATIC_ADVANCE_SECONDS := 8.0
const INFORMATION_ADVANCE_SECONDS := 6.0

var step := STEER
var step_elapsed := 0.0
var _seen_steer := false
var _seen_dash := false
var _seen_hop := false


func reset(already_completed: bool = false) -> void:
	step = COMPLETE if already_completed else STEER
	step_elapsed = 0.0
	_seen_steer = false
	_seen_dash = false
	_seen_hop = false


func update(delta: float, steering: bool, dashing: bool, hopping: bool) -> bool:
	if step == COMPLETE:
		return false
	_seen_steer = _seen_steer or steering
	_seen_dash = _seen_dash or dashing
	_seen_hop = _seen_hop or hopping
	step_elapsed += maxf(0.0, delta)
	var previous_step := step
	if step == STEER and (_seen_steer or step_elapsed >= AUTOMATIC_ADVANCE_SECONDS):
		_advance()
	if step == DASH and (_seen_dash or step_elapsed >= AUTOMATIC_ADVANCE_SECONDS):
		_advance()
	if step == HOP and (_seen_hop or step_elapsed >= AUTOMATIC_ADVANCE_SECONDS):
		_advance()
	if step in [THREATS, BUILD, OBJECTIVE] and step_elapsed >= INFORMATION_ADVANCE_SECONDS:
		_advance()
	return step != previous_step


func get_message(gamepad: bool = false) -> String:
	match step:
		STEER:
			return "STEER THE RUN  •  LEFT STICK\nYou move automatically. Choose open ground and keep velocity." if gamepad else "STEER THE RUN  •  A / D OR ← / →\nYou move automatically. Choose open ground and keep velocity."
		DASH:
			return "DASH THROUGH PRESSURE  •  LB / RB\nTap for a burst, hold for distance. Your air dash refreshes on landing." if gamepad else "DASH THROUGH PRESSURE  •  SHIFT / ALT\nTap for a burst, hold for distance. Your air dash refreshes on landing."
		HOP:
			return "HOP THE TERRAIN  •  A\nWeapons fire automatically. Bright shards level you; coral cores repair integrity." if gamepad else "HOP THE TERRAIN  •  SPACE\nWeapons fire automatically. Bright shards level you; coral cores repair integrity."
		THREATS:
			return "READ THE GROUND\nLeave marked zones before they trigger. Dashing briefly prevents damage."
		BUILD:
			return "BUILD FOR A PLAN\nDrafts pause play. Commit to an engine, evolve it, then add an arsenal."
		OBJECTIVE:
			return "BREAK THE APEX\nAt 18:00, destroy it before the 20:00 deadline. Survival alone is not victory."
		_:
			return ""


func is_complete() -> bool:
	return step == COMPLETE


func _advance() -> void:
	step = mini(step + 1, COMPLETE)
	step_elapsed = 0.0
