extends CozyMap
## A single 135 m coastal neighborhood. Layout, dressing and activities are local.
const Geometry = preload("res://maps/sunny_bay/geometry.gd")
const Architecture = preload("res://maps/sunny_bay/architecture.gd")
const Planting = preload("res://maps/sunny_bay/planting.gd")
const ATMOSPHERE = preload("res://maps/sunny_bay/atmosphere.tres")
const LOOP = [Vector2(0,8),Vector2(-18,14),Vector2(-24,35),Vector2(-24,48),Vector2(-18,70),Vector2(6,80),Vector2(35,78),Vector2(48,54),Vector2(42,30),Vector2(22,9),Vector2(0,8)]
const PIER = Vector3(-8,2,-19)
var geo
var architecture
var paths: Array = []
var static_content: Node3D
var boats: Array[Node3D] = []
var elapsed := 0.0

func build() -> void:
	supports_surface_traversal = true
	flight_bounds = AABB(Vector3(-83,-.3,-55),Vector3(166,95,205))
	ambience = {"wind_gain":.12,"wave_base":.033,"wave_swell":.016,"cicada_frequencies":Vector2(3200,3600),"cicada_gain":.004,"birds":true}
	ATMOSPHERE.install(self)
	for child in get_children():
		if child is WorldEnvironment:
			var sky_material=ShaderMaterial.new()
			sky_material.shader=preload("res://maps/sunny_bay/sky.gdshader")
			child.environment.sky.sky_material=sky_material
	load_progress.emit("Following the coast to Sunny Bay…",.1)
	await get_tree().process_frame
	static_content = Node3D.new()
	static_content.name = "Sunny Bay town"
	add_child(static_content)
	geo = Geometry.new(static_content)
	geo.ground_height = height_at
	_terrain()
	_routes()
	load_progress.emit("Opening the café terraces…",.35)
	await get_tree().process_frame
	architecture = Architecture.new()
	architecture.build(self,geo)
	_waterfront()
	_garden()
	load_progress.emit("Finding shade beneath the trees…",.65)
	await get_tree().process_frame
	Planting.new().build(self,geo)
	_edge_details()
	_landmarks()
	geo.finish()
	ATMOSPHERE.install_post(self)
	load_progress.emit("Take the long way home.",1.0)

func terrain_height(_x: float,z: float) -> float:
	return 2 + 4*smoothstep(16,34,z) + 6*smoothstep(48,70,z) + 2*smoothstep(94,116,z)

func coast_distance(x: float,z: float) -> float:
	return minf(z+2+3*sin(x*.035), 66+8*sin(z*.037)-absf(x))

func height_at(x: float,z: float) -> float:
	if absf(x+8)<2.5 and z>=-23 and z<3: return 2.0
	if x>22 and x<32 and z>-6.4 and z<3: return lerpf(1.23,2.0,smoothstep(-1.6,2,z))
	var d = coast_distance(x,z)
	var h = lerpf(-4.0,terrain_height(x,z),smoothstep(-5,0,d))
	# The pond is a shallow, contained depression; its banks join the garden grade.
	var pond = Vector2((x-3)/7.2,(z-68)/4.8).length()
	if pond<1.15: h-=1.05*(1-smoothstep(.85,1.15,pond))
	return h

func walkable(x: float,z: float) -> bool:
	if absf(x+8)<2.23 and z>=-22.6 and z<4: return true
	if x>22.4 and x<31.6 and z>-6.1 and z<4: return true
	if coast_distance(x,z)<1.1 or z>132: return false
	return Vector2((x-3)/7.8,(z-68)/5.4).length()>1.0

func point(x: float,z: float,lift: float=0) -> Vector3:
	return Vector3(x,height_at(x,z)+lift,z)

func _terrain() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(174):
		for ix in range(180):
			var x = -90.0+ix
			var z = -25.0+iz
			for off in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.ZERO,Vector2.ONE,Vector2.DOWN]:
				var p = Vector2(x,z)+off
				# Harbor platform is built separately over the water.
				var h = lerpf(-4.0,terrain_height(p.x,p.y),smoothstep(-5,0,coast_distance(p.x,p.y)))
				if p.y>0: h=height_at(p.x,p.y)
				st.add_vertex(Vector3(p.x,h,p.y))
	st.generate_normals()
	var mesh = st.commit()
	var ground_material=ShaderMaterial.new()
	ground_material.shader=preload("res://maps/sunny_bay/ground.gdshader")
	CozyPrimitives.instance(static_content,mesh,Vector3.ZERO,ground_material)
	CozyCollision.mesh(geo.collision,mesh)
	# Continuous hinterland, with a soft ridge behind the last houses.
	geo.add("sphere",Vector3(-15,0,205),Vector3(260,48,180),"829a83")
	geo.add("sphere",Vector3(-100,-5,310),Vector3(350,75,230),"8fa69b")
	for i in range(38):
		var z = i*3.7
		for side in [-1,1]:
			var x = side*(66+8*sin(z*.037))
			geo.add("sphere",Vector3(x-1.2*side,terrain_height(x,z)*.32,z),Vector3(5.5,terrain_height(x,z)*1.4,5.7),["989785","aaa28b","888f7a"][i%3])

func route(points: Array,width: float,color: String="cec4a7",finish: String="paving") -> void:
	var sampled: Array=[]
	for i in range(points.size()-1):
		var a: Vector2=points[i]
		var b: Vector2=points[i+1]
		var steps=ceili(a.distance_to(b)/.75)
		for j in range(steps):
			var v=a.lerp(b,float(j)/steps)
			sampled.append(point(v.x,v.y,.12))
	var end: Vector2=points[-1]
	sampled.append(point(end.x,end.y,.12))
	geo.ribbon(sampled,width,color,true,true,finish)
	paths.append({"points":points,"width":width})

func on_path(p: Vector2,margin: float=0) -> bool:
	for path in paths:
		for i in range(path.points.size()-1):
			var a: Vector2=path.points[i]
			var b: Vector2=path.points[i+1]
			var t=clampf((p-a).dot(b-a)/(b-a).length_squared(),0,1)
			if p.distance_to(a.lerp(b,t))<path.width*.5+margin:return true
	return false

func _routes() -> void:
	route(LOOP.slice(0,7),4.8)
	route(LOOP.slice(6),5.4,"b0ac98")
	route([Vector2(-51,8),Vector2(-8,8),Vector2(22,9),Vector2(51,15)],7)
	route([Vector2(-45,39),Vector2(-24,39),Vector2(5,39),Vector2(30,42)],6)
	route([Vector2(-18,70),Vector2(-11,59),Vector2(7,57),Vector2(17,64),Vector2(17,75),Vector2(6,80)],2.8)
	route([Vector2(35,78),Vector2(49,85),Vector2(57,78)],3.2)
	route([Vector2(-24,48),Vector2(-43,55),Vector2(-45,73),Vector2(-18,70)],2.6)
	# Low stair noses over the same continuous collision ramp prevent cat snagging.
	for i in range(32):
		var z=18+i*.47
		var center=Vector2(-18,14).lerp(Vector2(-24,35),(z-14)/21)
		var top=height_at(center.x,z+.23)+.15
		geo.box(Vector3(center.x,top-.12,z),Vector3(4.8,.24,.48),"d7ccb0",false,0,"paving")
		for side in [-1,1]:
			geo.box(Vector3(center.x+side*2.65,top+.18,z),Vector3(.38,.6,.5),"c3bda5",true,0,"brick")
	for i in range(36):
		var z=50+i*.49
		var x=-24+(z-48)/22*6
		var top=height_at(x,z+.245)+.15
		geo.box(Vector3(x,top-.16,z),Vector3(4.8,.32,.5),"d7ccb0")
		for side in [-1,1]:
			geo.box(Vector3(x+side*2.65,top+.18,z),Vector3(.38,.6,.52),"c3bda5",true,0,"brick")
	# A small, level transit stop belongs to the café street, away from the main climb.
	for x in [-6.2,-5.3]:
		geo.ribbon([point(x,34,.075),point(x,44,.075)],.07,"677a76")

func rail(a: Vector3,b: Vector3) -> void:
	geo.beam(a+Vector3.UP*.85,b+Vector3.UP*.85,.035,"627d76")
	geo.beam(a+Vector3.UP*.43,b+Vector3.UP*.43,.025,"627d76")
	var n=ceili(a.distance_to(b)/1.5)
	for i in range(n+1):
		var p=a.lerp(b,float(i)/n)
		geo.beam(p,p+Vector3.UP*.88,.035,"627d76")
	# One continuous narrow barrier, matching the visual railing.
	var d=b-a
	geo.box_collision((a+b)*.5+Vector3.UP*.43,Vector3(.09,.86,d.length()),Vector3(0,atan2(d.x,d.z),0))

func _waterfront() -> void:
	# Last Cast's timber pier, mooring cleats, berth ladder and tied boats, scaled for this town.
	geo.box(Vector3(-8,1.78,-10),Vector3(5,.44,26),"a58a62",true,0,"siding")
	for z in range(-22,3):
		geo.box(Vector3(-8,2.012,z),Vector3(4.92,.025,.045),"726951")
	for x in [-10.25,-5.75]:
		for z in [-21,-15,-9,-3]:
			geo.add("cylinder",Vector3(x,.6,z),Vector3(.24,3.4,.24),"796e56")
			geo.beam(Vector3(x,2.14,z)-Vector3.RIGHT*.17,Vector3(x,2.14,z)+Vector3.RIGHT*.17,.055,"425e5c")
		rail(Vector3(x,2,-21),Vector3(x,2,-3))
	# South end is the fishing opening; a low bumper keeps paws on the pier.
	geo.box(Vector3(-8,2.14,-22.65),Vector3(4.9,.28,.18),"85785b",true)
	for x in range(-49,52,4):
		var z=-.1-3*sin(x*.035)
		if absf(x+8)<4 or (x>21 and x<33):continue
		geo.box(Vector3(x,.4,z),Vector3(4.05,3.3,1.3),"a5a38e",true,0,"brick")
		geo.box(Vector3(x,2.13,z),Vector3(4.1,.18,1.55),"dfd4b6")
		if absf(x+8)>6:
			geo.add("cylinder",Vector3(x,2.45,z),Vector3(.3,.55,.3),"51736d")
	# Landing, with stairs cut into its shore side and a stationary skiff.
	geo.box(Vector3(27,1.05,-4),Vector3(10,.35,5),"b8b09a",true)
	geo.ribbon([Vector3(27,1.24,-1.6),Vector3(27,2.06,2.4)],3,"cfc5ab",true,false)
	for i in range(8):
		geo.box(Vector3(27,1.25+i*.1,-1.5+i*.5),Vector3(3,.06,.12),"e5d8b7")
	_boat(Vector3(25,.2,-10),.3,"709e9b")
	_boat(Vector3(-16,.2,-12),-.2,"d2a177")
	_boat(Vector3(42,.2,-27),1.0,"789dae",true)
	for z in [-7,-6.6,-6.2,-5.8]:geo.beam(Vector3(31.9,.1,z),Vector3(31.9,1.3,z),.025,"607b76")
	geo.label("SUNNY BAY",Vector3(-27,3.2,1.1),5,"f7e9c9",PI)
	architecture.bench(point(-35,5),PI)
	architecture.pergola(point(7,4),Vector2(8,4))
	architecture.bench(point(7,4),PI)

func _boat(p: Vector3,yaw: float,color: String,sail: bool=false) -> void:
	var basis=Basis(Vector3.UP,yaw)
	geo.add("sphere",p,Vector3(2.5,.95,6),color,Vector3(0,yaw,0))
	geo.box(p+Vector3.UP*.4,Vector3(1.9,.14,4.6),"d8c7a4",false,yaw)
	for z in [-1.4,0,1.4]:geo.box(p+basis*Vector3(0,.6,z),Vector3(2,.12,.35),"8c795a",false,yaw)
	if sail:
		geo.beam(p,p+Vector3.UP*7,.055,"c4ad7c")
		geo.cloth(p+Vector3.UP*6.8,Vector2(3.3,4.6),"efe2bd",yaw)

func _garden() -> void:
	var pond=PlaneMesh.new()
	pond.size=Vector2(13.7,8.8)
	var mat=ShaderMaterial.new()
	mat.shader=preload("res://maps/sunny_bay/pond.gdshader")
	# Elliptical surface avoids exposed square water corners beyond the bank.
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		for a in [-1,i,i+1]:
			var p=Vector3(3,11.05,68) if a==-1 else Vector3(3+cos(a*TAU/64)*6.9,11.05,68+sin(a*TAU/64)*4.5)
			st.add_vertex(p)
	st.generate_normals()
	CozyPrimitives.instance(static_content,st.commit(),Vector3.ZERO,mat)
	for i in range(42):
		var a=i*TAU/42
		geo.add("sphere",point(3+cos(a)*7.6,68+sin(a)*5.2,.12),Vector3(.95,.45,.8),["aaa890","909b81","bbc0a0"][i%3])
	for i in range(13):
		var a=i*2.4
		geo.add("cylinder",Vector3(3+cos(a)*4,11.08,68+sin(a)*2.7),Vector3(.65,.02,.65),"699466")
	architecture.pergola(point(-10,83),Vector2(8,5))
	architecture.bench(point(-10,83),PI)
	architecture.bench(point(15,80),PI)
	architecture.bench(point(53,80),PI*.65)
	rail(point(54,74),point(60,82))
	# Safe open overlook with a broad turning area and continuous coastal view.
	geo.add("cylinder",point(56,78,-.1),Vector3(9,.3,8),"ccc2a3")

func _landmarks() -> void:
	for info in [[Vector2(-15,12),"CAFÉ STREET ↑"],[Vector2(-19,46),"GARDEN ↑"],[Vector2(31,79),"COAST WALK →"],[Vector2(43,28),"HARBOR ↓"]]:
		var p=point(info[0].x,info[0].y)
		geo.beam(p,p+Vector3.UP*1.65,.055,"7d795f")
		geo.box(p+Vector3.UP*1.45,Vector3(1.8,.45,.1),"496d68")
		geo.label(info[1],p+Vector3(0,1.45,-.065),1.6,"f4e6c5",PI,48)
	# One ochre bell tower connects all elevations in the town silhouette.
	var p=point(-33,91)
	geo.box(p+Vector3.UP*5,Vector3(4,10,4),"d5b879",true)
	geo.box(p+Vector3.UP*10.1,Vector3(4.6,.3,4.6),"e4d5ae",true)
	for dx in [-1.4,1.4]:
		for dz in [-1.4,1.4]:geo.box(p+Vector3(dx,11.2,dz),Vector3(.32,2,.32),"e8dab7")
	geo.box(p+Vector3.UP*12.35,Vector3(4.7,.5,4.7),"ac7759",true)
	geo.add("sphere",p+Vector3.UP*11,Vector3(.8,1.2,.8),"697c66")
	for x in range(-52,40,9):
		architecture.lamp(point(x,12))
	for p2 in [Vector2(-29,43),Vector2(-25,72),Vector2(22,80),Vector2(45,46)]:architecture.lamp(point(p2.x,p2.y))

func _edge_details() -> void:
	# Pale boundary stones sit outside the walking corridor and tie the paths together.
	for path in paths:
		for i in range(path.points.size()-1):
			var a: Vector2=path.points[i];var b: Vector2=path.points[i+1]
			var side=(b-a).normalized().orthogonal()
			var count=ceili(a.distance_to(b)/1.1)
			for j in range(count):
				var center=a.lerp(b,(j+.5)/count)
				for sign_value in [-1,1]:
					var p=center+side*(path.width*.5+.16)*sign_value
					if on_path(p,.03):continue
					if (p.y>17 and p.y<35 and absf(p.x+23)<6) or (p.y>49 and p.y<69 and p.x< -13):continue
					geo.box(point(p.x,p.y,.12),Vector3(.24,.19,1.08),"c4bfa5",false,atan2(side.x,side.y)+PI*.5,"brick")
	# The road's sea edge has low stone posts and connecting timber rails.
	var previous=Vector3.ZERO
	for i in range(26):
		var z=19+i*2.4
		var x=49+6*sin((z-20)*.052)
		var p=point(x,z)
		geo.box(p+Vector3.UP*.45,Vector3(.4,.9,.4),"c9c4aa",true)
		if previous!=Vector3.ZERO:geo.beam(previous+Vector3.UP*.7,p+Vector3.UP*.7,.06,"a1a187")
		previous=p
	# Climbing vines soften the terrace retaining faces and frame the stairs.
	for i in range(26):
		var z=19+i*1.9
		var x=-24-(3.5 if i%2==0 else -3.5)
		if on_path(Vector2(x,z),.45):continue
		geo.add("leaf",point(x,z,.48),Vector3(1,.9,1),["5c824f","718a4b"][i%2])
