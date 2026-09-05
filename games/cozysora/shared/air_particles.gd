class_name CozyAirParticles
extends Resource
## A box emitter for drifting pollen or seed heads. Profiles own artistic values.
@export var amount := 80
@export var lifetime := 14.0
@export var bounds := AABB(Vector3(-30, -2, -25), Vector3(60, 18, 50))
@export var extents := Vector3(22, 4, 20)
@export var direction := Vector3(0.8, -0.1, 0.6)
@export var spread := 20.0
@export var velocity := Vector2(0.1, 0.35)
@export var gravity := Vector3.ZERO
@export var particle_scale := Vector2(0.012, 0.027)
@export var radius := 0.5
@export var height := 1.0
@export var segments := 4
@export var rings := 2
@export var color := Color("fff3c0")
@export var double_sided := true
@export var cast_shadows := true


func install(parent: Node3D, position: Vector3) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Drifting summer air"
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.visibility_aabb = bounds
	particles.position = position
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = extents
	motion.direction = direction
	motion.spread = spread
	motion.initial_velocity_min = velocity.x
	motion.initial_velocity_max = velocity.y
	motion.gravity = gravity
	motion.scale_min = particle_scale.x
	motion.scale_max = particle_scale.y
	particles.process_material = motion
	var mesh := CozyPrimitives.sphere_mesh(radius, height, segments, rings)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	particles.draw_pass_1 = mesh
	if not cast_shadows:
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	return particles
