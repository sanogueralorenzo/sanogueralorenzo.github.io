extends Node3D


func _ready() -> void:
	AppLog.info(&"course", "Foundation course loaded")


func shutdown() -> void:
	$Windboard/Audio.shutdown()
