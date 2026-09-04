extends Node3D
## Moving, map-owned cable car, one quiet van and bay birds. Never cached.
var map
var car:Node3D
var van:Node3D
var birds:Array=[]
var time=0.0
var route_time=0.0
var bells:AudioStreamPlayer3D
var sound:AudioStreamWAV
var profiling=false

func build(world) -> void:
	map=world
	profiling="--profile" in OS.get_cmdline_user_args()
	car=Node3D.new();car.name="Bay and Hill cable car";add_child(car)
	var geometry=load("res://maps/harbor_hills/geometry.gd").new(car,true)
	geometry.box(Vector3(0,.55,0),Vector3(2.25,.38,6.3),"756f52",true)
	geometry.box(Vector3(0,1.2,0),Vector3(2.1,.9,3.2),"a57353",true)
	geometry.box(Vector3(0,2.75,0),Vector3(2.55,.22,6.7),"59736b")
	geometry.box(Vector3(0,2.91,0),Vector3(2.1,.14,4.4),"687970")
	for side in [-1,1]:
		for z in [-2.6,-1.4,0,1.4,2.6]:geometry.beam(Vector3(side*1.0,.7,z),Vector3(side*1.0,2.7,z),.055,"ddc696")
		for z in [-1.0,0,1.0]:geometry.box(Vector3(side*1.07,2.03,z),Vector3(.035,.91,.85),"8ca5a0")
		geometry.box(Vector3(side*.7,.91,2.3),Vector3(.46,.15,1.3),"a9946a")
		geometry.box(Vector3(side*1.01,1.24,2.3),Vector3(.09,.65,1.4),"a9946a")
		for z in [-2.0,2.0]:geometry.add("cylinder",Vector3(side*.95,.36,z),Vector3(.57,.24,.57),"424e4c",Vector3(0,0,PI*.5))
	for side in [-1,1]:
		geometry.box(Vector3(0,1.17,side*3.0),Vector3(2.18,.6,.15),"a57353")
		geometry.box(Vector3(0,.58,side*3.28),Vector3(1.9,.13,.5),"697166")
		geometry.label("BAY & HILL",Vector3(0,2.49,side*3.08),1.6,"f3dfb0",0 if side==1 else PI)
		geometry.add("sphere",Vector3(0,1.3,side*3.12),Vector3(.25,.25,.12),"efdeb1")
	# Cream window frames, timber panels, running boards and destination fascia.
	for side in [-1,1]:
		for z in [-1.0,0,1.0]:
			for edge in [-.46,.46]:geometry.box(Vector3(side*1.105,2.03,z+edge),Vector3(.08,1.07,.055),"e0cfa5")
			for y in [1.53,2.51]:geometry.box(Vector3(side*1.11,y,z),Vector3(.09,.065,.96),"e0cfa5")
			geometry.box(Vector3(side*1.13,2.2,z-.27),Vector3(.03,.51,.11),"c0d2c8")
		for z in range(13):geometry.box(Vector3(side*1.065,1.2,-1.45+z*.24),Vector3(.035,.71,.025),"cfad78")
		geometry.box(Vector3(side*1.13,1.59,0),Vector3(.18,.12,3.35),"ddc18b")
		geometry.box(Vector3(side*1.23,.58,0),Vector3(.34,.12,5.7),"a48b60")
		geometry.box(Vector3(side*1.2,.35,2.43),Vector3(.49,.12,1.35),"606b60",true)
		geometry.box(Vector3(side*1.2,.35,-2.43),Vector3(.49,.12,1.35),"606b60",true)
		geometry.box(Vector3(side*1.29,2.72,0),Vector3(.07,.28,6.65),"c4ac7a")
		geometry.box(Vector3(side*1.34,2.73,0),Vector3(.06,.24,2.9),"597168")
		geometry.label("BAY & HILL · 07",Vector3(side*1.378,2.73,0),2.6,"f2dfb3",side*PI*.5)
		for z in [-2.65,2.65]:
			geometry.beam(Vector3(side*.94,.75,z),Vector3(side*.94,2.4,z),.035,"c6b584")
			geometry.box(Vector3(side*.68,.91,z),Vector3(.47,.13,.74),"b19b6f")
			for slat in range(3):geometry.box(Vector3(side*.99,1.1+slat*.15,z),Vector3(.055,.08,.79),"b8a174")
		for end in [-1,1]:
			geometry.beam(Vector3(side*.93,1.1,end*3.02),Vector3(side*.93,2.1,end*3.02),.037,"d3bd8c")
			geometry.beam(Vector3(side*.35,1.54,end*3.04),Vector3(side*.92,1.54,end*3.04),.035,"d3bd8c")
		for z in [-2.0,2.0]:
			geometry.box(Vector3(side*.84,.33,z),Vector3(.24,.27,1.03),"3f514d")
			geometry.add("cylinder",Vector3(side*1.09,.36,z),Vector3(.24,.045,.24),"b0ac8c",Vector3(0,0,PI*.5))
	for end in [-1,1]:
		geometry.box(Vector3(0,2.43,end*3.13),Vector3(1.86,.34,.1),"526d60")
		geometry.label("BAY & HILL",Vector3(0,2.43,end*3.2),1.65,"f3dfb0",0 if end==1 else PI)
		geometry.box(Vector3(0,.42,end*3.4),Vector3(1.35,.18,.17),"414e49")
		for side in [-1,1]:
			geometry.add("sphere",Vector3(side*.73,1.33,end*3.11),Vector3(.3,.3,.2),"d3ba84")
			geometry.add("sphere",Vector3(side*.73,1.33,end*3.22),Vector3(.2,.2,.08),"f3e6b4")
	geometry.label("07",Vector3(0,1.22,3.09),.42,"f3dfb0")
	geometry.finish()
	bells=AudioStreamPlayer3D.new();bells.name="Cable car bell";bells.max_distance=48;bells.unit_size=7;bells.volume_db=-17;car.add_child(bells)
	sound=AudioStreamWAV.new();sound.format=AudioStreamWAV.FORMAT_16_BITS;sound.mix_rate=22050
	var bytes=PackedByteArray();bytes.resize(22050*2)
	for i in 22050:
		var t=i/22050.0;var sample=(sin(TAU*1174*t)*.55+sin(TAU*2354*t)*.25+sin(TAU*3281*t)*.12)*exp(-t*6)*minf(1,t*80)
		bytes.encode_s16(i*2,int(sample*22000))
	sound.data=bytes;bells.stream=sound
	van=Node3D.new();van.name="Morning delivery";add_child(van)
	geometry=load("res://maps/harbor_hills/geometry.gd").new(van,true)
	geometry.box(Vector3(0,.9,0),Vector3(1.8,1.4,4.0),"b6ba9e",true)
	geometry.box(Vector3(0,1.3,-1.9),Vector3(1.6,.65,.04),"6d9195")
	for side in [-1,1]:
		for z in [-1.2,1.2]:geometry.add("cylinder",Vector3(side*.9,.38,z),Vector3(.65,.2,.65),"424e4c",Vector3(0,0,PI*.5))
	geometry.finish()
	for i in range(15):
		var bird=Node3D.new();add_child(bird);birds.append(bird)
		var mesh=ArrayMesh.new();var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [Vector3(0,0,.3),Vector3(-.65,.06,-.08),Vector3(0,0,-.2),Vector3(0,0,-.2),Vector3(.65,.06,-.08),Vector3(0,0,.3)]:st.add_vertex(v)
		st.generate_normals();mesh=st.commit();var n=MeshInstance3D.new();n.mesh=mesh;var material=StandardMaterial3D.new();material.albedo_color=Color("dfdfcf");material.cull_mode=BaseMaterial3D.CULL_DISABLED;n.material_override=material;bird.add_child(n)
	_update_positions()

func _physics_process(delta:float) -> void:
	time+=delta;route_time+=delta
	_update_positions()
	if int(time/23)!=int((time-delta)/23):
		bells.play()
		if profiling:print("Harbor Hills BELL route_time=",route_time," position=",car.position)
	if profiling and int(route_time/20)!=int((route_time-delta)/20):
		print("Harbor Hills TRANSIT route_time=",route_time," position=",car.position," rotation=",car.rotation_degrees)

func set_paused(value:bool) -> void:
	if is_instance_valid(bells):bells.stream_paused=value

func _update_positions() -> void:
	# Smoothly eased end stops and explicit dwell at two intermediate plazas.
	var cycle=fmod(route_time,160.0)
	var northbound=cycle<80
	var leg=fmod(cycle,80.0)
	var stops=[-100.0,-32.0,46.0,96.0] if northbound else [96.0,46.0,-32.0,-100.0]
	var z:float
	if leg<6:z=stops[0]
	elif leg<30:z=lerpf(stops[0],stops[1],(leg-6)/24.0)
	elif leg<35:z=stops[1]
	elif leg<61:z=lerpf(stops[1],stops[2],(leg-35)/26.0)
	elif leg<66:z=stops[2]
	elif leg<76:z=lerpf(stops[2],stops[3],(leg-66)/10.0)
	else:z=stops[3]
	car.position=map.point(8,z,.05)
	var grade=atan2(map.height_at(8,z+1)-map.height_at(8,z-1),2.0)
	var yaw=0.0 if northbound else PI
	if leg>76:yaw+=PI*smoothstep(76,80,leg)
	# Rotate around the grade normal, retaining rail contact throughout the turnaround.
	car.basis=Basis(Vector3.RIGHT,-grade)*Basis(Vector3.UP,yaw)
	# The single delivery van makes a slow, continuous two-way neighborhood circuit.
	var phase=time*.044
	var x=90+2.4*sin(phase)
	var z_v=14-112*cos(phase)
	var tangent=Vector2(2.4*cos(phase),112*sin(phase)).normalized()
	var slope=(map.height_at(x+tangent.x,z_v+tangent.y)-map.height_at(x-tangent.x,z_v-tangent.y))*.5
	van.position=map.point(x,z_v,.12)
	van.look_at(van.position+Vector3(tangent.x,slope,tangent.y),Vector3.UP)
	for i in birds.size():
		var a=time*(.08+i*.002)+i*.73
		birds[i].position=Vector3(cos(a)*65-25,18+sin(a*.7)*5+i*.6,-151+sin(a)*22)
		birds[i].rotation=Vector3(0,-a+PI*.5,sin(a*.8)*.2)
