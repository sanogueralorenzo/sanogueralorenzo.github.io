class_name WorldBoundary
extends Node

const BoundaryCurrentModel = preload("res://scripts/boundary_current.gd")
const EMERGENCY_INSET := 24.0

@export var runner_path: NodePath
@export var world_path: NodePath

var pressure := 0.0
var bank_label := ""
var emergency_recoveries := 0

var _runner: CharacterBody3D
var _world: Node3D
var _guidance := BoundaryCurrentModel.new()
var _sample := BoundaryCurrentModel.Sample.new()
var _turn_bias := 1.0


func _ready() -> void:
	_runner = get_node(runner_path)
	_world = get_node(world_path)
	_turn_bias = 1.0 if (int(_world.generated_seed) & 1) == 0 else -1.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_runner) or not is_instance_valid(_world):
		return
	var half_extent: float = _world.map_size * 0.5
	_guidance.sample(
		_runner.global_position,
		_runner.heading,
		_runner.get_horizontal_speed(),
		half_extent,
		_turn_bias,
		_sample
	)
	pressure = _sample.pressure
	bank_label = _sample.bank_label
	if pressure > 0.0:
		var guided_heading: Vector3 = _guidance.guide_heading(_runner.heading, _sample, delta)
		_runner.apply_boundary_heading(guided_heading)
	_apply_emergency_inset(half_extent)


func get_warning_text() -> String:
	if pressure < 0.12:
		return ""
	return "JETSTREAM  •  %s" % bank_label


func _apply_emergency_inset(half_extent: float) -> void:
	var limit := half_extent - EMERGENCY_INSET
	var position := _runner.global_position
	if absf(position.x) <= limit and absf(position.z) <= limit:
		return
	position.x = clampf(position.x, -limit, limit)
	position.z = clampf(position.z, -limit, limit)
	position.y = maxf(position.y, _world.get_surface_height(position.x, position.z) + 2.0)
	_runner.global_position = position
	var inward := Vector3(-position.x, 0.0, -position.z).normalized()
	_runner.apply_boundary_heading(_runner.heading.slerp(inward, 0.48).normalized())
	emergency_recoveries += 1
