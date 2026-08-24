class_name SurfaceProfile
extends Resource

@export var id: StringName = &"frost_hardpack"
@export var display_name := "Frost hardpack"
@export_range(0.1, 2.0, 0.01) var downhill_acceleration_multiplier := 1.0
@export_range(0.1, 3.0, 0.01) var drag_multiplier := 1.0
@export_range(0.05, 3.0, 0.01) var lateral_grip_multiplier := 1.0
@export_range(0.1, 3.0, 0.01) var stability_multiplier := 1.0
@export_range(0.1, 2.0, 0.01) var jump_multiplier := 1.0
@export_range(0.25, 2.0, 0.01) var landing_forgiveness_multiplier := 1.0

