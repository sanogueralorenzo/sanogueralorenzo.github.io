extends "res://scripts/three_d/coast.gd"
## A sheltered fishing quay. Reuses only the project's scenery construction tools.
var evening:=false
var lantern_materials:Array[StandardMaterial3D]=[]
var beacon:OmniLight3D

func _ready() -> void:
	rng.seed=9237
	make_foliage()
	G.box(self,Vector3(4,-0.20,-15.5),Vector3(31,0.7,12),mat("b8b39b",5,0.2))
	G.box(self,Vector3(4,-2.6,-15.5),Vector3(31,4.6,12),mat("8b9c95",2,0.22))
	for x in range(-9,20,2):
		G.box(self,Vector3(x,0.22,-10),Vector3(1.8,0.16,0.7),mat("d0c4a5",2))
	# Low maritime buildings leave an open view toward the lighthouse and water.
	warehouse(Vector3(0.5,0.15,-18.4),Vector3(7.2,5.2,6.5),"d3bda3","MARÉ • SAIL LOFT",false)
	warehouse(Vector3(9.3,0.15,-19),Vector3(6.6,6.4,7),"b6c4b8","PORTO POSTALE",true)
	warehouse(Vector3(17.2,0.15,-23),Vector3(6.3,7.4,7),"c99d87","",true)
	G.box(self,Vector3(-15.6,-2.4,-33),Vector3(22,5.0,5),mat("94a299",2,0.22))
	G.box(self,Vector3(-19.6,-2.4,-40.0),Vector3(5.4,5.0,19.0),mat("94a299",2,0.22))
	lighthouse(Vector3(-19.6,0.1,-47.0))
	for x in range(-25,-5,3):
		G.beam(self,Vector3(x,0.1,-30.4),Vector3(x,0.83,-30.4),0.10,mat("b9b99f"),0.08)
		G.sphere(self,Vector3(x,0.89,-30.4),Vector3.ONE*.12,mat("d8cfb2"))
	# Moorings, a timber landing and tied fishing skiffs give the quay depth.
	for i in range(3):
		var p:=Vector3(-19.7-i*5.3,-4.7,-18-i*9.8)
		fishing_boat(p,1.35+i*.24,["597d80","b57354","d0b368"][i])
	for j in range(13):
		G.box(self,Vector3(-11.0,-3.05,-8.9-j*.38),Vector3(4.9,.13,.34),mat("a39776",1,0.2))
	for x in [-13.2,-9.0]:
		for z in [-9.0,-13.4]: G.beam(self,Vector3(x,-5,z),Vector3(x,-2.65,z),.13,mat("776f58",6),.11)
	stairs(Vector3(-7.4,-3.0,-8.8),14,.22,.42,1.4)
	for z in [-8,-3,2,7]:
		for side in [-1,1]:
			bollard(Vector3(side*6.9,.03,z))
			planter(Vector3(side*6.7,.04,z+1.3),.30,.35,true)
	for p in [Vector3(-6,.2,-11),Vector3(5,.2,-11),Vector3(13,.2,-12)]:
		bench(p)
		lamp(p+Vector3(1.1,0,-.6))
	for i in range(6):
		var p:=Vector3(4.6+i*.64,.15,-13.2-(i%2)*.8)
		crate(p,Vector3(.56,.48+(i%3)*.15,.56))
	life_ring(Vector3(6.8,1.0,-1.5))
	string_lights(Vector3(-7.0,5.4,-11.0),Vector3(13.0,6.7,-11.0),15)
	tree(Vector3(8.3,0,6.5),1.16)
	tree(Vector3(8.8,0,-4),.94)
	tree(Vector3(-8.5,0,6),1.06)
	tree(Vector3(13.2,.1,-12.6),.83)
	headland(Vector3(-63,-5,-133),1.2,"638a92")
	headland(Vector3(-95,-5,-190),1.4,"8ca6ac")
	boat(Vector3(-43,-4.8,-64),1.4)
	batch_static()

func warehouse(p:Vector3,size:Vector3,color:String,sign_text:String,shutters:bool) -> void:
	G.box(self,p+Vector3(0,size.y/2,0),size,mat(color,0,.15))
	G.box(self,p+Vector3(0,.20,0),Vector3(size.x+.2,.4,size.z+.2),mat("939c8b",2))
	G.box(self,p+Vector3(0,size.y,0),Vector3(size.x+.3,.18,size.z+.3),mat("ecddbd"))
	roof(p+Vector3(0,size.y+.08,0),size.x+.6,size.z+.6,1.1)
	var front:=p+Vector3(0,0,size.z/2+.04)
	for x in [-size.x*.32,0,size.x*.32]:
		window(front+Vector3(x,size.y-1.3,0),shutters)
		if size.y>6: window(front+Vector3(x,size.y-3.3,0),not shutters)
	for x in [-size.x*.49,size.x*.49]: G.box(self,front+Vector3(x,size.y*.5,0),Vector3(.16,size.y,.07),mat("e6d8b9"))
	G.box(self,front+Vector3(0,1.25,.01),Vector3(2.0,2.5,.08),mat("45696a",6,.18))
	for x in [-1.05,1.05]: G.box(self,front+Vector3(x,1.25,.07),Vector3(.13,2.65,.13),mat("e7d6b7"))
	G.box(self,front+Vector3(0,2.57,.07),Vector3(2.23,.13,.13),mat("e7d6b7"))
	G.box(self,front+Vector3(0,2.98,.15),Vector3(size.x*.87,.54,.16),mat("3f6366"))
	if not sign_text.is_empty(): G.text(self,sign_text,front+Vector3(0,2.98,.25),40,.010,Color("f3dfb4"),true)
	for x in [-size.x*.32,size.x*.32]:
		G.box(self,front+Vector3(x,1.1,0),Vector3(.84,1.4,.04),mat("375d64"))
		G.box(self,front+Vector3(x,.36,.15),Vector3(1,.13,.36),mat("c7ba99"))
		planter(front+Vector3(x,.43,.14),.22,.25,true)
	# Visible side battens and windows, not featureless end walls.
	for z in [-size.z*.27,size.z*.20]:
		G.box(self,p+Vector3(-size.x/2-.04,2.7,z),Vector3(.08,1.3,.9),mat("47696d"))
		for dz in [-.51,.51]: G.box(self,p+Vector3(-size.x/2-.08,2.7,z+dz),Vector3(.08,1.45,.07),mat("e2d3b5"))

func lighthouse(p:Vector3) -> void:
	var tower:=Node3D.new()
	tower.position=p
	tower.scale=Vector3.ONE*.78
	add_child(tower)
	p=Vector3.ZERO
	G.beam(tower,p,p+Vector3(0,1.0,0),2.65,mat("b4ae95",2),2.45,32)
	G.beam(tower,p+Vector3(0,1,0),p+Vector3(0,11,0),1.55,mat("e3d6b9",0,.14),1.02,40)
	for y in [3.5,6.9]: G.beam(tower,p+Vector3(0,y,0),p+Vector3(0,y+.68,0),1.57-(y-1)*.053,mat("bd856e"),1.57-(y-.32)*.053,40)
	G.box(tower,p+Vector3(0,2,1.43),Vector3(.58,1.8,.06),mat("496769"))
	for y in [5.0,8.1]: G.box(tower,p+Vector3(0,y,1.30-y*.035),Vector3(.30,.62,.08),mat("536f72"))
	G.beam(tower,p+Vector3(0,10.8,0),p+Vector3(0,11.02,0),1.65,mat("d6cdb3"),1.65,40)
	G.beam(tower,p+Vector3(0,11.05,0),p+Vector3(0,12.5,0),.91,mat("78928d"),.91,16)
	for j in range(12):
		var direction:=Vector3(cos(j*TAU/12),0,sin(j*TAU/12))
		G.beam(tower,p+direction*1.52+Vector3(0,11,0),p+direction*1.52+Vector3(0,11.7,0),.025,mat("3e5b5e"))
		G.beam(tower,p+direction*.94+Vector3(0,11,0),p+direction*.94+Vector3(0,12.5,0),.04,mat("3e5b5e"))
	var rim:=TorusMesh.new(); rim.inner_radius=1.48; rim.outer_radius=1.54
	G.instance(tower,rim,p+Vector3(0,11.72,0),mat("3e5b5e"))
	G.beam(tower,p+Vector3(0,12.5,0),p+Vector3(0,13.5,0),1.25,mat("678080"),.03,16)
	G.beam(tower,p+Vector3(0,13.5,0),p+Vector3(0,14.15,0),.04,mat("3e5b5e"))
	beacon=OmniLight3D.new(); beacon.position=p+Vector3(0,11.8,0); beacon.light_color=Color("ffcd82"); beacon.light_energy=2 if evening else 0; beacon.omni_range=8; tower.add_child(beacon)

	G.merge_static(tower)

func fishing_boat(p:Vector3,size_scale:float,color:String) -> void:
	var mesh:=G.profile([Vector3(-.3,.55,1.9),Vector3(-.12,.83,2.3),Vector3(.36,1.0,2.65),Vector3(.43,.98,2.6)],32)
	var hull:=G.instance(self,mesh,p,mat(color,1,.18)); hull.scale=Vector3.ONE*size_scale
	G.box(self,p+Vector3(0,.35,0)*size_scale,Vector3(1.65,.08,3.65)*size_scale,mat("b8a784",1))
	G.box(self,p+Vector3(0,.81,-.55)*size_scale,Vector3(1.35,.95,1.5)*size_scale,mat("e3d7bd"))
	G.box(self,p+Vector3(0,1.35,-.55)*size_scale,Vector3(1.62,.12,1.8)*size_scale,mat("68898a"))
	G.box(self,p+Vector3(0,.98,.22)*size_scale,Vector3(.97,.48,.04)*size_scale,mat("3d6472"))
	G.beam(self,p+Vector3(0,.4,-1.4)*size_scale,p+Vector3(0,3.8,-1.4)*size_scale,.04*size_scale,mat("8c8267"))
	G.beam(self,p+Vector3(0,3,-1.4)*size_scale,p+Vector3(.7,2.8,1.0)*size_scale,.025*size_scale,mat("8c8267"))
	for side in [-1,1]:
		for z in [-1.4,.2,1.3]: G.sphere(self,p+Vector3(side*.98,.26,z)*size_scale,Vector3(.12,.24,.12)*size_scale,mat("e9ddc0"))

func bollard(p:Vector3) -> void:
	G.beam(self,p,p+Vector3(0,.55,0),.13,mat("405d5d"),.10)
	G.beam(self,p+Vector3(-.19,.45,0),p+Vector3(.19,.45,0),.06,mat("405d5d"))
	for y in [.17,.22,.27]:
		var coil:=TorusMesh.new(); coil.inner_radius=.115; coil.outer_radius=.145; coil.rings=16
		G.instance(self,coil,p+Vector3(0,y,0),mat("c6b28c"))

func crate(p:Vector3,size:Vector3) -> void:
	G.box(self,p+Vector3(0,size.y/2,0),size,mat("af946a",1,.2))
	for x in [-size.x*.42,size.x*.42]: G.box(self,p+Vector3(x,size.y/2,size.z/2+.02),Vector3(.07,size.y,.035),mat("d1b88b"))

func life_ring(p:Vector3) -> void:
	var mesh:=TorusMesh.new(); mesh.inner_radius=.24; mesh.outer_radius=.38; mesh.rings=32
	var ring:=G.instance(self,mesh,p,mat("deb78a")); ring.rotation.z=PI/2

func lamp(p:Vector3) -> void:
	G.beam(self,p,p+Vector3(0,3.7,0),.07,mat("405b5b"),.045)
	G.beam(self,p+Vector3(0,3.7,0),p+Vector3(-.4,3.7,0),.035,mat("405b5b"))
	lantern(p+Vector3(-.4,3.32,0),.26)

func lantern(p:Vector3,size:float) -> void:
	var glass:=G.matte(Color("ebd4a2")); glass.emission_enabled=evening; glass.emission=Color("ffcc7d"); glass.emission_energy_multiplier=.6
	lantern_materials.append(glass)
	G.box(self,p,Vector3(size*.72,size,size*.72),glass)
	for y in [-.56,.56]: G.box(self,p+Vector3(0,size*y,0),Vector3(size,size*.12,size),mat("405b5b"))
	for x in [-.42,.42]:
		for z in [-.42,.42]: G.beam(self,p+Vector3(x,-.5,z)*size,p+Vector3(x,.5,z)*size,.012,mat("405b5b"))

func string_lights(a:Vector3,b:Vector3,count:int) -> void:
	for i in range(count):
		var t:=float(i)/count; var next:=float(i+1)/count
		var p:=a.lerp(b,t)-Vector3(0,sin(t*PI)*1.0,0)
		var q:=a.lerp(b,next)-Vector3(0,sin(next*PI)*1.0,0)
		G.beam(self,p,q,.012,mat("67736a"),.012,6)
		if i>0: lantern(p-Vector3(0,.16,0),.21)

func set_evening(value:bool) -> void:
	evening=value
	for glass in lantern_materials: glass.emission_enabled=value
	if is_instance_valid(beacon): beacon.light_energy=2 if value else 0
