extends Node3D

@onready var player: WindboardController = %Windboard
@onready var recovery_prompt: Label = %RecoveryPrompt
@onready var crash_center: CenterContainer = %CrashCenter
@onready var crash_reason: Label = %CrashReason
@onready var completion_center: CenterContainer = %CompletionCenter
@onready var completion_summary: Label = %CompletionSummary

var _last_stability_percent := -1
var _run_start_tick := 0
var _previous_player_position := Vector3.ZERO
var _finish_gate_resolved := false


func _ready() -> void:
	AppLog.info(&"course", "Foundation course loaded")
	player.crashed.connect(_on_player_crashed)
	player.respawned.connect(_on_player_respawned)
	player.descent_finished.connect(_on_player_finished)
	_run_start_tick = player.physics_tick
	_previous_player_position = player.global_position


func _physics_process(_delta: float) -> void:
	if player.motion_state == WindboardController.MotionState.CRASHED \
			or player.motion_state == WindboardController.MotionState.FINISHED:
		return
	var current_position := player.global_position
	var previous_distance := -_previous_player_position.z
	var downhill_distance := -current_position.z
	if not _finish_gate_resolved \
			and previous_distance < MovementCourseGeometry.FINISH_TRIGGER_D \
			and downhill_distance >= MovementCourseGeometry.FINISH_TRIGGER_D:
		_finish_gate_resolved = true
		var crossing_fraction := inverse_lerp(
			previous_distance,
			downhill_distance,
			MovementCourseGeometry.FINISH_TRIGGER_D
		)
		var crossing_x := lerpf(
			_previous_player_position.x,
			current_position.x,
			clampf(crossing_fraction, 0.0, 1.0)
		)
		if crossing_x >= MovementCourseGeometry.FINISH_MIN_X \
				and crossing_x <= MovementCourseGeometry.FINISH_MAX_X:
			var elapsed_seconds := float(player.physics_tick - _run_start_tick) \
				/ float(Engine.physics_ticks_per_second)
			_previous_player_position = current_position
			player.finish_descent({
				"elapsed_seconds": elapsed_seconds,
				"entry_speed_mps": player.motion_model.velocity.length(),
				"lane_x": crossing_x,
			})
			return
	if downhill_distance > MovementCourseGeometry.COURSE_END_D + 0.25:
		player.crash_from_hazard(&"missed_finish", {
			"distance": downhill_distance,
			"lane_x": player.global_position.x,
		})
	_previous_player_position = current_position


func _process(_delta: float) -> void:
	if player.motion_state == WindboardController.MotionState.CRASHED \
			or player.motion_state == WindboardController.MotionState.FINISHED:
		recovery_prompt.hide()
		return
	var stability_percent := roundi(player.motion_model.stability * 100.0)
	if stability_percent != _last_stability_percent:
		_last_stability_percent = stability_percent
		recovery_prompt.text = \
			"UNSTABLE · %d%% · HOLD SPACE / A TO RECOVER" % stability_percent
	recovery_prompt.visible = player.motion_model.stability < 0.92


func shutdown() -> void:
	$Windboard/Audio.shutdown()


func _on_player_crashed(cause: StringName, _details: Dictionary) -> void:
	completion_center.hide()
	crash_reason.text = _crash_reason_label(cause)
	crash_center.show()
	recovery_prompt.hide()


func _on_player_respawned(_count: int) -> void:
	crash_center.hide()
	completion_center.hide()
	recovery_prompt.hide()
	_last_stability_percent = -1
	_run_start_tick = player.physics_tick
	_previous_player_position = player.global_position
	_finish_gate_resolved = false


func _on_player_finished(details: Dictionary) -> void:
	crash_center.hide()
	recovery_prompt.hide()
	completion_summary.text = "MOVEMENT COURSE CLEARED · %.2f S" % \
		float(details.get("elapsed_seconds", 0.0))
	completion_center.show()


func _crash_reason_label(cause: StringName) -> String:
	match cause:
		&"wall_impact":
			return "IMPACT TOO HARD"
		&"terminal_landing":
			return "LANDING LOST"
		&"stability_exhausted":
			return "LOST CONTROL"
		&"missed_finish":
			return "MISSED FINISH GATE"
	return "DESCENT ENDED"
