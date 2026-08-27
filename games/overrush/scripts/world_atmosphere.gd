class_name WorldAtmosphere
extends Node

signal region_revealed(region_name: String, subtitle: String)

const UPDATE_INTERVAL := 0.16
const TRANSITION_SPEED := 1.35
const WEIGHT_EPSILON := 0.002

const REGION_ORDER: Array[String] = ["VERDANT REACH", "EMBER BASIN", "PRISM HIGHLANDS"]
const REGION_SUBTITLES := {
	"VERDANT REACH": "Open air • clear sightlines",
	"EMBER BASIN": "Heat haze • rising pressure",
	"PRISM HIGHLANDS": "Cold light • fractured horizon",
}
const PALETTES := [
	{
		"sky_top": Color(0.018, 0.12, 0.43),
		"sky_horizon": Color(0.18, 0.72, 0.98),
		"ground_bottom": Color(0.015, 0.025, 0.08),
		"ground_horizon": Color(0.12, 0.42, 0.52),
		"fog_color": Color(0.22, 0.58, 0.78),
		"ambient_color": Color(0.42, 0.58, 0.78),
		"sun_color": Color(1.0, 0.78, 0.58),
		"ambient_energy": 0.42,
		"fog_density": 0.00075,
		"sun_energy": 0.92,
	},
	{
		"sky_top": Color(0.035, 0.018, 0.14),
		"sky_horizon": Color(0.62, 0.14, 0.055),
		"ground_bottom": Color(0.025, 0.008, 0.035),
		"ground_horizon": Color(0.28, 0.055, 0.075),
		"fog_color": Color(0.25, 0.085, 0.14),
		"ambient_color": Color(0.36, 0.22, 0.34),
		"sun_color": Color(1.0, 0.7, 0.46),
		"ambient_energy": 0.38,
		"fog_density": 0.00088,
		"sun_energy": 0.88,
	},
	{
		"sky_top": Color(0.038, 0.018, 0.22),
		"sky_horizon": Color(0.54, 0.24, 1.0),
		"ground_bottom": Color(0.012, 0.008, 0.055),
		"ground_horizon": Color(0.2, 0.1, 0.5),
		"fog_color": Color(0.27, 0.2, 0.6),
		"ambient_color": Color(0.38, 0.31, 0.72),
		"sun_color": Color(0.76, 0.72, 1.0),
		"ambient_energy": 0.46,
		"fog_density": 0.00105,
		"sun_energy": 0.88,
	},
]

@export var runner_path: NodePath
@export var world_path: NodePath
@export var environment_path: NodePath
@export var sun_path: NodePath

var current_weights := Vector3(1.0, 0.0, 0.0)
var applied_update_count := 0

var _runner: Node3D
var _world: Node3D
var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _update_accumulator := 0.0
var _current_region := ""
var _revealed_regions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runner = get_node(runner_path)
	_world = get_node(world_path)
	_world_environment = get_node(environment_path)
	_sun = get_node(sun_path)
	_environment = _world_environment.environment
	if _environment != null and _environment.sky != null:
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
	snap_to_runner()
	_current_region = _world.get_region_name(_runner.global_position.z).to_upper()
	_revealed_regions[_current_region] = true


func _process(delta: float) -> void:
	_update_accumulator += maxf(0.0, delta)
	if _update_accumulator < UPDATE_INTERVAL:
		return
	var update_delta := _update_accumulator
	_update_accumulator = 0.0
	var target_weights: Vector3 = _world.grammar.get_region_weights(_runner.global_position.z)
	var blend := 1.0 - exp(-TRANSITION_SPEED * update_delta)
	var next_weights := current_weights.lerp(target_weights, blend)
	var weight_delta := (next_weights - current_weights).abs()
	if maxf(weight_delta.x, maxf(weight_delta.y, weight_delta.z)) >= WEIGHT_EPSILON:
		current_weights = next_weights
		_apply_state(sample_palette(current_weights))
	_update_region_reveal()


func snap_to_runner() -> void:
	if not is_instance_valid(_runner) or not is_instance_valid(_world):
		return
	current_weights = _world.grammar.get_region_weights(_runner.global_position.z)
	_apply_state(sample_palette(current_weights))


func get_current_region() -> String:
	return _current_region


static func sample_palette(weights: Vector3) -> Dictionary:
	var safe_weights := Vector3(maxf(0.0, weights.x), maxf(0.0, weights.y), maxf(0.0, weights.z))
	var total := safe_weights.x + safe_weights.y + safe_weights.z
	if total <= 0.0001:
		safe_weights = Vector3(1.0, 0.0, 0.0)
	else:
		safe_weights /= total
	var state := {}
	for key in ["sky_top", "sky_horizon", "ground_bottom", "ground_horizon", "fog_color", "ambient_color", "sun_color"]:
		state[key] = _blend_color(
			Color(PALETTES[0][key]),
			Color(PALETTES[1][key]),
			Color(PALETTES[2][key]),
			safe_weights
		)
	for key in ["ambient_energy", "fog_density", "sun_energy"]:
		state[key] = (
			float(PALETTES[0][key]) * safe_weights.x
			+ float(PALETTES[1][key]) * safe_weights.y
			+ float(PALETTES[2][key]) * safe_weights.z
		)
	return state


static func _blend_color(first: Color, second: Color, third: Color, weights: Vector3) -> Color:
	return Color(
		first.r * weights.x + second.r * weights.y + third.r * weights.z,
		first.g * weights.x + second.g * weights.y + third.g * weights.z,
		first.b * weights.x + second.b * weights.y + third.b * weights.z,
		1.0
	)


func _apply_state(state: Dictionary) -> void:
	applied_update_count += 1
	if _sky_material != null:
		_sky_material.sky_top_color = Color(state.sky_top)
		_sky_material.sky_horizon_color = Color(state.sky_horizon)
		_sky_material.ground_bottom_color = Color(state.ground_bottom)
		_sky_material.ground_horizon_color = Color(state.ground_horizon)
	if _environment != null:
		_environment.fog_light_color = Color(state.fog_color)
		_environment.fog_density = float(state.fog_density)
		_environment.ambient_light_color = Color(state.ambient_color)
		_environment.ambient_light_energy = float(state.ambient_energy)
	if is_instance_valid(_sun):
		_sun.light_color = Color(state.sun_color)
		_sun.light_energy = float(state.sun_energy)


func _update_region_reveal() -> void:
	var region_name: String = _world.get_region_name(_runner.global_position.z).to_upper()
	if region_name == _current_region:
		return
	_current_region = region_name
	if _revealed_regions.has(region_name):
		return
	_revealed_regions[region_name] = true
	region_revealed.emit(region_name, str(REGION_SUBTITLES.get(region_name, "The landscape is changing")))
