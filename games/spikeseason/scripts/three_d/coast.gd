extends Node3D
## Dimensional coastal scenery. Geometry, leaf images and material variation are local.
const G=preload("res://scripts/three_d/geometry.gd")
const Leaf=preload("res://scripts/leaf_painter.gd")
var rng:=RandomNumberGenerator.new()
var materials:Dictionary={}
var leaf_texture:Texture2D
var canopy:Mesh

func mat(hex:String,pattern:int=0,grain:float=0.12) -> Material:
	var key:=hex+str(pattern)+str(grain)
	if not materials.has(key): materials[key]=G.surface(Color(hex),pattern,grain)
	return materials[key]

func _ready() -> void:
	rng.seed=17381
	make_foliage()
	# A low promenade separates the court from the stepped neighborhood.
	G.box(self,Vector3(4,-0.08,-11),Vector3(27,0.36,5.8),mat("c7b99b",5))
	G.box(self,Vector3(6,-2.2,-15),Vector3(30,4.6,9),mat("b4a58a",2))
	# Cut the retaining terraces around their stairs, so the steps are not buried.
	terrace(-7.5,31.5,-32,-18,4.65,8.65,11.55,-25,"b4a891")
	terrace(-4.5,38.5,-47,-31,9.3,11.2,14.0,-38,"b7ad97")
	var palette:=["e6c3a7","ebd0a7","ce998b","dfa98a","bdc2b4","eddbb5"]
	for row in range(3):
		for col in range(5):
			var x:float=-1.8+col*5.9+row*2.6
			# Leave a winding public stair through the composition.
			if col==2: continue
			var z:float=-16-row*12.1+rng.randf_range(-1.2,1.2)
			var y:float=[0.2,4.65,9.3][row]
			building(Vector3(x,y,z),Vector3(rng.randf_range(4.4,5.4),rng.randf_range(4.1,5.7) if row==0 else rng.randf_range(5.2,8.2),4.4),palette[(row*3+col)%palette.size()],row==0 and col==0)
	stairs(Vector3(10.1,0.15,-11.7),21,0.215,0.60,2.6)
	G.box(self,Vector3(11.35,4.57,-24.9),Vector3(5.2,0.16,1.6),mat("c8bfa5",5))
	stairs(Vector3(12.6,4.65,-25.6),21,0.22,0.60,2.4)
	for p in [Vector3(-4.5,0.15,-11),Vector3(1.8,0.15,-11),Vector3(17.8,0.15,-11),Vector3(2.5,4.6,-24),Vector3(19.5,4.6,-24)]:
		tree(p,rng.randf_range(0.66,0.91))
	# Framing trunks stand beyond playable space; overhead crowns cast leaf shadows.
	tree(Vector3(-7.9,0,5.5),1.20)
	tree(Vector3(8.2,0,6.5),1.27)
	tree(Vector3(-8.3,0,-3.8),1.08)
	tree(Vector3(8.7,0,-3.2),1.12)
	# Irregular planted pockets leave intervals of open railing and court sightlines.
	for i in range(11):
		var z:float=-9.5+i*1.9+rng.randf_range(-0.45,0.45)
		var radius:=rng.randf_range(0.24,0.43)
		planter(Vector3(6.65+rng.randf_range(-0.12,0.25),0.04,z),radius,rng.randf_range(0.29,0.53),i%3==0)
		if i%3==0:
			planter(Vector3(6.4,0.04,z+0.52),0.20,0.23,true)
		if i%2==0: planter(Vector3(-6.55,0.04,z+0.8),rng.randf_range(0.26,0.42),rng.randf_range(0.25,0.40),i%3==0)
	for p in [Vector3(-5.9,0.15,-10.6),Vector3(7.2,0.15,-10.5),Vector3(14.5,4.65,-25.1),Vector3(7.8,4.65,-22.0),Vector3(14.6,9.3,-38.3)]:
		G.box(self,p+Vector3(0,0.24,0),Vector3(1.5,0.48,0.65),mat("b5a88d",2))
		for j in range(3): crown(p+Vector3((j-1)*0.47,0.6,-0.02),Vector3(0.48,0.36,0.48),"648344")
	# Vines soften exposed terrace faces, with hanging stems and uneven clumps.
	for i in range(15):
		var x:float=-6.5+i*1.05
		if x>7.5: continue
		var at:=Vector3(x,4.55,-17.94)
		for j in range(2+i%3):
			crown(at+Vector3(sin(i+j)*0.18,-j*0.38,0.10),Vector3(0.28,0.36,0.15),"567442")
	bench(Vector3(-2.8,0.20,-9.8))
	bench(Vector3(4.5,0.20,-9.8))
	bench(Vector3(6.4,0.03,3.0),PI/2)
	for i in range(14):
		var z:float=-13+i*2.2
		var rock:=G.sphere(self,Vector3(-8.8-rng.randf()*1.5,-4.5+rng.randf()*0.8,z),Vector3(rng.randf_range(0.7,1.8),rng.randf_range(0.5,1.4),rng.randf_range(0.8,1.5)),mat("9da89b"))
		rock.rotation=Vector3(rng.randf()*.4,rng.randf()*TAU,rng.randf()*.3)
		for j in range(2):
			var foam:=G.sphere(self,Vector3(-10.0-j*0.55,-4.98,z+0.4),Vector3(0.80+j*0.3,0.008,0.055),G.matte(Color("d1e8dc")))
			foam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coastal_slope()
	# Two low, broken ridgelines replace a single smooth distant slab.
	headland(Vector3(-68,-5,-145),1.0,"668f94")
	headland(Vector3(-93,-5,-192),1.35,"8ca9ad")
	boat(Vector3(-37,-4.8,-39),0.85)
	boat(Vector3(-55,-4.8,-84),1.3)
	batch_static()

func coastal_slope() -> void:
	var rows:Array=[]
	for i in range(19):
		var row:Array=[]
		var z:float=-15+i*1.65
		for depth in range(5):
			var fraction:=float(depth)/4.0
			row.append(Vector3(-7.95-fraction*6.1-sin(i*1.7+depth)*fraction*0.4,-0.18-fraction*5.0+sin(i*2.1+depth)*fraction*0.24,z+sin(depth*2.0+i)*fraction*0.35))
		rows.append(row)
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(18):
		for j in range(4):
			for offset in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				st.set_color(Color.WHITE.darkened(rng.randf_range(0.0,0.12)))
				st.add_vertex(rows[i+offset.x][j+offset.y])
	st.generate_normals()
	G.instance(self,st.commit(),Vector3.ZERO,mat("a8aa94",4,0.25))
	for i in range(13):
		var z:float=-13+i*2.15
		var at:=Vector3(-8.5-rng.randf()*1.7,-0.7-rng.randf()*0.8,z)
		crown(at,Vector3(rng.randf_range(0.5,0.9),0.35,rng.randf_range(0.55,0.95)),"637f4c")

func headland(p:Vector3,size_scale:float,color:String) -> void:
	var rows:Array=[]
	for i in range(14):
		var x:float=(i-6.5)*5.0
		var envelope:=sin(float(i)/13.0*PI)
		var ridge:=Vector3(x,(1.8+rng.randf()*7.0)*envelope,-rng.randf()*3)
		rows.append([Vector3(x,-0.4,7+rng.randf()*3),ridge,Vector3(x,-0.5,-8-rng.randf()*4)])
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(13):
		for side in range(2):
			for offset in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				st.add_vertex(rows[i+offset.x][side+offset.y]*size_scale)
	st.generate_normals()
	var land_material:=ShaderMaterial.new()
	land_material.shader=preload("res://shaders/three_d/headland.gdshader")
	land_material.set_shader_parameter("land_color",Color(color))
	G.instance(self,st.commit(),p,land_material)

func terrace(left:float,right:float,back:float,front:float,top:float,cut_left:float,cut_right:float,cut_back:float,color:String) -> void:
	var bottom:=-5.0
	var y:float=(bottom+top)/2
	for rect in [Rect2(left,back,cut_left-left,front-back),Rect2(cut_right,back,right-cut_right,front-back),Rect2(cut_left,back,cut_right-cut_left,cut_back-back)]:
		G.box(self,Vector3(rect.get_center().x,y,rect.get_center().y),Vector3(rect.size.x,top-bottom,rect.size.y),mat(color,2))
		G.box(self,Vector3(rect.get_center().x,top+0.045,rect.get_center().y),Vector3(rect.size.x+0.08,0.09,rect.size.y+0.08),mat("cfc4a8",5))

func building(p:Vector3,size:Vector3,color:String,cafe:bool) -> void:
	G.box(self,p+Vector3(0,size.y/2,0),size,mat(color))
	G.box(self,p+Vector3(0,0.12,0),Vector3(size.x+0.22,0.22,size.z+0.22),mat("c4b295"))
	var floor_count:=maxi(2,roundi(size.y/2.05))
	var floor_height:=size.y/floor_count
	for floor_index in range(floor_count):
		var y:float=(floor_index+0.5)*floor_height
		G.box(self,p+Vector3(0,y-0.65,size.z/2+0.06),Vector3(size.x+0.12,0.12,0.15),mat("f0e4c9"))
		for column in range(3):
			var x:float=(column-1)*(size.x/3.4)
			var front:=p+Vector3(x,y,size.z/2+0.026)
			if not cafe or floor_index>0: window(front,floor_index%2==1)
			if (floor_index+column)%3==0 and not (cafe and floor_index==1): balcony(front+Vector3(0,-0.66,0))
		# Side windows on the exposed west wall receive cool reflected light.
		for z in [-1.1,0.7]:
			G.box(self,p+Vector3(-size.x/2-0.015,y,z),Vector3(0.025,1.15,0.64),mat("52747a"))
			for dz in [-0.36,0.36]: G.box(self,p+Vector3(-size.x/2-0.033,y,z+dz),Vector3(0.045,1.27,0.05),mat("f2e4c8"))
	# Corner pilasters, drainpipes, and occasional balcony doors break simple boxes.
	for x in [-size.x/2+0.08,size.x/2-0.08]:
		G.box(self,p+Vector3(x,size.y/2,size.z/2+0.018),Vector3(0.16,size.y,0.045),mat("dfcfb1"))
		G.beam(self,p+Vector3(x+0.14,0.12,size.z/2+0.10),p+Vector3(x+0.14,size.y-0.15,size.z/2+0.10),0.021,mat("8d937f"),0.021,8)
	if int(p.x)%2==0:
		for j in range(4): crown(p+Vector3(size.x*0.48,0.8+j*0.6,size.z/2+0.11),Vector3(0.23,0.4,0.14),"638049")
	G.box(self,p+Vector3(0,size.y+0.08,0),Vector3(size.x+0.40,0.16,size.z+0.40),mat("eddfbe"))
	roof(p+Vector3(0,size.y+0.16,0),size.x+0.55,size.z+0.55,0.70)
	if cafe:
		var front:=p+Vector3(0,0,size.z/2+0.1)
		for x in [-1.20,0.0,1.20]: G.box(self,front+Vector3(x,0.92,0),Vector3(0.94,1.70,0.06),mat("35595f",0,0.035))
		var awning:=G.box(self,front+Vector3(0,2.05,0.68),Vector3(size.x+0.15,0.07,1.48),mat("315e64",0,0.035))
		awning.rotation.x=0.17
		G.box(self,front+Vector3(0,1.87,1.37),Vector3(size.x+0.15,0.26,0.045),mat("315e64"))
		G.text(self,"CAFÉ SOL",front+Vector3(0,1.88,1.41),48,0.008,Color("efe3bd"),true)
		var terrace_y:=floor_height+0.04
		G.box(self,front+Vector3(0,terrace_y,0.50),Vector3(size.x-0.22,0.12,1.05),mat("d7c8a7"))
		for rail_index in range(13):
			var x:float=(float(rail_index)/12.0-0.5)*(size.x-0.36)
			G.beam(self,front+Vector3(x,terrace_y+0.06,0.99),front+Vector3(x,terrace_y+0.87,0.99),0.011,mat("435f59"),0.011,6)
		G.beam(self,front+Vector3(-size.x/2+0.15,terrace_y+0.90,0.99),front+Vector3(size.x/2-0.15,terrace_y+0.90,0.99),0.019,mat("435f59"))
		for x in [-1.35,1.25]: planter(front+Vector3(x,terrace_y+0.09,0.65),0.24,0.29,true)
		for x in [-1.25,1.15]:
			var at:=front+Vector3(x,0,2.05)
			G.beam(self,at,at+Vector3(0,0.65,0),0.034,mat("455451"))
			G.box(self,at+Vector3(0,0.66,0),Vector3(0.72,0.05,0.58),mat("aa8960"))
			for side in [-1,1]:
				G.box(self,at+Vector3(side*0.48,0.35,0),Vector3(0.31,0.055,0.33),mat("ae9369"))
				G.box(self,at+Vector3(side*0.61,0.61,0),Vector3(0.05,0.4,0.33),mat("ae9369"))
				for z in [-0.11,0.11]: G.beam(self,at+Vector3(side*0.48,0.02,z),at+Vector3(side*0.48,0.35,z),0.018,mat("455451"))

func window(p:Vector3,shutters:bool) -> void:
	G.box(self,p,Vector3(0.72,1.21,0.06),mat("42636d",0,0.04))
	for x in [-0.41,0.41,0.0]: G.box(self,p+Vector3(x,0,0.058),Vector3(0.055,1.33,0.065),mat("f4e6c9"))
	for y in [-0.64,0.64,0.05]: G.box(self,p+Vector3(0,y,0.066),Vector3(0.87,0.056,0.075),mat("f4e6c9"))
	G.box(self,p+Vector3(0,-0.7,0.15),Vector3(1.0,0.09,0.30),mat("d9caad"))
	if shutters:
		for x in [-0.62,0.62]:
			G.box(self,p+Vector3(x,0,0.03),Vector3(0.32,1.27,0.08),mat("728676",1,0.09))

func balcony(p:Vector3) -> void:
	G.box(self,p+Vector3(0,-0.05,0.40),Vector3(1.55,0.13,0.85),mat("ddd1b3"))
	for x in [-0.66,-0.44,-0.22,0.0,0.22,0.44,0.66]: G.beam(self,p+Vector3(x,0.03,0.78),p+Vector3(x,0.73,0.78),0.012,mat("475d5d"),0.012,6)
	G.beam(self,p+Vector3(-0.73,0.75,0.78),p+Vector3(0.73,0.75,0.78),0.022,mat("475d5d"))
	for x in [-0.73,0.73]: G.beam(self,p+Vector3(x,0.75,0),p+Vector3(x,0.75,0.78),0.021,mat("475d5d"))
	if rng.randf()>0.42: planter(p+Vector3(0.35,0.04,0.40),0.19,0.24,true)

func roof(p:Vector3,width:float,depth:float,height:float) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners:=[Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(width/2,0,depth/2),Vector3(-width/2,0,depth/2)]
	var ridge_a:=Vector3(-width*0.29,height,0)
	var ridge_b:=Vector3(width*0.29,height,0)
	for tri in [[corners[0],corners[1],ridge_b],[corners[0],ridge_b,ridge_a],[corners[1],corners[2],ridge_b],[corners[2],corners[3],ridge_a],[corners[2],ridge_a,ridge_b],[corners[3],corners[0],ridge_a]]:
		for index in [0,2,1]: st.add_vertex(tri[index])
	st.generate_normals()
	G.instance(self,st.commit(),p,mat("b08f70",3,0.11))

func stairs(start:Vector3,count:int,rise:float,run:float,width:float) -> void:
	for i in range(count):
		G.box(self,start+Vector3(0,rise*(i+1)*0.5,-run*i),Vector3(width,rise*(i+1),run+0.018),mat("b4b2a0",0,0.09))
	for side in [-1,1]:
		var a:=start+Vector3(side*(width*.5+0.04),0.95,0)
		var b:=start+Vector3(side*(width*.5+0.04),rise*count+0.95,-run*count)
		G.beam(self,a,b,0.024,mat("68706a"))
		for i in range(0,count,3): G.beam(self,start+Vector3(side*(width*.5+0.04),rise*i,-run*i),start+Vector3(side*(width*.5+0.04),rise*i+0.95,-run*i),0.021,mat("68706a"))

func make_foliage() -> void:
	var image:=Image.create(256,256,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in range(100):
		var angle:=rng.randf()*TAU
		var radius:=sqrt(rng.randf())*98
		var center:=Vector2(128,128)+Vector2(cos(angle),sin(angle)*0.8)*radius
		var length:=rng.randf_range(10,23)
		Leaf.paint(image,center,length,length*rng.randf_range(0.30,0.50),angle+rng.randf_range(-0.8,0.8),rng.randf_range(0.65,1.0),Leaf.Profile.POINTED)
	image.generate_mipmaps()
	leaf_texture=ImageTexture.create_from_image(image)
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(95):
		var angle:=rng.randf()*TAU
		var u:=rng.randf_range(-0.9,1.0)
		var direction:=Vector3(cos(angle)*sqrt(1-u*u),u,sin(angle)*sqrt(1-u*u))
		var center:=direction*pow(rng.randf(),0.28)
		var orientation:=Basis(Quaternion(Vector3.FORWARD,(direction+Vector3.UP*.3).normalized()))
		var radius:=rng.randf_range(0.23,0.40)
		var points:=[Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
		for index in [0,1,2,0,2,3]:
			st.set_color(Color.WHITE* rng.randf_range(0.85,1.15))
			st.set_uv(points[index]*.5+Vector2.ONE*.5)
			st.set_normal((direction+Vector3.UP*.5).normalized())
			st.add_vertex(center+orientation*Vector3(points[index].x*radius,points[index].y*radius,0))
	canopy=st.commit()

func crown(p:Vector3,radii:Vector3,color:String="537343") -> void:
	var key:="leaf"+color
	if not materials.has(key):
		var shader:=ShaderMaterial.new()
		shader.shader=preload("res://shaders/three_d/foliage.gdshader")
		shader.set_shader_parameter("leaf_cards",true)
		shader.set_shader_parameter("leaf_texture",leaf_texture)
		shader.set_shader_parameter("base_color",Color(color))
		materials[key]=shader
	var n:=G.instance(self,canopy,p,materials[key])
	n.scale=radii
	n.rotation.y=rng.randf()*TAU
	n.set_meta("moving_foliage",true)

func tree(p:Vector3,scale_value:float) -> void:
	var fork:=p+Vector3(0.25,3.1,0)*scale_value
	G.beam(self,p,fork,0.24*scale_value,mat("827b60",6,0.23),0.115*scale_value,13)
	for i in range(6):
		var angle:=i*TAU/6+0.25
		var end:=fork+Vector3(cos(angle)*1.65,1.9+rng.randf()*0.8,sin(angle)*1.65)*scale_value
		var elbow:=fork.lerp(end,0.56)+Vector3(0,0.25,0)
		G.beam(self,fork,elbow,0.105*scale_value,mat("827b60",6,0.23),0.058*scale_value,11)
		G.beam(self,elbow,end,0.058*scale_value,mat("827b60",6,0.23),0.014*scale_value,9)
		crown(end,Vector3(1.45,1.05,1.4)*scale_value,"547648" if i%2 else "69834a")
	crown(fork+Vector3(0,2.7,0)*scale_value,Vector3(1.6,1.2,1.6)*scale_value,"66824a")

func planter(p:Vector3,radius:float,height:float,flowers:bool=false) -> void:
	G.beam(self,p,p+Vector3(0,height,0),radius*0.76,mat("b48868"),radius,12)
	crown(p+Vector3(0,height+radius*.35,0),Vector3(radius*1.5,radius*.9,radius*1.4),"5e7b44")
	if flowers:
		for j in range(4):
			var flower:=p+Vector3(cos(j*2.4)*radius*.65,height+radius*.65,sin(j*2.4)*radius*.65)
			G.sphere(self,flower,Vector3.ONE*radius*.16,mat("d8a38b"))

func bench(p:Vector3,yaw:float=0.0) -> void:
	var basis:=Basis(Vector3.UP,yaw)
	for z in [-0.16,0,0.16]:
		var plank:=G.box(self,p+basis*Vector3(0,0.43,z),Vector3(1.62,0.055,0.14),mat("ad8c61"))
		plank.rotation.y=yaw
	for y in [0.67,0.84]:
		var plank:=G.box(self,p+basis*Vector3(0,y,0.22),Vector3(1.62,0.13,0.055),mat("ad8c61"))
		plank.rotation.y=yaw
	for x in [-0.59,0.59]:
		G.beam(self,p+basis*Vector3(x,0.02,-0.16),p+basis*Vector3(x,0.46,-0.16),0.025,mat("465956"))
		G.beam(self,p+basis*Vector3(x,0.02,0.19),p+basis*Vector3(x,0.94,0.19),0.025,mat("465956"))

func boat(p:Vector3,scale_value:float) -> void:
	G.sphere(self,p,Vector3(1.3,.12,.4)*scale_value,mat("efe4ce"))
	G.beam(self,p,p+Vector3(0,2.6,0)*scale_value,.015*scale_value,mat("a7a394"))
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [Vector3(0,.3,0),Vector3(-1.1,.3,0),Vector3(0,2.5,0)]: st.add_vertex(vertex*scale_value)
	st.generate_normals()
	var sail:=G.matte(Color("fff3d5"))
	sail.cull_mode=BaseMaterial3D.CULL_DISABLED
	G.instance(self,st.commit(),p,sail)

func batch_static() -> void:
	# Merge inert scenery by shared material and shadow policy. Keep wind independent.
	var groups:Dictionary={}
	var remove:Array[Node]=[]
	for child in get_children():
		if child is MeshInstance3D and not child.has_meta("moving_foliage"):
			var material:Material=child.material_override
			if not groups.has(material): groups[material]={}
			var shadow_mode:int=child.cast_shadow
			if not groups[material].has(shadow_mode):
				var st:=SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[material][shadow_mode]=st
			var source:=SurfaceTool.new()
			source.create_from(child.mesh,0)
			source.deindex()
			groups[material][shadow_mode].append_from(source.commit(),0,child.transform)
			remove.append(child)
	for material in groups:
		for shadow_mode in groups[material]:
			var merged:=G.instance(self,groups[material][shadow_mode].commit(),Vector3.ZERO,material)
			merged.cast_shadow=shadow_mode
	for child in remove: child.queue_free()
