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
		if _on_path(x,z,4):continue
		_cypress(map.point(x,z),rng.randf_range(5.5,10),i+300)
	# Taller rounded street crowns cast broken shade over the pavement.
	for x in [-.6,17.0]:
		for z in [-92.0,-49.0,-18.0,28.0,66.0,120.0]:
			_street_tree(map.point(x,z),rng.randf_range(6.2,8.0))
	for z in [-74.,-57.,-12.,24.,70.]:_street_tree(map.point(12.65,z),rng.randf_range(6.2,7.5))
	for x in [-65.0,-35.0,38.0,67.0,114.0]:
		for z in [-110.0,-39.0,53.0]:
			if z==53.0 and x<0:continue
			_street_tree(map.point(x,z),rng.randf_range(5.2,7.2))
	print("Harbor Hills park and street trees: ",tree_count)
	for route in [[Vector2(-112,101),Vector2(-54,110)],[Vector2(-104,74),Vector2(-22,111)],[Vector2(-55,110),Vector2(-16,133)]]:
		var path=[]
		for i in range(42):
			var p:Vector2=route[0].lerp(route[1],i/41.0);path.append(map.point(p.x,p.y,.08))
		g.ribbon(path,3.0,"aca98c",true)
	for i in range(360):
		var x=rng.randf_range(-91,-18);var z=rng.randf_range(54,168)
		if absf(x+38)<3 and z<98:continue
		if _on_path(x,z,2):continue
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
	for x in [31.0,53.0,75.0]:
		for z in [128.0,154.0]:_street_tree(map.point(x,z),rng.randf_range(6.2,8.2))
	# Perimeter scrub and wildflowers establish a finished edge rather than an empty plane.
	for i in range(1500):
		var x=rng.randf_range(-173,173);var z=rng.randf_range(-107,171)
		if x>-83 and x<128 and z<136:continue
		if (absf(x+104)<3 or absf(x+38)<3) and z>44 and z<95:continue
		var p=map.point(x,z)
		g.add("leaf",p+Vector3(0,.3,0),Vector3(rng.randf_range(.6,1.5),rng.randf_range(.55,1.3),rng.randf_range(.6,1.5)),["677f5a","89946a","55765b","9b9c6e"][i%4])
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
			g.add("leaf",at,Vector3(size*1.4,size*.68,size),["416c42","557c45","365e46","6b874e"][j%4],Vector3(0,a,rng.randf_range(-.1,.1)))

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
	for i in range(14):
		var p=Vector3(-130+i*22,-.35,-151-rng.randf()*70)
		if i==0:p=Vector3(-123.7,-.35,-143)
		var yaw=rng.randf_range(-.35,.35)
		var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sections=[Vector3(0,.18,-3.9),Vector3(.82,-.34,-2.3),Vector3(1.12,-.5,0),Vector3(.94,-.4,2.4),Vector3(.76,-.2,3.1)]
		for j in range(sections.size()-1):
			for side in [-1,1]:
				var a:Vector3=sections[j];var b:Vector3=sections[j+1]
				var ring_a=[Vector3(a.x*side,.55,a.z),Vector3(a.x*.72*side,-.07,a.z),Vector3(0,a.y,a.z)]
				var ring_b=[Vector3(b.x*side,.55,b.z),Vector3(b.x*.72*side,-.07,b.z),Vector3(0,b.y,b.z)]
				for band in range(2):
					for v in [ring_a[band],ring_b[band],ring_b[band+1],ring_a[band],ring_b[band+1],ring_a[band+1]]:st.add_vertex(v)
		st.generate_normals();var n=MeshInstance3D.new();n.mesh=st.commit();n.position=p;n.rotation.y=yaw
		var mat=StandardMaterial3D.new();mat.albedo_color=Color(["d8d9bf","72958b","b56d50"][i%3]);mat.cull_mode=BaseMaterial3D.CULL_DISABLED;n.material_override=mat;g.root.add_child(n)
		var turn=Basis(Vector3.UP,yaw)
		g.box(p+turn*Vector3(0,.32,.2),Vector3(1.55,.12,5.1),"9c896a",false,yaw)
		g.box(p+turn*Vector3(0,.76,-.7),Vector3(1.45,.82,2.2),"ded7b9",false,yaw)
		g.box(p+turn*Vector3(0,.9,-1.83),Vector3(1.2,.35,.035),"537f89",false,yaw)
		for side in [-1,1]:
			var previous=p+turn*Vector3(0,.62,-3.9)
			for section in sections.slice(1):
				var next=p+turn*Vector3(section.x*side,.62,section.z);g.beam(previous,next,.045,"d3c39e");previous=next
			g.box(p+turn*Vector3(side*.92,.62,1.65),Vector3(.22,.18,2.1),"c6b291",false,yaw)
		if i%2==0:
			g.beam(p+turn*Vector3(0,.4,-.8),p+turn*Vector3(0,8.9,-.8),.046,"b3b6a0")
			g.beam(p+turn*Vector3(0,1.7,-.8),p+turn*Vector3(0,1.7,2.8),.035,"b3b6a0")
			var sail=SurfaceTool.new();sail.begin(Mesh.PRIMITIVE_TRIANGLES)
			for row in range(12):
				var t=row/12.;var t1=(row+1)/12.
				var corners=[Vector3(.07,1.8+t*6.8,-.8),Vector3(.07+sin(t*PI)*.24,1.8+t*6.8,2.6-t*3.4),Vector3(.07+sin(t1*PI)*.24,1.8+t1*6.8,2.6-t1*3.4),Vector3(.07,1.8+t1*6.8,-.8)]
				for j in [0,1,2,0,2,3]:sail.add_vertex(corners[j])
			sail.generate_normals();n=MeshInstance3D.new();n.mesh=sail.commit();n.position=p;n.rotation.y=yaw
			mat=StandardMaterial3D.new();mat.albedo_color=Color("e6dfc4");mat.cull_mode=BaseMaterial3D.CULL_DISABLED;n.material_override=mat;g.root.add_child(n)
			g.beam(p+turn*Vector3(0,8.8,-.8),p+turn*Vector3(0,.6,-3.8),.011,"a6afa6")
		g.add("sphere",p+Vector3(3,.4,2),Vector3(.4,.5,.4),"ce9472")

func _grass() -> void:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		st.set_color(Color(1.-i*.045,1.-i*.025,1.-i*.035))
		var angle=i*2.399;var turn=Basis(Vector3.UP,angle)
		var h=.52+(i%3)*.13
		var a=Vector3(-.063,0,0);var b=Vector3(.063,0,0);var c=Vector3(-.039,h*.6,.14);var d=Vector3(.039,h*.6,.14);var tip=Vector3(.08,h,.32)
		for v in [a,b,c,b,d,c,c,d,tip]:st.set_uv(Vector2(0,v.y/h));st.add_vertex(turn*v)
	st.generate_normals();var blade=st.commit();var positions=[]
	for i in range(700000):
		var x=rng.randf_range(-172,172);var z=rng.randf_range(-106,170)
		var core=x>-87 and x<131 and z<136 and not (x<-18 and z>53)
		var verge=(z>53 and z<59 and x>-17 and x<79) or (z>40.5 and z<44.0 and x>-69 and x<81) or (z>111 and z<135 and x>23 and x<81)
		if core and not verge:continue
		var paved=false
		for road_x in map.STREETS_X:
			if absf(x-road_x)<8.5 and z<136:paved=true
		for road_z in map.STREETS_Z:
			if absf(z-road_z)<8.5 and x>-121 and x<130:paved=true
		if paved:continue
		if absf(map.height_at(x,z)-map.terrain_height(x,z))>.1:continue
		if (absf(x+104)<3 or absf(x+38)<3) and z>44 and z<95:continue
		if absf(x+147-sin(z*.018)*9)<2.5 or absf(x-151-sin(z*.018)*9)<2.5:continue
		if Vector2(x+110,z-99).length()<12 or Vector2(x+56,z-62).length()<9:continue
		if _on_path(x,z,2):continue
		positions.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.55,1.3)),map.point(x,z)))
	# Spatial grass batches let the renderer discard fields outside the camera frustum.
	var cells={}
	for transform in positions:
		var cell=Vector2i(floori(transform.origin.x/32),floori(transform.origin.z/32))
		if not cells.has(cell):cells[cell]=[]
		cells[cell].append(transform)
	var mat=ShaderMaterial.new();mat.shader=load("res://shaders/grass.gdshader");mat.set_shader_parameter("grass_base",Vector3(.18,.29,.12));mat.set_shader_parameter("grass_mid",Vector3(.32,.43,.18));mat.set_shader_parameter("grass_tip",Vector3(.54,.55,.29))
	for cell in cells:
		var origin=Vector3(cell.x*32+16,0,cell.y*32+16)
		var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=blade;mm.instance_count=cells[cell].size()
		for i in mm.instance_count:
			var transform:Transform3D=cells[cell][i];transform.origin-=origin;mm.set_instance_transform(i,transform)
		var n=MultiMeshInstance3D.new();n.name="Wind grass";n.visibility_range_end=110;n.visibility_range_end_margin=12;n.multimesh=mm;n.position=origin;n.material_override=mat;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;g.root.add_child(n)
	print("Harbor Hills vegetation: ",tree_count," cypress, ",positions.size()," grass clumps in ",cells.size()," batches")

func _on_path(x:float,z:float,width:float) -> bool:
	var p=Vector2(x,z)
	for route in [[Vector2(-112,101),Vector2(-54,110)],[Vector2(-104,74),Vector2(-22,111)],[Vector2(-55,110),Vector2(-16,133)]]:
		var a:Vector2=route[0];var b:Vector2=route[1];var line=b-a
		if p.distance_to(a+line*clampf((p-a).dot(line)/line.length_squared(),0,1))<width:return true
	return false

func _street_tree(p:Vector3,h:float) -> void:
	tree_count+=1
	g.beam(p,p+Vector3(.18,h*.72,-.1),.13,"716d4e")
	g.box_collision(p+Vector3(0,h*.3,0),Vector3(.26,h*.6,.26))
	for branch in range(5):
		var angle=branch*2.399
		var tip=p+Vector3(cos(angle)*1.2,h*(.7+rng.randf()*.18),sin(angle)*1.2)
		g.beam(p+Vector3(0,h*.47,0),tip,.075,"716d4e")
		for j in range(9):
			var a=rng.randf()*TAU;var r=sqrt(rng.randf())*1.2
			g.add("leaf",tip+Vector3(cos(a)*r,rng.randf_range(-.6,.8),sin(a)*r),Vector3(1.6,1.8,1.6),["628641","487740","789448","3c7148"][j%4],Vector3(0,a,0))
