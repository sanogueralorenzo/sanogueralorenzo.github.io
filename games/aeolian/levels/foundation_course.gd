extends Node3D

@onready var player: WindboardController = %Windboard
@onready var recovery_prompt: Label = %RecoveryPrompt
@onready var crash_center: CenterContainer = %CrashCenter
@onready var crash_reason: Label = %CrashReason

var _last_stability_percent := -1


func _ready() -> void:
	AppLog.info(&"course", "Foundation course loaded")
	player.crashed.connect(_on_player_crashed)
	player.respawned.connect(_on_player_respawned)


func _process(_delta: float) -> void:
	if player.motion_state == WindboardController.MotionState.CRASHED:
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
	crash_reason.text = _crash_reason_label(cause)
	crash_center.show()
	recovery_prompt.hide()


func _on_player_respawned(_count: int) -> void:
	crash_center.hide()
	recovery_prompt.hide()
	_last_stability_percent = -1


func _crash_reason_label(cause: StringName) -> String:
	match cause:
		&"wall_impact":
			return "IMPACT TOO HARD"
		&"terminal_landing":
			return "LANDING LOST"
		&"stability_exhausted":
			return "LOST CONTROL"
	return "DESCENT ENDED"
