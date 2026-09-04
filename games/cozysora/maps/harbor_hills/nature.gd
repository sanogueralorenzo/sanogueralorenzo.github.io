extends RefCounted
var map
var g
var rng=RandomNumberGenerator.new()
var tree_count=0

func build(world,geometry) -> void:
	map=world;g=geometry;rng.seed=44391
	# A contiguous wooded park on the western hill, with deliberate sightlines to the bay.
	for i in range(120):
		var x=rng.randf_range(-166,-87);var z=rng.randf_range(-30,163)
		if absf(x+104)<5 and z>43 and z<98:continue
		if Vector2(x+109,z-96).length()<16:continue
		_cypress(map.point(x,z),rng.randf_range(5.5,12),i)
	# The upper park continues to the stair landings, framing several open glades.
	for i in range(100):
		var x=rng.randf_range(-91,-18);var z=rng.randf_range(57,162)
		if absf(x+38)<5 and z<98:continue
		if Vector2(x+56,z-62).length()<11:continue
		if Vector2(x+54,z-110).length()<15:continue
		if absf(z-(75+(x+80)*.42))<4:continue
		_cypress(map.point(x,z),rng.randf_range(5.5,10),i+300)
	print("Harbor Hills park cypress: ",tree_count)
	for route in [[Vector2(-112,101),Vector2(-54,110)],[Vector2(-104,74),Vector2(-22,111)],[Vector2(-55,110),Vector2(-16,133)]]:
		var path=[]
		for i in range(42):
			var p:Vector2=route[0].lerp(route[1],i/41.0);path.append(map.point(p.x,p.y,.08))
		g.ribbon(path,3.0,"aca98c",true)
	for i in range(360):
		var x=rng.randf_range(-91,-18);var z=rng.randf_range(54,168)
		if absf(x+38)<3 and z<98:continue
		if absf(z-(75+(x+80)*.42))<2:continue
		var p=map.point(x,z)
		g.add("leaf",p+Vector3(0,.45,0),Vector3(1.5,.9,1.4),["758959","657c58","949a69"][i%3])
		for j in range(3):g.add("sphere",p+Vector3(rng.randf_range(-.4,.4),.9,rng.randf_range(-.4,.4)),Vector3(.13,.12,.13),"d2bb7c")
	# Street trees fit the planting strip, never a doorway or the rail alignment.
	for x in [-85.0,99.0]:
		for z in range(-82,130,19):_cypress(map.point(x,z),rng.randf_range(4.5,6.0),z)
	for x in range(-152,163,19):
		if absf(x-8)<10:continue
		_cypress(map.point(x,-107),rng.randf_range(4.2,6.4),x)
	for i in range(35):
		var x=rng.randf_range(132,171);var z=rng.randf_range(-73,164)
		_cypress(map.point(x,z),rng.randf_range(6,10),i)
	# Perimeter scrub and wildflowers establish a finished edge rather than an empty plane.
	for i in range(1500):
		var x=rng.randf_range(-173,173);var z=rng.randf_range(-107,171)
		if x>-83 and x<128 and z<136:continue
		if (absf(x+104)<3 or absf(x+38)<3) and z>44 and z<95:continue
		var p=map.point(x,z)
		g.add("leaf",p+Vector3(0,.3,0),Vector3(rng.randf_range(.6,1.5),rng.randf_range(.4,1.1),rng.randf_range(.6,1.5)),["677f5a","89946a","55765b","9b9c6e"][i%4])
		if i%3==0:
			for j in range(4):g.add("sphere",p+Vector3(rng.randf_range(-.5,.5),.6+rng.randf()*.3,rng.randf_range(-.5,.5)),Vector3(.12,.12,.12),["d3bf80","b9979c","ddd3a8"][i%3])
	# A composed overlook with a low wall, relief plaque and warm stone terraces.
	var p=map.point(-110,99)
	g.add("cylinder",p-Vector3(0,.12,0),Vector3(21,.3,17),"b3ae93",Vector3.ZERO,true)
	for i in range(25):
		var angle=PI*.12+i/24.0*PI*.77
		var a=p+Vector3(sin(angle)*10,0,cos(angle)*8)
		g.box(a+Vector3(0,.5,0),Vector3(.9,1.0,1),"969c8b",true,angle)
	g.box(p+Vector3(-3,.85,-3),Vector3(2.8,.16,1),"627c71",false,0)
	g.label("THE LONG WAY HOME\nHARBOR HILLS OVERLOOK",p+Vector3(-3,.98,-2.45),2.3,"e5d8b5",0,52)
	for i in range(4):g.add("leaf",p+Vector3(-8+i*.6,.6,-5),Vector3(1.1,1.1,1.1),"879666")
	_skyline_and_bridge()
	_boats()
	_grass()

func _cypress(p:Vector3,h:float,index:int) -> void:
	tree_count+=1
	var lean=Vector3(-h*.16,0,h*.03)
	g.beam(p,p+lean+Vector3(0,h*.75,0),h*.031,"776e59")
	g.box_collision(p+lean*.35+Vector3.UP*h*.3,Vector3(h*.075,h*.6,h*.075))
	for i in range(5):
		var phase=i*2.39+index*.38
		var tip=p+Vector3(cos(phase)*h*.25,h*(.52+i*.085),sin(phase)*h*.2)+lean
		g.beam(p+Vector3(0,h*.4,0)+lean*.6,tip,h*.018,"776e59")
		for j in range(12):
			var a=rng.randf()*TAU;var r=sqrt(rng.randf())*h*.19
			var at=tip+Vector3(cos(a)*r,rng.randf_range(-.3,.3)*h*.12,sin(a)*r)
			var size=rng.randf_range(.65,1.25)*h*.22
			g.add("leaf",at,Vector3(size*1.4,size*.39,size),["456750","527459","365d50","638060"][j%4],Vector3(0,a,rng.randf_range(-.1,.1)))

func _skyline_and_bridge() -> void:
	# Distant fictional city blocks remain outside the playable 360 m district.
	# The far shore grounds the skyline in a continuous muted land silhouette.
	g.add("sphere",Vector3(350,-3,-336),Vector3(550,25,90),"637f86")
	for center in [-384.0,-121.0]:
		var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ix in range(28):
			for iz in range(36):
				var positions=[]
				for offset in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
					var x=center-84+(ix+offset.x)*6;var z=-498+(iz+offset.y)*6
					var slope=sin(clampf((x-center+84)/168.0,0,1)*PI)
					var y=-3+37*slope*smoothstep(-280,-360,z)
					positions.append(Vector3(x,y,z))
				for j in [0,1,2,0,2,3]:st.add_vertex(positions[j])
		st.generate_normals();var n=MeshInstance3D.new();n.mesh=st.commit();n.material_override=g.material("788f92");g.root.add_child(n)
	for i in range(65):
		var x=180+i*5.8;var z=-310+rng.randf_range(-20,20);var h=rng.randf_range(9,43)
		if i%13==0:h*=1.5
		g.box(Vector3(x,h*.5-1,z),Vector3(rng.randf_range(4,8),h,7),["687f89","7b9298","576f7b"][i%3])
		if i%6==0:g.box(Vector3(x,h+1,z),Vector3(2,2,3),"91a4a7")
	# A red suspension bridge silhouette, deliberately fictional in its proportions.
	var z=-315.0;var left=-365.0;var right=-135.0
	g.box(Vector3((left+right)*.5,16,z),Vector3(right-left,.9,8),"986f61")
	for x in [-310.0,-195.0]:
		for side in [-1,1]:
			g.box(Vector3(x,28,z+side*3.8),Vector3(2.6,60,2.6),"a77e6c")
		for y in [21.0,38.0,54.0]:g.box(Vector3(x,y,z),Vector3(2.5,1.5,10),"a77e6c")
	for side in [-1,1]:
		for section in [[left,-310.0],[-310.0,-195.0],[-195.0,right]]:
			var prev=Vector3.ZERO
			for i in range(33):
				var t=i/32.0;var x=lerpf(section[0],section[1],t);var height=55-33*sin(t*PI)
				if section[0]==left:height=lerpf(18,55,t)
				if section[1]==right:height=lerpf(55,18,t)
				var at=Vector3(x,height,z+side*4)
				if i>0:g.beam(prev,at,.18,"a78779")
				if i%2==0:g.beam(Vector3(x,16,z+side*4),at,.055,"a78779")
				prev=at

func _boats() -> void:
	for i in range(13):
		var p=Vector3(-130+i*22,-.2,-151-rng.randf()*70)
		g.add("sphere",p,Vector3(2.3,.9,6.8),["d2d6c6","75918b","bb9c7c"][i%3])
		g.box(p+Vector3(0,.55,.35),Vector3(1.7,.75,2.3),"d9d6be")
		g.box(p+Vector3(0,.7,1.55),Vector3(1.5,.42,.04),"6b8a90")
		if i%2==0:
			g.beam(p,p+Vector3(0,8,0),.055,"a3aaa0")
			var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for v in [p+Vector3(.08,7.8,0),p+Vector3(.08,1.4,0),p+Vector3(.08,1.4,3.6)]:st.add_vertex(v)
			st.generate_normals();var n=MeshInstance3D.new();n.mesh=st.commit();n.material_override=g.material("dddaca");g.root.add_child(n)
			g.beam(p+Vector3(0,1.4,0),p+Vector3(0,1.4,3.6),.04,"a3aaa0")

func _grass() -> void:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(3):
		var angle=i*PI/3;var turn=Basis(Vector3.UP,angle)
		var h=.48+i*.08
		var a=Vector3(-.045,0,0);var b=Vector3(.045,0,0);var c=Vector3(-.022,h*.6,.07);var d=Vector3(.022,h*.6,.07);var tip=Vector3(.04,h,.17)
		for v in [a,b,c,b,d,c,c,d,tip]:st.add_vertex(turn*v)
	st.generate_normals();var blade=st.commit();var positions=[]
	for i in range(520000):
		var x=rng.randf_range(-172,172);var z=rng.randf_range(-106,170)
		if x>-87 and x<131 and z<136 and not (x<-18 and z>53):continue
		if (absf(x+104)<3 or absf(x+38)<3) and z>44 and z<95:continue
		if absf(x+147-sin(z*.018)*9)<2.5 or absf(x-151-sin(z*.018)*9)<2.5:continue
		if Vector2(x+110,z-99).length()<12 or Vector2(x+56,z-62).length()<9:continue
		if x>-108 and x<-18 and absf(z-(75+(x+80)*.42))<2:continue
		positions.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.4,1.1)),map.point(x,z)))
	# Spatial grass batches let the renderer discard fields outside the camera frustum.
	var cells={}
	for transform in positions:
		var cell=Vector2i(floori(transform.origin.x/32),floori(transform.origin.z/32))
		if not cells.has(cell):cells[cell]=[]
		cells[cell].append(transform)
	var mat=ShaderMaterial.new();mat.shader=load("res://maps/harbor_hills/leaves.gdshader");mat.set_shader_parameter("base_color",Color("8b9668"))
	for cell in cells:
		var origin=Vector3(cell.x*32+16,0,cell.y*32+16)
		var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=blade;mm.instance_count=cells[cell].size()
		for i in mm.instance_count:
			var transform:Transform3D=cells[cell][i];transform.origin-=origin;mm.set_instance_transform(i,transform)
		var n=MultiMeshInstance3D.new();n.name="Wind grass";n.multimesh=mm;n.position=origin;n.material_override=mat;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;g.root.add_child(n)
	print("Harbor Hills vegetation: ",tree_count," cypress, ",positions.size()," grass clumps in ",cells.size()," batches")
