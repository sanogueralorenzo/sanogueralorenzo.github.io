extends Control

signal start_requested
signal quit_requested

@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel


func _ready() -> void:
	start_button.pressed.connect(start_requested.emit)
	quit_button.pressed.connect(quit_requested.emit)
	version_label.text = "Foundation build · v%s" % ProjectSettings.get_setting(
		"application/config/version", "unknown"
	)
	visibility_changed.connect(_focus_primary_action)
	_focus_primary_action()


func _focus_primary_action() -> void:
	if visible and is_node_ready():
		start_button.grab_focus.call_deferred()

