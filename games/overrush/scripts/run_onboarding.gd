class_name RunOnboarding
extends RefCounted

const STEER := 0
const DASH := 1
const HOP := 2
const FLOW := 3
const THREATS := 4
const BUILD := 5
const OBJECTIVE := 6
const COMPLETE := 7
const AUTOMATIC_ADVANCE_SECONDS := 8.0
const INFORMATION_ADVANCE_SECONDS := 6.0

var step := STEER
var step_elapsed := 0.0
var _seen_movement := false
var _seen_dash := false
var _seen_hop := false


func reset(already_completed: bool = false) -> void:
	step = COMPLETE if already_completed else STEER
	step_elapsed = 0.0
	_seen_movement = false
	_seen_dash = false
	_seen_hop = false


func update(delta: float, movement_input: bool, dashing: bool, hopping: bool) -> bool:
	if step == COMPLETE:
		return false
	_seen_movement = _seen_movement or movement_input
	_seen_dash = _seen_dash or dashing
	_seen_hop = _seen_hop or hopping
	step_elapsed += maxf(0.0, delta)
	var previous_step := step
	if step == STEER and (_seen_movement or step_elapsed >= AUTOMATIC_ADVANCE_SECONDS):
		_advance()
	if step == DASH and (_seen_dash or step_elapsed >= AUTOMATIC_ADVANCE_SECONDS):
		_advance()
	if step == HOP and (_seen_hop or step_elapsed >= AUTOMATIC_ADVANCE_SECONDS):
		_advance()
	if step in [FLOW, THREATS, BUILD, OBJECTIVE] and step_elapsed >= INFORMATION_ADVANCE_SECONDS:
		_advance()
	return step != previous_step


func get_message(gamepad: bool = false) -> String:
	match step:
		STEER:
			return "MOVE AND LOOK  •  LEFT + RIGHT STICKS\nMove in any direction; rotate the camera independently." if gamepad else "MOVE AND LOOK  •  WASD + MOUSE\nMove in any direction; rotate the camera independently."
		DASH:
			return "DASH THROUGH PRESSURE  •  LB / RB\nTap for a burst, hold for distance. Your air dash refreshes on landing." if gamepad else "DASH THROUGH PRESSURE  •  SHIFT / ALT\nTap for a burst, hold for distance. Your air dash refreshes on landing."
		HOP:
			return "HOP THE TERRAIN  •  A\nWeapons fire automatically. Bright shards level you; coral cores repair integrity." if gamepad else "HOP THE TERRAIN  •  SPACE\nWeapons fire automatically. Bright shards level you; coral cores repair integrity."
		FLOW:
			return "CHAIN THE FLOW\nDefeat threats above 52 m/s. Dashes extend time; best Flow banks Momentum."
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
