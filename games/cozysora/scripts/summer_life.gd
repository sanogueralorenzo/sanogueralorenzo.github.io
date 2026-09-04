extends Node3D
## Small cream butterflies over the opening verge, and drifting summer pollen.
var creatures: Array[Dictionary]=[]
var world: Node3D
var clock:=3.0

func build(level: Node3D) -> void:
	world=level
	var rng:=RandomNumberGenerator.new()
	rng.seed=99
	var cream:=StandardMaterial3D.new()
	cream.albedo_color=Color("fff3c0")
	cream.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	cream.cull_mode=BaseMaterial3D.CULL_DISABLED
	for i in 70:
		var patch:Vector2=[Vector2(-3.3,-4.6),Vector2(-3,-6.2),Vector2(-3.4,-3.4),Vector2(-1.5,-5.5),Vector2(-10,0)][rng.randi_range(0,4)]
		var pos:=patch+Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		var body:=Node3D.new()
		add_child(body)
		var wings:Array[Node3D]=[]
		for side in [-1,1]:
			var wing:=Node3D.new()
			body.add_child(wing)
			var mesh:=PrismMesh.new()
			mesh.size=Vector3(.075,.006,.058)
			var visual:=MeshInstance3D.new()
			visual.mesh=mesh
			visual.material_override=cream
			visual.position.x=side*.038
			wing.add_child(visual)
			wings.append(wing)
		creatures.append({"body":body,"wings":wings,"home":pos,"phase":rng.randf()*100,"speed":rng.randf_range(.6,1.2)})
	var pollen:=GPUParticles3D.new()
	pollen.amount=80
	pollen.lifetime=14
	pollen.preprocess=14
	pollen.visibility_aabb=AABB(Vector3(-30,-2,-25),Vector3(60,18,50))
	pollen.position=Vector3(-6,4,-1)
	var process:=ParticleProcessMaterial.new()
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents=Vector3(22,4,20)
	process.direction=Vector3(.8,-.1,.6)
	process.spread=20
	process.initial_velocity_min=.1
	process.initial_velocity_max=.35
	process.gravity=Vector3.ZERO
	process.scale_min=.012
	process.scale_max=.027
	pollen.process_material=process
	var mote:=SphereMesh.new()
	mote.radius=.5
	mote.height=1
	mote.radial_segments=4
	mote.rings=2
	mote.material=cream
	pollen.draw_pass_1=mote
	add_child(pollen)

func _process(delta:float) -> void:
	clock+=delta
	for creature in creatures:
		var t:float=clock*creature.speed+creature.phase
		var home:Vector2=creature.home
		var x:float=home.x+sin(t*.7)*.6
		var z:float=home.y+cos(t*.5)*.6
		creature.body.position=Vector3(x,world.height_at(x,z)+.6+sin(t)*.3,z)
		creature.body.rotation=Vector3(.4,t*.5,sin(t*2)*.3)
		creature.wings[0].rotation.z=sin(clock*22+creature.phase)*.9
		creature.wings[1].rotation.z=-sin(clock*22+creature.phase)*.9
