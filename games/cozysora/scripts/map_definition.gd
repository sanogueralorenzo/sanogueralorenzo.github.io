class_name CozyMapDefinition
extends Resource
## Editor-friendly destination metadata. Scenes are loaded only after selection.
@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var subtitle: String
@export_file("*.tscn") var scene: String
@export var preview: Texture2D
@export var spawn_position := Vector3.ZERO
@export var spawn_yaw := 0.0
@export var spawn_pitch := 0.09
@export_enum("cat", "gull") var spawn_mode := "cat"

func spawn() -> Dictionary:
	return {"position":spawn_position,"yaw":spawn_yaw,"pitch":spawn_pitch,"mode":spawn_mode}
