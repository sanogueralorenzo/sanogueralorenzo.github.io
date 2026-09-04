class_name CozySettlements
extends Node3D
## Procedural buildings, village props, farmland, and railway for Cozy Sora.
var w: Node3D
var rng := RandomNumberGenerator.new()
var textures := {}
var train_cars: Array[Node3D] = []
var track := Curve3D.new()
var butterflies: Array[Node3D] = []
var elapsed := 3.0
var train_start := .92

func build(world: Node3D) -> void:
	w = world
	rng.seed = 808
	farm()
	await get_tree().process_frame
	village()
	await get_tree().process_frame
	shrine()
	await get_tree().process_frame
	paddies()
	await get_tree().process_frame
	vending_area()
	await get_tree().process_frame
	railway()
	await get_tree().process_frame
	consolidate_static_meshes()

func m(hex: String) -> StandardMaterial3D:
	return w.mat(hex)

func b(p: Node3D, pos: Vector3, size: Vector3, color: Variant, collision := false) -> MeshInstance3D:
	return w.box(p, pos, size, m(color) if color is String else color, collision)

func c(p: Node3D, pos: Vector3, r: float, h: float, color: String, top := -1.0) -> MeshInstance3D:
	return w.cylinder(p, pos, r, r if top < 0 else top, h, m(color))

func group(x: float, z: float, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(x, w.height_at(x,z), z)
	n.rotation.y = yaw
	return n

func line(p: Node3D, a: Vector3, q: Vector3, thickness: float, color: String) -> void:
	if color == "#79573d":
		var length:float=a.distance_to(q)
		var frame:=Node3D.new()
		p.add_child(frame)
		frame.position=(a+q)*.5
		frame.quaternion=Quaternion(Vector3.UP,(q-a).normalized())
		if thickness<=.18 and length>3:
			b(frame,Vector3.ZERO,Vector3(thickness*1.8,length,.16),surface("paint",color))
			for side in [-1,1]:
				b(frame,Vector3(side*thickness*.82,0,0),Vector3(.065,length,.11),surface("paint",color))
			var sections:int=ceili(length/.60)
			for i in sections:
				var y0:float=-length*.5+length*i/sections
				var y1:float=-length*.5+length*(i+1)/sections
				var side:float=-1 if i%2==0 else 1
				var begin:=Vector3(side*thickness*.82,y0,0)
				var end:=Vector3(-side*thickness*.82,y1,0)
				var web:=b(frame,(begin+end)*.5,Vector3(.045,begin.distance_to(end),.045),m("#664938"))
				web.quaternion=Quaternion(Vector3.UP,(end-begin).normalized())
		else:
			b(frame,Vector3.ZERO,Vector3(thickness*2,length,thickness*2),surface("paint",color))
	else:
		w.beam(p,a,q,thickness,m(color))

func surface(kind: String, tint: String) -> StandardMaterial3D:
	var key := kind+tint
	if textures.has(key): return textures[key]
	var im := Image.create(128,128,false,Image.FORMAT_RGB8)
	var base := Color(tint)
	var noise := RandomNumberGenerator.new()
	noise.seed = 417+kind.hash()
	for y in 128:
		for x in 128:
			var f := noise.randf_range(.94,1.05)
			if kind == "wood":
				f *= .55 if x%8 < 1 else 1.0
				f += sin(float(y)*.19+sin(float(x)*2.7))*.035
			elif kind == "pole":
				f *= .88+sin(float(x)*2.4)*.08
				if y%29<2: f*=.8
			elif kind == "bamboo":
				f *= .55 if y%4==0 else 1.0
				f *= .75 if x%42<2 else 1.0
			elif kind == "metal":
				f *= (.84+sin(float(x%8)*PI/4.0)*.13)*.58
			elif kind == "tile":
				f *= .34 if y%32<6 else 1.0
				f *= .85+sin(float(x%16)*PI/16.0)*.2
			elif kind == "paint":
				f *= .9+sin(float(x)*.08+sin(float(y)*.05)*2)*.05
				if noise.randf()<.025: f*=.64
			elif kind == "stone":
				f *= .70 if y%32<2 or (x+(y/32)*16)%48<2 else 1.0
			im.set_pixel(x,y,Color(base.r*f,base.g*f,base.b*f))
	if kind == "stone": rock_pattern(im,base,noise)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(im)
	mat.roughness = .93
	mat.uv1_scale = Vector3(2,2,2)
	textures[key] = mat
	return mat

func roof(p: Node3D, center: Vector3, width: float, depth: float, rise: float, tint := "#515a60", hip := false, curved := 0.0, trim_tint := "") -> Node3D:
	var n := Node3D.new()
	p.add_child(n)
	n.position = center
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim := tint if trim_tint.is_empty() else trim_tint
	var half := width*.5
	var ridge := maxf(.25,half-depth*.5) if hip else half
	# Build the curved roof profile in two dimensions: the corners turn upward
	# more strongly than the center of an eave, which keeps the Japanese silhouette.
	for side in [-1.0,1.0]:
		for j in 10:
			for ix in 10:
				var t0:=j/10.0
				var t1:=(j+1)/10.0
				var u0:=-1.0+ix*.2
				var u1:=u0+.2
				var a:=roof_point(half,ridge,depth,rise,curved,side,t0,u0,hip)
				var q:=roof_point(half,ridge,depth,rise,curved,side,t0,u1,hip)
				var d:=roof_point(half,ridge,depth,rise,curved,side,t1,u1,hip)
				var e:=roof_point(half,ridge,depth,rise,curved,side,t1,u0,hip)
				if side>0: quad(mesh,a,q,d,e)
				else: quad(mesh,q,a,e,d)
	if hip:
		triangle(mesh,Vector3(half,0,-depth*.5),Vector3(half,0,depth*.5),Vector3(ridge,rise,0))
		triangle(mesh,Vector3(-half,0,depth*.5),Vector3(-half,0,-depth*.5),Vector3(-ridge,rise,0))
	elif curved<=1.2:
		for sx in [-1,1]:
			triangle(mesh,Vector3(sx*half,0,-depth*.5),Vector3(sx*half,0,depth*.5),Vector3(sx*half,rise,0))
	mesh.generate_normals()
	var roofmesh := MeshInstance3D.new()
	roofmesh.mesh = mesh.commit()
	var mat := surface("tile",tint)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	roofmesh.material_override = mat
	n.add_child(roofmesh)
	b(n,Vector3(0,rise+.07,0),Vector3(ridge*2+.12,.19,.23),trim)
	for side in [-1,1]:
		b(n,Vector3(0,-.065,side*depth*.5),Vector3(width+.06,.16,.16),trim)
		# Cylindrical rolled tiles along the visible eaves.
		for i in range(int(width/.28)):
			var edge := c(n,Vector3(-half+.14+i*.28,.015,side*(depth*.5-.09)),.075,.32,tint)
			edge.rotation.x = PI/2
	return n

func triangle(st: SurfaceTool, a: Vector3, q: Vector3, d: Vector3) -> void:
	for v in [a,q,d]:
		st.set_uv(Vector2(v.x,v.z)*.4)
		st.add_vertex(v)

func quad(st: SurfaceTool, a: Vector3, q: Vector3, d: Vector3, e: Vector3) -> void:
	triangle(st,a,q,d)
	triangle(st,a,d,e)

func window(p: Node3D, at: Vector3, width := 1.7, height := 1.3) -> void:
	b(p,at,Vector3(width+.15,height+.15,.08),"#494739")
	b(p,at+Vector3(0,0,.055),Vector3(width,height,.035),"#738d91")
	for x in [-width*.5,0,width*.5]:
		b(p,at+Vector3(x,0,.09),Vector3(.055,height+.06,.045),"#c0bba5")
	b(p,at+Vector3(0,0,.095),Vector3(width,.045,.035),"#c0bba5")
	b(p,at+Vector3(0,-height*.5-.08,.1),Vector3(width+.27,.11,.22),"#898e88")

func house(x: float,z: float,width: float,depth: float,tint: String,kind: String,yaw: float,balcony := true,hip := false,floors := 2, roof_color := "") -> Node3D:
	var n := group(x,z,yaw)
	var h := floors*2.9
	b(n,Vector3(0,h*.5,0),Vector3(width,h,depth),surface("plaster" if kind=="stone" else kind,tint),true)
	b(n,Vector3(0,.17,0),Vector3(width+.2,.35,depth+.2),surface("stone","#8f8b7d"))
	for sx in [-1,1]:
		for sz in [-1,1]:
			b(n,Vector3(sx*width*.49,h*.5,sz*depth*.49),Vector3(.16,h,.16),"#3f3128")
	for floor_no in floors:
		var fy := floor_no*2.9
		if floor_no>0: b(n,Vector3(0,fy,0),Vector3(width+.08,.18,depth+.08),"#493a2e")
		for side in [-1,1]:
			var wall := Node3D.new()
			n.add_child(wall)
			wall.rotation.y = 0 if side == 1 else PI
			for wx in [-width*.28,width*.28]:
				window(wall,Vector3(wx,fy+1.7,depth*.5+.02),minf(1.8,width*.25),1.25)
		if floor_no == 1 and balcony:
			b(n,Vector3(0,fy+.05,depth*.5+.47),Vector3(width-.5,.16,1.05),"#898e86")
			b(n,Vector3(0,fy+.94,depth*.5+.95),Vector3(width-.45,.08,.075),"#584f3e")
			for i in range(int((width-.5)/.23)):
				b(n,Vector3(-width*.5+.3+i*.23,fy+.51,depth*.5+.95),Vector3(.035,.83,.035),"#625c4f")
			for panel in 3:
				var blind_width:=width*.8/3-.1
				var wx: float=-width*.4+blind_width*.5+.05+panel*(blind_width+.1)
				b(n,Vector3(wx,4.85,depth*.5+.92),Vector3(blind_width,1.85,.025),surface("bamboo","#817761"))
				b(n,Vector3(wx,5.79,depth*.5+.92),Vector3(blind_width+.06,.05,.05),"#3a382c")
	# A recessed wooden sliding entrance with closely spaced battens.
	b(n,Vector3(0,1.22,depth*.5+.04),Vector3(1.65,2.15,.08),"#433b30")
	for i in 13:
		b(n,Vector3(-.77+i*.128,1.22,depth*.5+.10),Vector3(.032,2.05,.045),"#988467")
	b(n,Vector3(0,.08,depth*.5+.42),Vector3(2,.15,.85),"#969689",true)
	if absf(x+10.5)<.01 and absf(z-84)<.01:
		roof(n,Vector3(0,h+.05,0),depth+1.2,width+1.2,(width+1.2)*.34,"#3f484b",false,0).rotation.y=PI/2
		var gable:=SurfaceTool.new()
		gable.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in [-1,1]: triangle(gable,Vector3(-(width+1.18)*.5,h+.05,side*(depth*.5+.605)),Vector3((width+1.18)*.5,h+.05,side*(depth*.5+.605)),Vector3(0,h+.05+(width+1.2)*.34,side*(depth*.5+.605)))
		gable.generate_normals()
		var cap:=MeshInstance3D.new()
		cap.mesh=gable.commit()
		cap.material_override=m("#c4bdac")
		n.add_child(cap)
	else:
		roof(n,Vector3(0,h+.03,0),width+1.2,depth+1.2,depth*.34,(roof_color if not roof_color.is_empty() else ("#596366" if tint!="#d9d4bf" else "#a6aaa4")),hip,.3,"#554330" if not roof_color.is_empty() else "")
	# Drainpipes and outdoor condenser are significant in close street views.
	b(n,Vector3(width*.5+.06,h*.45,depth*.42),Vector3(.09,h*.9,.09),"#858b82")
	b(n,Vector3(width*.34,.61,depth*.5+.34),Vector3(.83,.57,.46),"#cac9b9")
	var fan := c(n,Vector3(width*.34,.61,depth*.5+.59),.21,.022,"#646c68")
	fan.rotation.x=PI/2
	for j in 4:
		b(n,Vector3(width*.34,.46+j*.09,depth*.5+.61),Vector3(.65,.015,.015),"#a2a69b")
	return n

func farm() -> void:
	house(40.5,73.6,8,6.5,"#65503b","wood",PI,false,true,1,"#c0a578")
	var kura := group(48,72.5,-.2)
	b(kura,Vector3(0,.6,0),Vector3(5.6,2,5.2),"#49493e",true)
	stonework(kura,5.6,5.2,2,-.4)
	b(kura,Vector3(0,3.8,0),Vector3(4.8,5.6,4.4),surface("wood","#885f37"),true)
	b(kura,Vector3(0,6.2,0),Vector3(4.79,.8,4.39),"#b4a993")
	for sx in [-1,1]:
		for sz in [-1,1]:
			b(kura,Vector3(sx*2.4,4.1,sz*2.2),Vector3(.19,5,.19),"#5a4833")
	for xx in range(47):
		for sz in [-1,1]: b(kura,Vector3(-2.3+xx*.1,3.8,sz*2.207),Vector3(.009,4.4,.012),"#5b3d27")
	for y in [2.9,4.3,5.8]: b(kura,Vector3(0,y,0),Vector3(4.9,.10,4.5),"#554635")
	b(kura,Vector3(0,3.25,2.24),Vector3(2.2,2.8,.10),surface("wood","#ad8f66"))
	for sx in [-1,1]: b(kura,Vector3(sx*1.45,5.7,2.24),Vector3(.7,.5,.1),"#282b23")
	roof(kura,Vector3(0,6.6,0),6.6,6.4,3.17,"#c4af7f",false,1,"#584333")
	var awning := group(40.5,70.35)
	roof(awning,Vector3(0,1.95,0),7.6,6,.8,"#c2ad7d",false,.6,"#584333")
	for sx in [-1,1]: b(awning,Vector3(sx*3.5,.98,-2.75),Vector3(.16,1.95,.16),"#4a3826")
	house(47.5,79.5,2.6,2,"#c4c0b4","metal",0,false,false,1).scale.y=.73
	c(self,Vector3(45.6,w.height_at(45.6,79.1)+.45,79.1),.3,.9,"#3a6ac0")
	car(43,69.3,.3,true)
	poles([[80,66,9.5],[66,78,10],[55.2,70.8,9.6,true],[52.4,68.6,10.2]])
	fence(Vector2(30,68),Vector2(35.2,68),.5,"#777b6c",false)

func village() -> void:
	var street_y: float=w.height_at(-20,83)
	b(self,Vector3(-10,street_y+.015,77),Vector3(30,.012,3.7),surface("asphalt","#5e5754"))
	for z in [70.9,79.15]: b(self,Vector3(-11,street_y+.02,z),Vector3(48,.16,.16),"#a7a18b")
	for x in [-14.2,-9.8,-3,1.6]:
		b(self,Vector3(x,street_y+.027,75.15),Vector3(.55,.015,.34),"#273b3c")
		for i in 7: b(self,Vector3(x-.23+i*.077,street_y+.04,75.15),Vector3(.014,.015,.31),"#697772")
	for data in [[-35,82.5,6.5,6.5,"#a8aab0","metal",PI,false],[-20.5,84,7.5,7,"#70767c","metal",-PI/2,false],[-10.5,84,8.5,7,"#b4bfc2","metal",PI,false],[-1,83.5,8,6.5,"#9aa3a8","metal",PI,false],[8.5,84,8,7,"#846951","wood",PI,true]]:
		house(data[0],data[1],data[2],data[3],data[4],data[5],data[6],true,data[7])
	for data in [[-22,59.5,9,7,"#977b56","wood"],[-31.5,55.5,8,7,"#a8aab0","metal"],[-12.5,58.4,8,6,"#d9d4bf","stone"],[-3.5,58,7,6,"#d9d4bf","stone"],[-38,92,9,7,"#826d4e","wood"],[-8,92.5,9,7,"#8a8e8c","metal"],[4,91,9,7,"#c9c5b5","stone"]]:
		house(data[0],data[1],data[2],data[3],data[4],data[5],0 if data[1]<65 else PI,false,true)
	# The north-facing shop facades, awnings, lanterns and narrow garden strip.
	for d in [[-20.5,79.9,7.1,"#776651","SAKE"],[-10.5,79.95,7.8,"#8a9298","COZY STORE"],[-1,79.8,6.8,"#557578","SORA"]]:
		var n := group(d[0],d[1],PI)
		var aw := b(n,Vector3(0,2.65,.62),Vector3(d[2],.12,1.45),d[3])
		aw.rotation.x = -.12
		b(n,Vector3(0,2.9,.11),Vector3(d[2]*.58,.53,.13),"#c0b49b")
		label(n,d[4],Vector3(0,2.91,.20),.23,"#514b3c")
		for i in [-1,1]:
			var lantern: MeshInstance3D = w.sphere(n,Vector3(i*float(d[2])*.42,2.9,.45),Vector3(.24,.39,.24),m("#d45537"))
			line(n,lantern.position+Vector3(0,.35,0),lantern.position+Vector3(0,.65,0),.015,"#403c31")
	poles([[-32,79.5,10.5],[-13,80.2,10.5],[6,80.2,10]])
	for d in [[-28,73.2],[-27.2,86.9],[-17,74],[-7,74],[2,73.5]]:
		var n := group(d[0],d[1])
		for j in 3: crate(n,Vector3(j*.53,0,0),"#4d6967")
	for d in [[-11.2,73.6],[-1.5,73.3]]:
		var n := group(d[0],d[1],.2)
		for j in 3:
			var size:=Vector3(.5+rng.randf()*.3,.3+rng.randf()*.2,.4+rng.randf()*.3)
			b(n,Vector3(0,j*.36+size.y*.5,0),size,"#b89d68" if j%2==0 else "#8a6a48",j==0)
			b(n,Vector3(0,j*.36+size.y+.01,0),Vector3(size.x,.025,.045),"#837357")
	for d in [[-12.4,74.4],[-15.2,75],[.5,75.3]]: cone(d[0],d[1])
	village_utility_yard()
	bicycle(-16,79.7,-1.4,"#a94232")
	bicycle(3.2,79.6,-.1,"#bfa345")

func label(p: Node3D, text: String, pos: Vector3, size: float, tint: String) -> Label3D:
	var l := Label3D.new()
	l.text=text
	l.position=pos
	l.pixel_size=size/48.0
	l.font_size=48
	l.modulate=Color(tint)
	l.outline_size=0
	l.no_depth_test=false
	p.add_child(l)
	return l

func shrine() -> void:
	var n := group(.5,23.5,PI-.22)
	b(n,Vector3(0,-.65,0),Vector3(6.6,1.4,6.4),"#49493e",true)
	stonework(n,6.6,6.4,1.4,-1.35)
	b(n,Vector3(0,.1,0),Vector3(6.6,.2,6.4),surface("stone","#d3cdbb"),true)
	b(n,Vector3(0,.42,0),Vector3(5.8,.85,5.6),surface("stone","#c7c1ab"),true)
	b(n,Vector3(0,2.2,0),Vector3(4.8,2.7,4.6),"#beb9a5",true)
	for sx in [-1,1]:
		for j in 5:
			b(n,Vector3(-2.4+j*1.2,2.2,sx*2.3),Vector3(.14,2.7,.16),"#58472e")
		for j in 4: b(n,Vector3(sx*2.4,2.2,-2.3+j*1.533),Vector3(.16,2.7,.14),"#58472e")
	for y in [.87,2.4,3.54]: b(n,Vector3(0,y,0),Vector3(4.9,.16,4.7),"#58472e")
	b(n,Vector3(0,1.63,2.33),Vector3(4.3,1.47,.08),surface("wood","#705339"))
	for i in 21: b(n,Vector3(-2.05+i*.205,1.63,2.40),Vector3(.035,1.4,.04),"#5a4934")
	roof(n,Vector3(0,3.65,0),6.7,6.5,.75,"#283238",true,.35)
	roof(n,Vector3(0,3.95,0),5.9,5.2,2.392,"#252d34",false,1.6).rotation.y=PI/2
	shrine_gable(n)
	b(n,Vector3(0,.97,2.8),Vector3(3.36,.25,.9),"#896644",true)
	house(8.5,31,7,5.5,"#594b3d","wood",PI-.15,false,true,1)
	for d in [[-4.2,24.5],[5.4,27]]:
		var lantern := group(d[0],d[1])
		b(lantern,Vector3(0,.15,0),Vector3(.7,.3,.7),"#9a9a89",true)
		c(lantern,Vector3(0,.85,0),.18,1.1,"#9a9a89",.14)
		b(lantern,Vector3(0,1.45,0),Vector3(.5,.12,.5),"#9a9a89")
		b(lantern,Vector3(0,1.72,0),Vector3(.42,.42,.42),"#999c87")
		for sx in [-1,1]: b(lantern,Vector3(0,1.74,sx*.214),Vector3(.24,.24,.02),"#42483c")
		roof(lantern,Vector3(0,2,0),.74,.74,.32,"#929989",true)
		w.sphere(lantern,Vector3(0,2.45,0),Vector3(.1,.1,.1),m("#a1a491"))
	fence(Vector2(9,22),Vector2(9,28),.7,"#8b8c7a",false)
	car(5.8,21.3,PI-.25,false)
	for d in [[1.5,13.5],[-1.5,15],[3.5,16.5],[.5,18],[5.5,15],[-2.5,12.8],[2.5,14.8],[7,19.5],[8.5,20],[3,20.5]]:
		var fly := group(d[0],d[1])
		fly.position.y+=rng.randf_range(1.1,2.0)
		fly.set_meta("origin",fly.position)
		fly.set_meta("phase",rng.randf()*TAU)
		b(fly,Vector3(-.07,0,0),Vector3(.14,.018,.15),"#efd779")
		b(fly,Vector3(.07,0,0),Vector3(.14,.018,.15),"#efd779")
		butterflies.append(fly)

func paddies() -> void:
	paddy_guardrail()
	for area in [Rect2(63.5,-8,35.5,52),Rect2(42,0,10,30)]:
		var water := StandardMaterial3D.new()
		water.albedo_color=Color("#77999a")
		water.metallic=.28
		water.roughness=.23
		b(self,Vector3(area.get_center().x,.405,area.get_center().y),Vector3(area.size.x,.025,area.size.y),water)
		var canopy := MeshInstance3D.new()
		var canopy_mesh := PlaneMesh.new()
		canopy_mesh.size = area.size-Vector2(.8,.8)
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(area.get_center().x,.95,area.get_center().y)
		var canopy_material := ShaderMaterial.new()
		canopy_material.shader = load("res://shaders/rice_canopy.gdshader")
		canopy.material_override = canopy_material
		canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(canopy)
		# Three bent, tapered ribbons form each rice tuft above the distant canopy.
		var blades := SurfaceTool.new()
		blades.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in 3:
			var yaw := j*TAU/3+rng.randf()*.8
			var direction := Vector3(cos(yaw),0,sin(yaw))
			var side := Vector3(-direction.z,0,direction.x)
			var width := rng.randf_range(.10,.15)
			var bend := rng.randf_range(.2,.6)
			for section in 4:
				var t0:=section/4.0
				var t1:=(section+1)/4.0
				var lower:=Vector3(0,t0,0)+direction*bend*t0*t0
				var upper:=Vector3(0,t1,0)+direction*bend*t1*t1
				var points: Array[Vector3]=[lower-side*width*(1-t0)*.5,lower+side*width*(1-t0)*.5,upper+side*width*(1-t1)*.5,lower-side*width*(1-t0)*.5,upper+side*width*(1-t1)*.5,upper-side*width*(1-t1)*.5]
				for point in points: blades.add_vertex(point)
		blades.generate_normals()
		var rice_mat := ShaderMaterial.new()
		rice_mat.shader=load("res://shaders/rice_blades.gdshader")
		var multi := MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=blades.commit()
		var transforms: Array[Transform3D]=[]
		var rows := int((area.size.x-1.2)/.35)
		var cols := int((area.size.y-1.2)/.45)
		for ix in rows:
			for iz in cols:
				var x: float = area.position.x+.6+ix*.35
				var z: float = area.position.y+.6+iz*.45
				if area.size.x>20 and (absf(x-81.2)<.33 or absf(z-17.8)<.3): continue
				var scale_y := rng.randf_range(.7,.9)
				var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(scale_y*2.4,scale_y,scale_y*2.4))
				transforms.append(Transform3D(basis,Vector3(x+rng.randf_range(-.04,.04),.42,z+rng.randf_range(-.04,.04))))
		multi.instance_count=transforms.size()
		for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
		var inst := MultiMeshInstance3D.new()
		inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.multimesh=multi
		inst.material_override=rice_mat
		add_child(inst)
		for z in [area.position.y,area.end.y]: b(self,Vector3(area.get_center().x,.48,z),Vector3(area.size.x+.5,.17,.4),"#858660")
		for x in [area.position.x,area.end.x]: b(self,Vector3(x,.48,area.get_center().y),Vector3(.4,.17,area.size.y),"#858660")
		if area.size.x>20:
			b(self,Vector3(81.2,.48,18),Vector3(.55,.17,52),"#8a8860")
			b(self,Vector3(81.2,.48,17.8),Vector3(35.5,.17,.5),"#8a8860")
	fence(Vector2(63.9,-6),Vector2(63.9,44),1,"#5a6848",false)
	fence(Vector2(99.6,-8),Vector2(99.6,44),1,"#5a6848",false)
	fence(Vector2(64.2,44.5),Vector2(99,44.5),1.2,"#888d85",true)
	fence(Vector2(64.2,-8.5),Vector2(99,-8.5),1.2,"#888d85",true)
	var cabinet := group(61,3.6,-2.05)
	b(cabinet,Vector3(0,.125,0),Vector3(1.6,.25,1.15),"#b9b6a8",true)
	b(cabinet,Vector3(0,1.25,0),Vector3(1.4,2,.95),"#d9642c",true)
	b(cabinet,Vector3(0,.41,0),Vector3(1.42,.30,.97),"#b35b28")
	b(cabinet,Vector3(0,2.15,0),Vector3(1.42,.14,.97),"#e08a55")
	b(cabinet,Vector3(0,2.27,0),Vector3(1.46,.06,1.01),"#b35b28")
	b(cabinet,Vector3(0,1.25,.48),Vector3(.018,1.8,.02),"#8a4522")
	b(cabinet,Vector3(.1,1.1,.50),Vector3(.05,.11,.05),"#2a302a")
	b(cabinet,Vector3(.32,1.45,.49),Vector3(.26,.18,.02),"#cfcdc0")
	poles([[63.5,44,10.5,.1,1.0],[64.9,7.4,9.6,.25,.85],[61.6,4.7,10.8,PI+.25,1.15],[70.5,-14,10.5,.35,1.0]],true)
	var lamp_origin := Vector3(61.6,w.height_at(61.6,4.7)+7.56,4.7)
	var lamp_direction := Vector3(-.94,0,.34).normalized()
	var lamp_end := lamp_origin+lamp_direction*1.7+Vector3(0,.35,0)
	line(self,lamp_origin+lamp_direction*.1,lamp_end,.05,"#9a9b98")
	line(self,lamp_origin-Vector3(0,.7,0),lamp_origin+lamp_direction*.7+Vector3(0,.14,0),.03,"#9a9b98")
	var lamp := Node3D.new()
	add_child(lamp)
	lamp.position=lamp_end+lamp_direction*.2+Vector3(0,.02,0)
	lamp.rotation.y=atan2(lamp_direction.x,lamp_direction.z)-PI/2
	b(lamp,Vector3(0,.06,0),Vector3(.62,.17,.28),"#9a9b98")
	b(lamp,Vector3(.06,-.05,0),Vector3(.42,.06,.24),"#e8e4c8")
	var meter := group(61.4,4.48,atan2(-6.4,-7.3))
	b(meter,Vector3(0,3.1,0),Vector3(.4,.5,.25),"#b4b7b0")

func fence(a: Vector2,q: Vector2,height: float,color: String,wire: bool) -> void:
	var distance := a.distance_to(q)
	var steps := maxi(1,int(distance/1.8))
	var points: Array[Vector3]=[]
	for i in range(steps+1):
		var at := a.lerp(q,float(i)/steps)
		var ground := Vector3(at.x,w.height_at(at.x,at.y),at.y)
		b(self,ground+Vector3(0,height*.5,0),Vector3(.075 if wire else .13,height,.075 if wire else .13),color)
		points.append(ground)
		if i>0:
			for y in [.45,.85] if not wire else [.12,.52,.92]:
				line(self,points[i-1]+Vector3(0,y*height,0),ground+Vector3(0,y*height,0),.025 if wire else .045,color)
			if wire:
				chainlink_panel(points[i-1],ground,height)
	var barrier := Node3D.new()
	add_child(barrier)
	barrier.position = (points[0]+points[-1])*.5+Vector3(0,height*.5,0)
	barrier.rotation.y = atan2(-(q.y-a.y),q.x-a.x)
	w.add_collision_box(barrier,Vector3.ZERO,Vector3(distance,height,.09))

func poles(data: Array, dark := false) -> void:
	var previous: Vector3
	for i in data.size():
		var d: Array=data[i]
		var n := group(d[0],d[1])
		var h: float=d[2]
		if dark:
			n.rotation.y=d[3]
			var radius:float=d[4]
			var shaft:=c(n,Vector3(0,h*.5-.3,0),.19*radius,h,"#696961",.12*radius)
			shaft.material_override=surface("pole","#78786d")
			for rung in 9: b(n,Vector3(0,2.5+rung*.75,0),Vector3(.05,.05,.42),"#3a3b38")
		else:
			c(n,Vector3(0,h*.5,0),.115,h,"#7b8175",.08)
		b(n,Vector3(0,h-.48,0),Vector3(2.25,.13,.13),"#656f68")
		b(n,Vector3(0,h-1.22,0),Vector3(1.8,.10,.11),"#656f68")
		for sx in [-.9,0,.9]:
			c(n,Vector3(sx,h-.28,0),.072,.26,"#b3b9a7")
			c(n,Vector3(sx,h-1.05,0),.063,.25,"#b3b9a7")
		if not dark and d.size()>3 and d[3]:
			for tx in [.35,-.35]:
				c(n,Vector3(tx,h-2,.22),.22,.75,"#9c9d88")
				c(n,Vector3(tx,h-1.6,.22),.25,.065,"#747966")
		b(n,Vector3(0,h-2.5,.23),Vector3(.11,.08,.5),"#68756b")
		if i>0:
			for sx in [-.9,0,.9]:
				wire_sag(previous+Vector3(sx,0,0),n.position+Vector3(sx,h-.15,0),1.0)
			wire_sag(previous-Vector3(0,1.7,0),n.position+Vector3(0,h-1.85,0),1.4)
		previous=n.position+Vector3(0,h-.15,0)

func wire_sag(a: Vector3,q: Vector3,sag: float) -> void:
	var prev:=a
	for i in range(1,17):
		var t:=i/16.0
		var v:=a.lerp(q,t)-Vector3(0,4*sag*t*(1-t),0)
		line(self,prev,v,.015,"#3a4543")
		prev=v

func vending_machine(x: float,z: float,yaw: float,tint: String,worn := false) -> Node3D:
	var n := group(x,z,yaw)
	b(n,Vector3(0,1,0),Vector3(1,1.9,.8),surface("paint",tint),true)
	b(n,Vector3(0,.035,0),Vector3(.90,.07,.7),"#222f2e")
	b(n,Vector3(-.14,1.31,.407),Vector3(.68,.9,.02),"#263039")
	b(n,Vector3(-.14,1.31,.424),Vector3(.62,.84,.02),"#1c2024")
	for yy in [.87,1.748]: b(n,Vector3(-.14,yy,.438),Vector3(.66,.03,.035),"#bfc6bd")
	var bottle_colors: Array[String]=["#d45742","#e3bf53","#3c787e","#e7e4c6","#5c9648"]
	for row in (5 if worn else 3):
		for col in (11 if worn else 9):
			var xx: float=-.42+col*(.055 if worn else .069)
			var yy: float=(.98+row*.165) if worn else (1.05+row*.265)
			var can_height:=rng.randf_range(.075,.10) if worn else rng.randf_range(.12,.19)
			c(n,Vector3(xx,yy,.458),.022,can_height,bottle_colors[(row+col)%5])
			c(n,Vector3(xx,yy,.458),.023,.045,"#e7e3cc")
			if rng.randf()>.35: c(n,Vector3(xx,yy+can_height*.5+.01,.458),.010,.024,"#e4dfc9")
			b(n,Vector3(xx,yy-.105,.455),Vector3(.052,.015,.03),"#e5e6d8")
	for row in 3:
		b(n,Vector3(-.14,1.0+row*.266,.44),Vector3(.64,.027,.05),"#c5ccc2")
		b(n,Vector3(.35,1.63-row*.09,.419),Vector3(.11,.05,.025),"#d7ddc5")
	b(n,Vector3(.32,.95,.42),Vector3(.16,.08,.03),"#273737")
	b(n,Vector3(.34,.79,.42),Vector3(.04,.09,.03),"#273737")
	b(n,Vector3(-.15,.32,.416),Vector3(.6,.16,.03),"#1e3333")
	b(n,Vector3(-.15,.27,.44),Vector3(.64,.035,.1),"#a4b4af")
	label(n,"CUP" if tint=="#1f2f6c" else ("ICE" if tint=="#e8e6e0" else "GM"),Vector3(-.13,.56,.426),.13,"#e6e9d4")
	return n

func vending_area() -> void:
	vending_machine(-66.3,27.4,PI/2,"#e8e6e0")
	vending_machine(-66.3,26.35,PI/2,"#1f2f6c")
	vending_machine(-66.3,25.3,PI/2,"#c8262a")
	fence(Vector2(-67.2,10),Vector2(-67.2,21.4),2.3,"#7c8e85",true)
	fence(Vector2(-67.2,24.9),Vector2(-67.2,40),2.3,"#7c8e85",true)
	for j in 2:
		var n := group(-66.45,24.3-j*.55)
		for i in 3: crate(n,Vector3(0,i*.33,0),"#c84040" if (j==0 and i==2) or (j==1 and i==1) else "#3a8a4a")
	var boxes := group(-66.25,29.4,.3)
	for i in 3: b(boxes,Vector3((i%2)*.2,.20+i*.34,0),Vector3(.48,.37,.44),surface("wood","#b0a17f"))
	for d in [[-65.75,29.7],[-65.65,27.4],[-65.6,25],[-65.7,21.7]]: cone(d[0],d[1])
	poles([[-76.5,0,8.4],[-76,20.5,8.6],[-75.5,44,8.6]])
	bicycle(-66.55,22.3,-PI/2,"#bfa345")
	var cone_points: Array[Vector2]=[Vector2(-65.75,29.7),Vector2(-65.65,27.4),Vector2(-65.6,25),Vector2(-65.7,21.7)]
	for i in 3:
		var a:=cone_points[i]
		var q:=cone_points[i+1]
		hazard_tape(Vector3(a.x,w.height_at(a.x,a.y)+.42,a.y),Vector3(q.x,w.height_at(q.x,q.y)+.42,q.y),.05)
	viaduct_vending()

func crate(p: Node3D,pos: Vector3,tint: String) -> void:
	b(p,pos+Vector3(0,.15,0),Vector3(.5,.3,.38),tint)
	for y in [.05,.15,.25]:
		for sx in [-1,1]: b(p,pos+Vector3(sx*.251,y,0),Vector3(.012,.026,.30),"#243d35")
	for i in 4:
		for sz in [-1,1]: b(p,pos+Vector3(-.18+i*.12,.15,sz*.191),Vector3(.055,.17,.012),"#294d43")

func cone(x: float,z: float) -> void:
	var n := group(x,z)
	b(n,Vector3(0,.025,0),Vector3(.36,.05,.36),"#384442")
	c(n,Vector3(0,.28,0),.145,.5,"#cf6b3b",.025)
	c(n,Vector3(0,.34,0),.09,.085,"#d9d3b3",.07)

func car(x: float,z: float,yaw: float,truck: bool) -> void:
	var n := group(x,z,yaw)
	b(n,Vector3(0,.45,0),Vector3(3.6 if truck else 4.2,.45,1.62),"#e5e4d7",true)
	b(n,Vector3(0,.3,0),Vector3(3.5 if truck else 4.1,.20,1.58),"#283b3c")
	b(n,Vector3(.52 if truck else -.10,1.03,0),Vector3(1.35,.72,1.45),"#506f78")
	b(n,Vector3(.52 if truck else -.10,1.44,0),Vector3(1.50,.13,1.54),"#e3e3d5")
	for sx in [-1,1]:
		b(n,Vector3((.52 if truck else -.10)+sx*.68,1.03,0),Vector3(.09,.72,1.45),"#e5e4d7")
		for side in [-1,1]:
			var wheel := c(n,Vector3(sx*1.25,.34,side*.79),.32,.18,"#293333")
			wheel.rotation.x=PI/2
			var hub := c(n,Vector3(sx*1.25,.34,side*.89),.17,.025,"#abb4ad")
			hub.rotation.x=PI/2
	if truck:
		b(n,Vector3(-1.05,.73,0),Vector3(1.4,.12,1.6),"#afb6ac")
		for side in [-1,1]: b(n,Vector3(-1.05,.86,side*.76),Vector3(1.5,.28,.09),"#d1d5c7")
	else:
		b(n,Vector3(1.30,.78,0),Vector3(1.4,.25,1.59),"#eceadd")
	for side in [-1,1]:
		b(n,Vector3(1.82 if truck else 2.11,.66,side*.52),Vector3(.045,.20,.40),"#e7e4bd")
		b(n,Vector3(-1.82 if truck else -2.11,.66,side*.52),Vector3(.045,.17,.34),"#bd4738")
	b(n,Vector3(1.84 if truck else 2.14,.46,0),Vector3(.03,.17,.34),"#d4c98b")

func bicycle(x: float,z: float,yaw: float,tint: String) -> void:
	var n := group(x,z,yaw)
	for sx in [-.6,.6]:
		var torus := TorusMesh.new()
		torus.inner_radius=.30
		torus.outer_radius=.34
		var wheel:=MeshInstance3D.new()
		wheel.mesh=torus
		wheel.material_override=m("#35433e")
		wheel.position=Vector3(sx,.36,0)
		wheel.rotation.x=PI/2
		n.add_child(wheel)
		for i in 8:
			var a:=i*TAU/8
			line(n,Vector3(sx,.36,0),Vector3(sx+cos(a)*.30,.36+sin(a)*.30,0),.005,"#aeb7a4")
	for pair in [[Vector3(-.6,.36,0),Vector3(-.2,.8,0)],[Vector3(-.2,.8,0),Vector3(.08,.36,0)],[Vector3(.08,.36,0),Vector3(-.6,.36,0)],[Vector3(-.2,.8,0),Vector3(.46,.86,0)],[Vector3(.46,.86,0),Vector3(.08,.36,0)],[Vector3(.46,.86,0),Vector3(.6,.36,0)]]:
		line(n,pair[0],pair[1],.022,tint)
	b(n,Vector3(-.2,.92,0),Vector3(.28,.07,.17),"#514d3d")
	line(n,Vector3(.46,.86,0),Vector3(.4,1.08,0),.025,"#b7bdb0")
	line(n,Vector3(.4,1.08,-.20),Vector3(.4,1.08,.20),.025,"#b7bdb0")

func railway() -> void:
	rail_signs()
	var controls: Array[Vector3]=[Vector3(-80,11.5,36),Vector3(-52,11.5,54),Vector3(-44,11.5,68),Vector3(-40,11.5,84),Vector3(-20,11.5,96),Vector3(60,11.5,96),Vector3(108,11.5,70)]
	# Catmull-Rom interpolation carries the railway through its control points
	# and preserves the pronounced western turn.
	for i in range(controls.size()-1):
		var a: Vector3=controls[maxi(0,i-1)]
		var q: Vector3=controls[i]
		var d: Vector3=controls[i+1]
		var e: Vector3=controls[mini(controls.size()-1,i+2)]
		for j in 8:
			var t:=j/8.0
			track.add_point(.5*((2*q)+(-a+d)*t+(2*a-5*q+4*d-e)*t*t+(-a+3*q-3*d+e)*t*t*t))
	track.add_point(controls[-1])
	track.bake_interval=.4
	var length:=track.get_baked_length()
	var closest:=INF
	for i in 401:
		var fraction:=i/400.0
		var point:=track.sample_baked(fraction*length)
		var distance_to_start:=Vector2(point.x-89,point.z-track_z(89)).length()
		if distance_to_start<closest:
			closest=distance_to_start
			train_start=fraction
	var distance:=0.0
	while distance<length:
		var a:=track.sample_baked(distance)
		var q:=track.sample_baked(minf(distance+2,length))
		var direction:=(q-a).normalized()
		var side:=Vector3(-direction.z,0,direction.x)
		var center:=(a+q)*.5
		var bridge:=center.x>=12 and center.x<=44
		var segment:=Node3D.new()
		add_child(segment)
		segment.position=center
		segment.rotation.y=atan2(-direction.z,direction.x)
		if not bridge:
			b(segment,Vector3(0,-.65,0),Vector3(a.distance_to(q)+.04,1.3,8.5),surface("concrete","#b0aea0"))
		else:
			b(segment,Vector3(0,-.15,0),Vector3(a.distance_to(q)+.04,.3,4.5),"#514c3c")
			b(segment,Vector3(0,-.65,0),Vector3(.3,.75,8.2),"#79573d")
		for sz in [-1,1]:
			if not bridge:
				b(segment,Vector3(0,.45,sz*4.06),Vector3(2.05,.9,.38),"#cac9b7")
				b(segment,Vector3(0,-1.95,sz*1.9),Vector3(2.05,.7,.50),"#9b9987")
				b(segment,Vector3(0,1.38,sz*4.12),Vector3(.07,1.1,.07),"#e3e2d2")
				for y in [1.4,1.9]: b(segment,Vector3(0,y,sz*4.12),Vector3(2.05,.04,.04),"#e3e2d2")
			b(segment,Vector3(0,.31,sz*.83),Vector3(2.06,.13,.09),"#5e655f")
		for j in 3: b(segment,Vector3(-.7+j*.7,.17,0),Vector3(.19,.12,2.25),"#6d7364")
		if int(distance/2)%6==0 and not bridge:
			var ground: float=w.height_at(center.x,center.z)
			var ph:=11.5-ground-2.2
			if ph>1:
				b(segment,Vector3(0,-2.2-ph*.5,0),Vector3(1.65,ph,4.9),surface("concrete","#a8a799"),true)
				b(segment,Vector3(0,-2.35,0),Vector3(2.1,.7,6.8),"#c7c5b2")
		if int(distance/2)%13==0:
			for sz in [-1,1]:
				c(segment,Vector3(0,3.7,sz*3.05),.07,7.4,"#727c72")
			b(segment,Vector3(0,7.3,0),Vector3(.12,.12,6.4),"#757f74")
			for sz in [-1,1]: c(segment,Vector3(0,6.9,sz*.8),.07,.6,"#b8beb0")
		for sz in [-.7,.7]:
			line(self,a+side*sz+Vector3(0,6.6,0),q+side*sz+Vector3(0,6.6,0),.012,"#54635b")
		distance+=2.0
	# Riveted steel through-truss spans the gully between x12 and x44.
	var start:=Vector3(12,11.5,track_z(12))
	var finish:=Vector3(44,11.5,track_z(44))
	var delta:=finish-start
	var side:=Vector3(-delta.z,0,delta.x).normalized()*4.25
	for sign_value in [-1,1]:
		var offset: Vector3 = side*sign_value
		line(self,start+offset-Vector3(0,.6,0),finish+offset-Vector3(0,.6,0),.23,"#79573d")
		line(self,start.lerp(finish,.125)+offset+Vector3(0,9,0),start.lerp(finish,.875)+offset+Vector3(0,9,0),.23,"#79573d")
		for i in 8:
			var a:=start.lerp(finish,i/8.0)+offset
			var q:=start.lerp(finish,(i+1)/8.0)+offset
			var low:=a-Vector3(0,.6,0)
			if i>0: line(self,low,a+Vector3(0,9,0),.14,"#79573d")
			if i==0: line(self,low,q+Vector3(0,9,0),.18,"#79573d")
			elif i==7: line(self,a+Vector3(0,9,0),q-Vector3(0,.6,0),.18,"#79573d")
			elif i<4: line(self,a+Vector3(0,9,0),q-Vector3(0,.6,0),.14,"#79573d")
			else: line(self,low,q+Vector3(0,9,0),.14,"#79573d")
	for i in range(1,8):
		var a:=start.lerp(finish,i/8.0)+Vector3(0,9,0)
		line(self,a-side,a+side,.14,"#79573d")
		if i<7:
			var q:=start.lerp(finish,(i+1)/8.0)+Vector3(0,9,0)
			line(self,a-side,q+side,.065,"#79573d")
			line(self,a+side,q-side,.065,"#79573d")
	for i in 4:
		var n:=Node3D.new()
		add_child(n)
		train_cars.append(n)
		b(n,Vector3(0,2.604,0),Vector3(19.5,2.808,2.9),"#d6d8dc")
		b(n,Vector3(0,4.06,0),Vector3(19.35,.30,2.85),"#b8bcc0")
		b(n,Vector3(0,.95,0),Vector3(18.5,.50,2.46),"#252f32")
		for sz in [-1,1]:
			b(n,Vector3(0,3.1,sz*1.455),Vector3(19.45,.96,.025),"#263b44")
			b(n,Vector3(0,2.1,sz*1.475),Vector3(19.45,.24,.025),"#efc52c")
			for j in 4:
				var dx: float=-7.5+j*4.78
				b(n,Vector3(dx,2.6,sz*1.48),Vector3(1.74,2.15,.035),"#bfc3c3")
				for sx in [-1,1]: b(n,Vector3(dx+sx*.42,3.12,sz*1.505),Vector3(.65,.80,.025),"#2b4148")
				b(n,Vector3(dx,2.6,sz*1.51),Vector3(.025,2.15,.015),"#586561")
			for sx in [-6.5,6.5]:
				var wheel:=c(n,Vector3(sx,.43,sz*.75),.43,.2,"#26322f")
				wheel.rotation.x=PI/2
				b(n,Vector3(sx,.7,sz*.9),Vector3(2.6,.4,.3),"#26322f")
		for sx in [-6,0,6]: b(n,Vector3(sx,4.36,0),Vector3(1.6,.35,1.8),"#c9cfcd")
		for sx in [-1,1]:
			b(n,Vector3(sx*9.76,3,0),Vector3(.13,1.8,2.61),"#243337")
			b(n,Vector3(sx*9.84,1.81,0),Vector3(.03,.35,2.66),"#efc52c")
			for sz in [-1,1]: b(n,Vector3(sx*9.86,3.43,sz*.9),Vector3(.05,.22,.4),"#f3eaca")
	update_train()

func track_z(x: float) -> float:
	for i in range(track.point_count-1):
		var a:=track.get_point_position(i)
		var q:=track.get_point_position(i+1)
		if x>=a.x and x<=q.x: return lerpf(a.z,q.z,(x-a.x)/(q.x-a.x))
	return 96.0

func update_train() -> void:
	var length:=track.get_baked_length()
	var phase:=fposmod((elapsed-3.0)/70.0,1.0)
	var fraction:=train_start-phase*1.8 if phase<.5 else train_start-.9+(phase-.5)*1.8
	for i in train_cars.size():
		var at:=fraction*length-i*20.3
		var n:=train_cars[i]
		n.visible=at>=0 and at<=length
		if not n.visible: continue
		var pos:=track.sample_baked(at)+Vector3(0,.5,0)
		var direction:=track.sample_baked(minf(length,at+.5))-track.sample_baked(maxf(0,at-.5))
		n.position=pos
		n.rotation.y=atan2(-direction.z,direction.x)

func _process(dt: float) -> void:
	if not "--shot" in OS.get_cmdline_user_args(): elapsed+=dt
	if not train_cars.is_empty(): update_train()
	for n in butterflies:
		var origin: Vector3=n.get_meta("origin")
		var phase: float=n.get_meta("phase")
		var t:=elapsed*.8+phase
		n.position=origin+Vector3(sin(t*.7)*.8,sin(t*1.9)*.25,cos(t*.55)*.6)
		n.rotation.y=t*.7
		n.get_child(0).rotation.z=sin(elapsed*22+phase)*.9
		n.get_child(1).rotation.z=-sin(elapsed*22+phase)*.9

func village_utility_yard() -> void:
	fence(Vector2(-16,72.6),Vector2(-11.8,72.6),1.95,"#87958b",true)
	fence(Vector2(-11.8,72.6),Vector2(-6.4,72.6),1.95,"#87958b",true)
	fence(Vector2(-6.4,72.6),Vector2(2,72.6),2.5,"#87958b",true)
	vending_machine(-6.8,73.2,.55,"#b64b3a")
	var rack:=group(-9.7,73.1,.08)
	for xx in [-.69,.69]:
		for zz in [-.22,.22]: b(rack,Vector3(xx,.925,zz),Vector3(.07,1.85,.07),"#5a4632")
	for yy in [.07,.925,1.8]: b(rack,Vector3(0,yy,0),Vector3(1.45,.07,.5),"#816a49")
	for i in 6:
		for sz in [-1,1]: b(rack,Vector3(-.59+i*.24,.95,sz*.25),Vector3(.1,1.63,.045),"#9d8158")
	var n:=group(-8.15,73.65,.4)
	for i in 3: crate(n,Vector3(0,i*.33,0),["#7a5a3a","#5a4d38","#8a7a48"][i])
	b(n,Vector3(0,1.16,0),Vector3(.4,.34,.36),"#b89d68")
	var pipe:=group(-6.2,73.55)
	line(pipe,Vector3(0,.62,0),Vector3(5.2,.62,0),.11,"#c3a743")
	for xx in [.3,2.4]: c(pipe,Vector3(xx,.31,0),.04,.62,"#8e8980")
	for xx in [.675,.925]:
		var flange:=c(pipe,Vector3(xx,.62,0),.16,.12,"#2d4e4a")
		flange.rotation.z=PI/2
	c(pipe,Vector3(.8,.82,0),.03,.22,"#8e8980")
	var torus:=TorusMesh.new()
	torus.inner_radius=.10
	torus.outer_radius=.14
	var valve:=MeshInstance3D.new()
	valve.mesh=torus
	valve.material_override=m("#b03a30")
	valve.position=Vector3(.8,.95,0)
	pipe.add_child(valve)
	for i in 4:
		var yaw:=i*PI/2
		line(pipe,Vector3(.8,.95,0),Vector3(.8+cos(yaw)*.11,.95,sin(yaw)*.11),.012,"#b03a30")
	var barricade:=group(-6.6,73.95,.25)
	for xx in [-.6,.6]:
		for zz in [-.12,.12]: line(barricade,Vector3(xx,0,zz),Vector3(xx,.85,0),.02,"#bdc3b5")
	for yy in [.42,.78]:
		b(barricade,Vector3(0,yy,0),Vector3(1.3,.18,.04),"#e4e3cc")
		for j in 7:
			var stripe:=b(barricade,Vector3(-.57+j*.18,yy,.025),Vector3(.085,.19,.012),"#d87545")
			stripe.rotation.z=-.35

func consolidate_static_meshes() -> void:
	var buckets: Dictionary={}
	collect_static(self,Transform3D.IDENTITY,buckets)
	for entry: Dictionary in buckets.values():
		var mesh_node:=MeshInstance3D.new()
		mesh_node.name="SettlementBatch"
		var st: SurfaceTool=entry.surface
		mesh_node.mesh=st.commit()
		mesh_node.material_override=entry.material
		add_child(mesh_node)

func collect_static(node: Node3D,relative: Transform3D,buckets: Dictionary) -> void:
	for child: Node in node.get_children():
		if not child is Node3D: continue
		if train_cars.has(child) or butterflies.has(child): continue
		var transform: Transform3D=relative*child.transform
		if child is MeshInstance3D and child.mesh!=null:
			var material: Material=child.material_override
			if material==null: continue
			var tile:=Vector2i(floori(transform.origin.x/32),floori(transform.origin.z/32))
			var key: String=str(material.get_instance_id())+":"+str(tile)
			if not buckets.has(key):
				var surface_tool:=SurfaceTool.new()
				surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				buckets[key]={"surface":surface_tool,"material":material}
			var surface_tool: SurfaceTool=buckets[key].surface
			for i in child.mesh.get_surface_count(): surface_tool.append_from(child.mesh,i,transform)
			# Collision shapes are siblings, and Labels are separate retained nodes.
			child.queue_free()
		else:
			collect_static(child,transform,buckets)

func chainlink_panel(a: Vector3,q: Vector3,height: float) -> void:
	if not textures.has("chainlink"):
		var img:=Image.create(64,64,false,Image.FORMAT_RGBA8)
		img.fill(Color(0,0,0,0))
		for yy in 64:
			for xx in 64:
				if abs(xx-yy)<2 or abs(xx+yy-63)<2:
					img.set_pixel(xx,yy,Color("#9eafa5"))
		img.generate_mipmaps()
		var mat:=StandardMaterial3D.new()
		mat.albedo_texture=ImageTexture.create_from_image(img)
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold=.3
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		mat.roughness=.9
		textures["chainlink"]=mat
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3]=[a,q,q+Vector3(0,height,0),a,a+Vector3(0,height,0),q+Vector3(0,height,0)]
	var u:=a.distance_to(q)*6.5
	var v:=height*6.5
	var uv: Array[Vector2]=[Vector2(0,0),Vector2(u,0),Vector2(u,v),Vector2(0,0),Vector2(0,v),Vector2(u,v)]
	for i in 6:
		st.set_uv(uv[i])
		st.add_vertex(verts[i])
	st.generate_normals()
	var inst:=MeshInstance3D.new()
	inst.mesh=st.commit()
	inst.material_override=textures["chainlink"]
	add_child(inst)

func paddy_guardrail() -> void:
	var previous:=Vector3.ZERO
	var count:=0
	var pts: Array=w.roads[0]
	for i in range(pts.size()-1):
		var p: Vector2=pts[i]
		if p.x<44 or p.y < -6 or p.y > 42: continue
		var delta: Vector2=(pts[i+1]-p).normalized()
		var at:=p+Vector2(delta.y,-delta.x)*4.45
		var v:=Vector3(at.x,w.height_at(at.x,at.y)+.595,at.y)
		if count>0 and previous.distance_to(v)<5:
			var rail:=Node3D.new()
			add_child(rail)
			rail.position=(previous+v)*.5
			rail.rotation.y=atan2(-(v.z-previous.z),v.x-previous.x)
			for off in [-.105,0,.105]: b(rail,Vector3(0,off,.012 if off==0 else 0),Vector3(previous.distance_to(v)+.06,.085,.035),"#8e9578")
		if count%2==0: b(self,v-Vector3(0,.30,-.1),Vector3(.09,.675,.12),"#7a8668")
		previous=v
		count+=1

func rail_signs() -> void:
	var x:=23.331
	var z:=84.129
	var n:=group(x,z,atan2(19.2-x,80-z))
	var ground: float=w.height_at(x,z)
	c(n,Vector3(0,(10.78-ground)*.5,0),.035,10.78-ground,"#87918a")
	var sign_y:=7.39-ground
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	triangle(st,Vector3(-.38,.34,.07),Vector3(.38,.34,.07),Vector3(0,-.34,.07))
	st.generate_normals()
	var triangle_mesh:=MeshInstance3D.new()
	triangle_mesh.mesh=st.commit()
	triangle_mesh.material_override=m("#e4ddd1")
	triangle_mesh.position.y=sign_y
	n.add_child(triangle_mesh)
	for pair in [[Vector3(-.34,.30,.085),Vector3(.34,.30,.085)],[Vector3(.34,.30,.085),Vector3(0,-.30,.085)],[Vector3(0,-.30,.085),Vector3(-.34,.30,.085)]]:
		line(n,pair[0]+Vector3(0,sign_y,0),pair[1]+Vector3(0,sign_y,0),.035,"#a43f30")
	label(n,"SLOW",Vector3(0,sign_y+.04,.092),.085,"#464b42")
	for j in 2:
		var circle:=c(n,Vector3(0,sign_y-.71-j*.66,.07),.29,.035,"#365c7d" if j==0 else "#a44336")
		circle.rotation.x=PI/2
		if j==1:
			var inner:=c(n,Vector3(0,sign_y-1.37,.095),.225,.02,"#e1ddd1")
			inner.rotation.x=PI/2
			b(n,Vector3(0,sign_y-1.40,.11),Vector3(.27,.095,.014),"#304969")
			b(n,Vector3(-.035,sign_y-1.32,.11),Vector3(.16,.08,.014),"#304969")
			for sx in [-1,1]:
				var wheel:=c(n,Vector3(sx*.085,sign_y-1.46,.12),.024,.012,"#253e5e")
				wheel.rotation.x=PI/2
			var slash:=b(n,Vector3(0,sign_y-1.37,.14),Vector3(.055,.5,.014),"#aa483d")
			slash.rotation.z=-.78
		else:
			b(n,Vector3(-.04,sign_y-.71,.10),Vector3(.06,.34,.016),"#e3dfc9")
			b(n,Vector3(.055,sign_y-.73,.10),Vector3(.24,.055,.016),"#e3dfc9")
			for sx in [-1,1]:
				var arrow:=b(n,Vector3(-.04+sx*.046,sign_y-.59,.10),Vector3(.045,.13,.016),"#e3dfc9")
				arrow.rotation.z=sx*.75
				var turn_arrow:=b(n,Vector3(.13,sign_y-.73+sx*.045,.11),Vector3(.045,.13,.016),"#e3dfc9")
				turn_arrow.rotation.z=PI*.5+sx*.75

func rock_pattern(im: Image,base: Color,random: RandomNumberGenerator) -> void:
	im.fill(base*.5)
	for i in 60:
		var x:=random.randf_range(-12,126)
		var y:=random.randf_range(-12,126)
		var width:=random.randf_range(11,28)
		var height:=random.randf_range(8,20)
		var poly:=PackedVector2Array([Vector2(x,y+height*.3),Vector2(x+width*.3,y),Vector2(x+width,y+height*.2),Vector2(x+width*.9,y+height),Vector2(x+width*.2,y+height*.95)])
		var color:=base*random.randf_range(.85,1.24)
		for yy in range(maxi(0,int(y)),mini(128,int(y+height)+1)):
			for xx in range(maxi(0,int(x)),mini(128,int(x+width)+1)):
				if Geometry2D.is_point_in_polygon(Vector2(xx,yy),poly): im.set_pixel(xx,yy,color*random.randf_range(.94,1.03))

func shrine_gable(n: Node3D) -> void:
	for sz in [-1,1]:
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for sx in [-1,1]:
			var previous:=Vector3(sx*2.48,4.448,sz*2.65)
			for j in range(1,13):
				var t:=j/12.0
				var next:=Vector3(sx*2.48*(1-t),3.95+2.392*(pow(t,1.55)+.3*(1-t))-.22,sz*2.65)
				triangle(st,Vector3(0,3.55,sz*2.65),previous,next)
				line(n,previous+Vector3(0,.14,sz*.10),next+Vector3(0,.14,sz*.10),.105,"#252b2b")
				previous=next
		st.generate_normals()
		var face:=MeshInstance3D.new()
		face.mesh=st.commit()
		var mat:=surface("wood","#c1b691")
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		face.material_override=mat
		n.add_child(face)

func roof_point(half: float,ridge: float,depth: float,rise: float,curved: float,side: float,t: float,u: float,hip: bool) -> Vector3:
	var x:=lerpf(half,ridge,t)*u
	var y:=rise*t
	var z:=side*(1-t)*depth*.5
	if not hip and curved>1.2:
		y=rise*(pow(t,1.55)+(1-t)*.55*pow(absf(u),3))
		z*=1+.06*pow(absf(u),3)
	elif not hip and curved>0:
		y=rise*pow(t,1+.8*curved)+(1-t)*.22*curved*pow(absf(u),4)*rise
	return Vector3(x,y,z)

func hazard_tape(a: Vector3,q: Vector3,height: float) -> void:
	var count:=maxi(2,int(a.distance_to(q)/.11))
	for i in count:
		var t0:=float(i)/count
		var t1:=float(i+1)/count
		var p:=a.lerp(q,t0)-Vector3(0,.32*t0*(1-t0),0)
		var end:=a.lerp(q,t1)-Vector3(0,.32*t1*(1-t1),0)
		var tape:=b(self,(p+end)*.5,Vector3(p.distance_to(end)+.003,height,.009),"#c8b64a" if i%2==0 else "#333e36")
		tape.rotation.y=atan2(-(end.z-p.z),end.x-p.x)

func viaduct_vending() -> void:
	var n:=group(-63.09,60.16,-1.95)
	b(n,Vector3(0,.5,0),Vector3(3,1,1.9),"#8d8982",true)
	var machine:=vending_machine(-62.933,59.898,-2.25,"#b6443b",true)
	machine.position.y+=1
	var points: Array[Vector2]=[]
	for v in [Vector2(5.2,-1.8),Vector2(3.8,1.2),Vector2(2.9,3.6)]:
		points.append(Vector2(-64.3+.929*v.x-.370*v.y,58.6+.370*v.x+.929*v.y))
	fence(points[0],points[1],3,"#657e76",true)
	fence(points[1],points[2],3,"#657e76",true)
	var crate_pos:=Vector2(-64.3+.929*1.5-.370*1.4,58.6+.370*1.5+.929*1.4)
	var crate_group:=group(crate_pos.x,crate_pos.y,-1.7)
	crate(crate_group,Vector3(0,1,0),"#3a8a4a")

func stonework(parent: Node3D,width: float,depth: float,height: float,bottom: float) -> void:
	var random:=RandomNumberGenerator.new()
	random.seed=351
	for side in 4:
		var n:=Node3D.new()
		parent.add_child(n)
		n.rotation.y=side*PI/2
		var length:=width if side%2==0 else depth
		var distance:=depth*.5 if side%2==0 else width*.5
		for row in maxi(1,int(height/.35)):
			var x: float=-length*.5-.2
			while x<length*.5:
				var sw:=random.randf_range(.3,.65)
				var y:=bottom+row*.35+random.randf_range(-.04,.04)
				var st:=SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var verts: Array[Vector3]=[Vector3(x,y+.1,distance+.012),Vector3(x+sw*.28,y+.02,distance+.012),Vector3(minf(length*.5,x+sw*.95),y+.06,distance+.012),Vector3(minf(length*.5,x+sw*.87),y+.31,distance+.012),Vector3(x+sw*.17,y+.32,distance+.012)]
				for j in range(1,4): triangle(st,verts[0],verts[j],verts[j+1])
				st.generate_normals()
				var stone:=MeshInstance3D.new()
				stone.mesh=st.commit()
				stone.material_override=m(["#8d826a","#a09479","#746e59","#9b8f75"][random.randi_range(0,3)])
				n.add_child(stone)
				x+=sw
