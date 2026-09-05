class_name CozyAtmosphere
extends Resource
## Map-owned profiles share the sky, lighting, ocean and painterly presentation.
@export var ambient_color := Color("7fb0d8")
@export var ambient_energy := 0.52
@export var fog_color := Color("c9d6de")
@export var fog_begin := 40.0
@export var fog_end := 260.0
@export var fog_curve := 1.0
@export var fog_sky := 0.1
@export var sun_color := Color("ffcf9c")
@export var sun_energy := 1.15
@export var shadow_distance := 110.0
@export var shadow_normal_bias := 0.7
@export var sun_position := Vector3(-66, 84, -45.6)
@export var sun_rotation_degrees := Vector3.ZERO
@export var aim_sun_at_origin := true
@export var fill_color := Color("c9d6ec")
@export var fill_energy := 0.25
@export var fill_position := Vector3(60, 50, 90)
@export var ocean_size := Vector2(4000, 4000)
@export var ocean_position := Vector3(0, -30, 0)
@export var brush_radius := 4.0


func install(parent: Node3D) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	environment.environment = env
	parent.add_child(environment)
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = fog_color
	env.fog_depth_begin = fog_begin
	env.fog_depth_end = fog_end
	env.fog_depth_curve = fog_curve
	env.fog_sky_affect = fog_sky
	var sun := DirectionalLight3D.new()
	sun.name = "SummerSun"
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = shadow_distance
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = shadow_normal_bias
	parent.add_child(sun)
	if aim_sun_at_origin:
		sun.position = sun_position
		sun.look_at(Vector3.ZERO)
	else:
		sun.rotation_degrees = sun_rotation_degrees
	if fill_energy > 0:
		var fill := DirectionalLight3D.new()
		fill.light_color = fill_color
		fill.light_energy = fill_energy
		parent.add_child(fill)
		fill.position = fill_position
		fill.look_at(Vector3.ZERO)
	var plane := PlaneMesh.new()
	plane.size = ocean_size
	var water := ShaderMaterial.new()
	water.shader = preload("res://shaders/ocean.gdshader")
	CozyPrimitives.instance(parent, plane, ocean_position, water)


func install_post(parent: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var effect := ShaderMaterial.new()
	effect.shader = preload("res://shaders/paint.gdshader")
	effect.set_shader_parameter("brush_radius", brush_radius)
	rect.material = effect
	layer.add_child(rect)
	parent.add_child(layer)
