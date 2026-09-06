class_name LastCastWorld
extends Node3D
## All scenery is generated locally. Coordinates keep the quay and water legible.
var rng := RandomNumberGenerator.new()
var palette: Array[Color] = []
var leaf_transforms: Array[Transform3D] = []
var leaf_colors: Array[Color] = []
var rock_transforms: Array[Transform3D] = []
var rock_colors: Array[Color] = []
var stone: Material
var trim: Material
var wood: Material
var dark: Material
var roof: Material
var green: Material
var region_index := 0
var material_cache: Dictionary = {}
var daylight_environment: Environment
var daylight_sun: DirectionalLight3D
var daylight_sky: ShaderMaterial
var daylight_top := Color("4a91bd")
var daylight_horizon := Color("c4dbd6")

func build(region: int = 0, season: int = 0) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	rng.seed = 41973 + region * 51
	region_index = region
	material_cache.clear()
	leaf_transforms.clear()
	leaf_colors.clear()
	rock_transforms.clear()
	rock_colors.clear()
	palette = [Color("d6b195"), Color("d6c6aa"), Color("c89781"), Color("dfcaaa"), Color("b8c2ab")]
	if region == 1:
		palette = [Color("d5bdba"), Color("d9d3bb"), Color("a9bdc6"), Color("e7c8a9"), Color("cad4c3")]
	elif region == 2:
		palette = [Color("e4ac85"), Color("d5b597"), Color("c7b6a0"), Color("e1c997"), Color("babdaf")]
	stone = _mat(Color("9d9d8b"))
	trim = _mat(Color("c8bfaf"))
	wood = ShaderMaterial.new()
	wood.shader = load("res://shaders/timber.gdshader")
	dark = _mat(Color("25494b"))
	roof = ShaderMaterial.new()
	roof.shader = load("res://shaders/roof.gdshader")
	green = _mat(Color("657b50"))
	_environment(season)
	_water(season)
	_quay()
	_village()
	_coastal_quarter()
	_shopkeeper(Vector3(-8,1,-4.6), false)
	_shopkeeper(Vector3(6,1,-4.6), true)
	_regional_details(season)
	_dock(Vector3(0, 0, 4), 3.2, 8.0)
	_dock(Vector3(-12, 0, 2.5), 3.0, 5.0)
	_sign("SHORE CASTING", Vector3(-14.0, 2.15, .4), .075)
	_sign("BOAT BERTH", Vector3(2.5, 2.2, .3), .085)
	_landscape()
	_lighthouse(Vector3(88, 0, 15))
	_boundary_buoys()
	_sailboat(Vector3(-29, .2, 53), .8)
	_sailboat(Vector3(16, .2, 70), 1.25)
	_sailboat(Vector3(47, .2, 57), .65)
	_flush_instances()
	_batch_boxes()
	_batch_cylinders()

func _mat(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if material_cache.has(key): return material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/plaster.gdshader")
	material.set_shader_parameter("tint", color)
	material_cache[key]=material
	return material

func _box(pos: Vector3, size: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.position = pos
	add_child(item)
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		item.add_child(body)
	return item

func _cylinder(pos: Vector3, radius: float, height: float, material: Material, top: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.position = pos
	add_child(item)
	return item

func _sphere(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 10
	mesh.rings = 5
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.position = pos
	item.scale = size
	add_child(item)
	return item

func _environment(season: int) -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	daylight_environment=env
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	daylight_sky=sky_mat
	daylight_top=Color("4a91bd")
	daylight_horizon=Color("c4dbd6")
	if region_index == 1:
		daylight_top=Color("527e9a")
		sky_mat.set_shader_parameter("sky_top", daylight_top)
	elif region_index == 2:
		daylight_top=Color("496b83")
		daylight_horizon=Color("c6cbd0")
		sky_mat.set_shader_parameter("sky_top", daylight_top)
		sky_mat.set_shader_parameter("sky_horizon", Color("c6cbd0"))
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9d8df")
	env.ambient_light_energy = .56
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = .08
	env.fog_light_color = Color("aac7c9")
	env.fog_density = .0022 if region_index != 2 else .005
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	daylight_sun=sun
	sun.rotation_degrees = Vector3(-43, -34, 0)
	sun.light_color = Color("ffedce") if season == 0 else Color("ffe0bf")
	sun.light_energy = .72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 95
	sun.shadow_bias = .035
	add_child(sun)

func _water(season: int) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	plane.subdivide_width = 120
	plane.subdivide_depth = 120
	var item := MeshInstance3D.new()
	item.mesh = plane
	item.position = Vector3(0, .08, 90)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	if region_index == 1:
		material.set_shader_parameter("shallow", Color("328d7c"))
		material.set_shader_parameter("deep", Color("155462"))
	elif region_index == 2:
		material.set_shader_parameter("shallow", Color("287989"))
		material.set_shader_parameter("deep", Color("173f59"))
	material.set_shader_parameter("wind", 1.0 + region_index * .35 + season * .25)
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	var seabed := MeshInstance3D.new()
	seabed.set_script(load("res://scripts/waterbed.gd"))
	seabed.build(region_index)
	add_child(seabed)

func _quay() -> void:
	_box(Vector3(0, -.35, -6.5), Vector3(46, 2.7, 13), stone, true)
	# Small irregular limestone courses retain a clear continuous promenade.
	var pavers: Array[Transform3D] = []
	var colors: Array[Color] = []
	var course_z := -12.98
	while course_z<-.04:
		var course := minf(rng.randf_range(.255,.385),-course_z)
		var x := -22.98
		while x<22.96:
			var width := minf(rng.randf_range(.36,.70),23.0-x)
			var offset := rng.randf_range(-.01,.01)
			pavers.append(Transform3D(Basis.from_euler(Vector3(0,rng.randf_range(-.012,.012),0)).scaled(Vector3(width-.013,.055,course-.013)),Vector3(x+width*.5,1.005+offset*.2,course_z+course*.5)))
			colors.append(Color("b5aba0").lerp(Color("a59f92"),rng.randf_range(0,.60)))
			x+=width
		course_z+=course
	_instances(_bevel_box(.026),pavers,colors,null,false)
	var blocks: Array[Transform3D] = []
	var block_colors: Array[Color] = []
	for row in range(9):
		var x := -23.1
		while x<23.0:
			var width := rng.randf_range(.46,.82)
			blocks.append(Transform3D(Basis.from_euler(Vector3(0,0,rng.randf_range(-.022,.022))).scaled(Vector3(width-.022,.255+rng.randf_range(-.02,.02),.31)),Vector3(x+width*.5,.78-row*.275,.085+rng.randf_range(-.025,.025))))
			block_colors.append(Color("a5a58e").lerp(Color("747968"),rng.randf_range(0,.48)+clampf((row-3)*.065,0,.28)))
			x+=width
	# Coping is broader than masonry but is still sized for a person's foot.
	for i in range(77):
		blocks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.578,.13,.43)),Vector3(-22.8+i*.6,.97,.07)))
		block_colors.append(Color("bbb7a0").darkened(rng.randf_range(0,.11)))
	_instances(_bevel_box(.075),blocks,block_colors,null)
	for x in [-21,-17,-7,-4,5,9,14,19,22]:
		_box(Vector3(x,1.32,.0),Vector3(.23,.60,.26),stone)
		_cylinder(Vector3(x,1.67,.0),.16,.09,trim)
	for x in [-19,12,20]: _bench(Vector3(x,1,-2.6))
	for x in [-20,-3,15]: _lamp(Vector3(x,1,-3.7))
	for x in [-16,-2,12,21]: _planter(Vector3(x,1,-4.5))
	# Gravel, low stones and herbs merge the engineered quay into the coast.
	for side in [-1,1]:
		for i in range(16):
			var z := -12.0+i*.72
			var x: float = side*(23.5+rng.randf_range(-.3,1.3))
			_rock(Vector3(x,.12,z),Vector3(rng.randf_range(1.1,2.1),rng.randf_range(1.0,1.9),rng.randf_range(1.0,2.2)))
			if i%3==0: _bush(Vector3(x,1,z),Vector3(.72,.53,.64))

func _dock(center: Vector3, width: float, length: float) -> void:
	_box(Vector3(center.x,.8,center.z),Vector3(width,.4,length),wood,true)
	for i in range(int(length/.32)):
		_box(Vector3(center.x,1.025,center.z-length*.5+.16+i*.32),Vector3(width+.12,.09,.28),wood)
	for z in [center.z-length*.5+.25,center.z+length*.5-.25]:
		for x in [center.x-width*.5,center.x+width*.5]:
			_cylinder(Vector3(x,.55,z),.14,2.05,wood)
			_cylinder(Vector3(x,1.63,z),.17,.12,trim)
			_sphere(Vector3(x,.43,z+.13),Vector3(.36,.44,.34),trim)
	# Rope cleats and landing ladder clearly mark the approach.
	_box(Vector3(center.x+width*.5,1.14,center.z),Vector3(.38,.12,.12),dark)
	for yy in range(4):
		_box(Vector3(center.x+width*.5+.2,.25+yy*.23,center.z+.6),Vector3(.5,.065,.07),wood)

func _village() -> void:
	_building(Vector3(-8,1,-7.1),Vector3(6,4.0,4),palette[0],"TACKLE",true)
	_building(Vector3(6,1,-7.1),Vector3(5.8,3.9,4),palette[3],"FRESH CATCH",true)
	_building(Vector3(-16.8,1,-8.2),Vector3(5,6.6,4.8),palette[2])
	_building(Vector3(16,1,-9.1),Vector3(6.2,7.2,5.8),palette[1])
	_building(Vector3(.0,1,-10.4),Vector3(4.6,7.8,4.4),palette[4])
	# Each house sits on its own shelf along an asymmetric hillside, rather than a grid.
	for i in range(8):
		var x := -30.0+i*8.3+rng.randf_range(-1.1,1.1)
		var z := -20.0-rng.randf_range(0,5)
		var yy := _hill_height(x,z-2.8)+.3
		var footprint := Vector3(rng.randf_range(3.9,6.4),rng.randf_range(4.2,7.5),rng.randf_range(4.2,6.5))
		_terrace(Vector3(x,yy,z),footprint.x+2.3,footprint.z+2.0)
		_building(Vector3(x,yy,z),footprint,palette[i%palette.size()],"",false,rng.randf_range(-.35,.35)+(PI/2 if i%3==0 else 0.0))
		_tree(Vector3(x-footprint.x*.5-1.3,yy,z),rng.randf_range(4,6.5))
	for i in range(5):
		var x := -32.0+i*11.0
		var z := -34.0-rng.randf_range(0,9)
		var yy := _hill_height(x,z-3)+.2
		_terrace(Vector3(x,yy,z),8,8)
		_building(Vector3(x,yy,z),Vector3(rng.randf_range(4.5,6),rng.randf_range(3.8,6.5),rng.randf_range(4.8,7.2)),palette[(i+2)%palette.size()],"",false,rng.randf_range(-.25,.25))
		_cypress(Vector3(x+4,yy,z+1),rng.randf_range(7,10))
	# Village stairs and terraces frame the central harbor without blocking shop approach.
	_harbor_stair()
	for pos in [Vector3(-19,1,-5.4),Vector3(-3,1,-7),Vector3(11,1,-6),Vector3(21,1,-6),Vector3(-12,5.4,-15),Vector3(10,5.4,-15)]:
		_tree(pos,rng.randf_range(3.5,5.3))
	for x in [-10,-6,4,8]:
		_box(Vector3(x,1.28,-4.9),Vector3(.85,.56,.65),wood)
		for j in range(3):
			_sphere(Vector3(x-.24+j*.24,1.65,-4.85),Vector3(.20,.16,.18),_mat(Color("e6aa57") if x<0 else Color("70a8a4")))

	# Shop dressing supports the harbor's fishing identity at walking distance.
	for i in range(5):
		var rod := _cylinder(Vector3(-10.45+i*.17,2.1,-4.98),.013,2.1,dark)
		rod.rotation.z=.08+i*.035
	for x in [-11.1,9.8]:
		_cylinder(Vector3(x,1.25,-4.5),.24,.48,wood,.26)
		_cylinder(Vector3(x,1.50,-4.5),.25,.055,dark)
		_box(Vector3(x+.52,1.25,-4.65),Vector3(.65,.5,.56),wood)
		for i in range(4):
			_box(Vector3(x+.24+i*.18,1.26,-4.34),Vector3(.025,.48,.025),trim)
	for i in range(7):
		_sphere(Vector3(8.53,2.0+i*.16,-4.93),Vector3(.15,.19,.15),_mat(Color("da8e67") if i%2 else Color("e8d0a1")))

func _building(base: Vector3, size: Vector3, color: Color, title: String = "", awning: bool = false, yaw: float = 0.0) -> void:
	var first_child := get_child_count()
	var first_leaf := leaf_transforms.size()
	_box(base+Vector3(0,size.y*.5,0),size,_mat(color),base.y<2)
	_box(base+Vector3(0,.22,0),Vector3(size.x+.16,.45,size.z+.1),stone)
	_box(base+Vector3(0,size.y-.15,0),Vector3(size.x+.18,.14,size.z+.18),trim)
	var variant := int(absf(base.x*13+base.z*7))%4
	_roof(base+Vector3(0,size.y,0),size.x+.46,size.z+.46,.65 if awning else .85+size.x*.035,variant%2,color)
	# A side wing and terrace vary the silhouette without changing the approach.
	if not awning and variant==1:
		var wing := base+Vector3(size.x*.36,0,-size.z*.20)
		_box(wing+Vector3(0,size.y*.26,0),Vector3(size.x*.64,size.y*.52,size.z*.95),_mat(color.darkened(.06)))
		_box(wing+Vector3(0,size.y*.52+.08,0),Vector3(size.x*.68,.16,size.z),trim)
		for i in range(5):
			_box(wing+Vector3(-size.x*.28+i*size.x*.14,size.y*.52+.48,size.z*.47),Vector3(.05,.76,.05),dark)
		_box(wing+Vector3(0,size.y*.52+.87,size.z*.47),Vector3(size.x*.65,.055,.055),dark)
	var front := base.z+size.z*.5+.05
	var floors := maxi(1,int(size.y/2.5))
	var columns := maxi(2,int(size.x/1.8))
	for floor_index in range(floors):
		for col in range(columns):
			var x := base.x+(col-(columns-1)*.5)*(size.x/(columns+.3))
			var y := base.y+1.6+floor_index*2.35
			_box(Vector3(x,y,front),Vector3(.9,1.38,.12),trim)
			_box(Vector3(x,y,front+.07),Vector3(.65,1.12,.08),dark)
			_box(Vector3(x,y,front+.13),Vector3(.04,1.12,.04),trim)
			_box(Vector3(x,y,front+.13),Vector3(.7,.04,.04),trim)
			for side in [-1,1]:
				var shutter := Vector3(x+side*.59,y,front+.045)
				_box(shutter,Vector3(.28,1.2,.08),green)
				for louver in range(7):
					var slat := _box(shutter+Vector3(0,-.49+louver*.16,.048),Vector3(.23,.11,.028),_mat(Color("6f7e62")))
					slat.rotation.x=-.23
			_box(Vector3(x,y-.74,front+.09),Vector3(1.03,.09,.22),stone)
			if floor_index>0 and col%2==0:
				_box(Vector3(x,y-.67,front+.25),Vector3(1.15,.18,.46),wood)
				_bush(Vector3(x,y-.53,front+.30),Vector3(.62,.21,.27))
				for bar in range(6):
					_box(Vector3(x-.48+bar*.192,y-.33,front+.50),Vector3(.025,.5,.025),dark)
				_box(Vector3(x,y-.09,front+.50),Vector3(1.1,.035,.035),dark)
	# Side elevations are finished too: camera orbit should never reveal blank boxes.
	for side in [-1,1]:
		for k in range(floors):
			for row in range(maxi(2,int(size.z/2.2))):
				var zz := base.z-size.z*.28+row*size.z*.52
				var yy := base.y+1.6+k*2.35
				var xx: float = base.x+side*(size.x*.5+.04)
				_box(Vector3(xx,yy,zz),Vector3(.12,1.35,.96),trim)
				_box(Vector3(xx+side*.075,yy,zz),Vector3(.08,1.13,.7),dark)
				_box(Vector3(xx+side*.13,yy,zz),Vector3(.04,.04,.72),trim)
				_box(Vector3(xx+side*.13,yy,zz),Vector3(.04,1.14,.04),trim)
				for shutter in [-1,1]:
					_box(Vector3(xx,yy,zz+shutter*.63),Vector3(.1,1.2,.30),green)
	_doorway(Vector3(base.x+(.28 if variant==2 else -.2),base.y,front+.065),variant%2==0)
	var chimney := base+Vector3(size.x*.3,size.y+.78,-size.z*.2)
	_box(chimney,Vector3(.37,1.3,.40),stone)
	_box(chimney+Vector3(0,.69,0),Vector3(.49,.13,.52),roof)
	for y in range(maxi(1,int(size.y/.48))):
		for side in [-1,1]:
			_box(base+Vector3(side*(size.x*.5-.16),.23+y*.48,size.z*.5+.012),Vector3(.24 if y%2 else .38,.20,.055),_mat(color.darkened(.05)))
	if awning:
		_shopfront(base,size,front,title)

	if not awning and size.y>5:
		# A small upper balcony and pergola break up the wall's rectangular silhouette.
		var yy := base.y+3.0
		_box(Vector3(base.x,yy,front+.62),Vector3(size.x*.64,.16,1.4),trim)
		_box(Vector3(base.x,yy+.93,front+1.22),Vector3(size.x*.67,.06,.06),dark)
		for rail in range(10):
			_box(Vector3(base.x-size.x*.31+rail*size.x*.062,yy+.46,front+1.22),Vector3(.035,.91,.035),dark)
		for side in [-1,1]:
			_cylinder(Vector3(base.x+side*size.x*.27,yy+.19,front+.86),.20,.35,roof,.25)
			_bush(Vector3(base.x+side*size.x*.27,yy+.52,front+.86),Vector3(.33,.35,.32))
	if absf(yaw)>.01:
		var rotation_basis := Basis(Vector3.UP,yaw)
		for index in range(first_child,get_child_count()):
			var node := get_child(index) as Node3D
			if node:
				node.position=base+rotation_basis*(node.position-base)
				node.basis=rotation_basis*node.basis
		for index in range(first_leaf,leaf_transforms.size()):
			leaf_transforms[index].origin=base+rotation_basis*(leaf_transforms[index].origin-base)
			leaf_transforms[index].basis=rotation_basis*leaf_transforms[index].basis

func _roof(pos: Vector3, width: float, depth: float, height: float, style: int = 0, gable_color: Color = Color("c5b69c")) -> void:
	var half := width*.5
	var zhalf := depth*.5
	var inset := depth*.23 if style==1 else 0.0
	var faces: Array = [
		[Vector3(-half,0,-zhalf),Vector3(0,height,-zhalf+inset),Vector3(0,height,zhalf-inset),Vector3(-half,0,zhalf)],
		[Vector3(0,height,-zhalf+inset),Vector3(half,0,-zhalf),Vector3(half,0,zhalf),Vector3(0,height,zhalf-inset)]]
	if style==1:
		faces.append([Vector3(-half,0,-zhalf),Vector3(half,0,-zhalf),Vector3(0,height,-zhalf+inset)])
		faces.append([Vector3(-half,0,zhalf),Vector3(0,height,zhalf-inset),Vector3(half,0,zhalf)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		for i in range(1,face.size()-1):
			for index in [0,i,i+1]: surface.add_vertex(face[index])
	surface.generate_normals()
	var item := MeshInstance3D.new()
	item.mesh=surface.commit()
	item.material_override=roof
	item.position=pos
	add_child(item)
	if style==0:
		for sign_value in [-1,1]:
			var end := SurfaceTool.new()
			end.begin(Mesh.PRIMITIVE_TRIANGLES)
			for point in [Vector3(-half,0,sign_value*zhalf),Vector3(half,0,sign_value*zhalf),Vector3(0,height,sign_value*zhalf)]: end.add_vertex(point)
			end.generate_normals()
			var mesh := MeshInstance3D.new()
			mesh.mesh=end.commit()
			mesh.material_override=_mat(gable_color)
			mesh.position=pos
			add_child(mesh)
	for side in [-1,1]:
		_box(pos+Vector3(side*half,-.03,0),Vector3(.10,.15,depth+.06),wood)
	for i in range(int((depth-inset*2)/.28)+1):
		_cylinder(pos+Vector3(0,height+.025,-zhalf+inset+i*.28),.075,.29,roof).rotation.x=PI/2

func _doorway(pos: Vector3, arched: bool) -> void:
	_box(pos+Vector3(0,.87,0),Vector3(.91,1.74,.08),dark)
	for i in range(5):
		_box(pos+Vector3(-.35+i*.175,.85,.047),Vector3(.16,1.66,.04),wood)
	for side in [-1,1]:
		_box(pos+Vector3(side*.52,.88,.04),Vector3(.13,1.76,.18),stone)
	if arched:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(12):
			var a := i*PI/12
			var b := (i+1)*PI/12
			for point in [Vector3.ZERO,Vector3(cos(a)*.46,sin(a)*.46,0),Vector3(cos(b)*.46,sin(b)*.46,0)]: st.add_vertex(point)
		st.generate_normals()
		var arch := MeshInstance3D.new()
		arch.mesh=st.commit()
		arch.position=pos+Vector3(0,1.73,.05)
		arch.material_override=dark
		add_child(arch)
		for i in range(11):
			var angle := (i+.5)*PI/11
			var block := _box(pos+Vector3(cos(angle)*.52,1.73+sin(angle)*.52,.04),Vector3(.16,.17,.19),stone)
			block.rotation.z=angle-PI/2
	else: _box(pos+Vector3(0,1.81,.06),Vector3(1.16,.17,.22),stone)
	_box(pos+Vector3(.28,.86,.10),Vector3(.045,.07,.05),trim)
	_box(pos+Vector3(0,.035,.17),Vector3(1.16,.07,.42),trim)

func _shopfront(base: Vector3, size: Vector3, front: float, title: String) -> void:
	var tackle := title=="TACKLE"
	var canvas := _mat(Color("89946d") if tackle else Color("bd9b72"))
	var stripe := _mat(Color("cfc5a4"))
	# Open shadowed bays, heavy jambs and shelves read as working shops.
	_box(Vector3(base.x,base.y+1.3,front+.075),Vector3(size.x-.45,2.47,.13),dark)
	for x in [-.46,0.0,.46]:
		_box(Vector3(base.x+x*size.x,base.y+1.27,front+.17),Vector3(.12,2.5,.15),wood)
	for y in [.42,1.18,1.88]:
		_box(Vector3(base.x+size.x*.27,base.y+y,front+.35),Vector3(size.x*.40,.10,.52),wood)
		for j in range(7):
			var at := Vector3(base.x+size.x*.11+j*.25,base.y+y+.15,front+.38)
			if tackle:
				_cylinder(at,.056,.21,_mat(Color("bba77c") if j%2 else Color("8b9b89")))
			else:
				var fish := _sphere(at,Vector3(.23,.075,.105),_mat(Color("7a9c9a")))
				fish.rotation.y=.25
	for i in range(12):
		var left := base.x-size.x*.5+i*size.x/12
		var right := left+size.x/12
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(5):
			var xa := lerpf(left,right,j/5.0)
			var xb := lerpf(left,right,(j+1)/5.0)
			var ya := base.y+2.36-.055*sin(j*PI/5)
			var yb := base.y+2.36-.055*sin((j+1)*PI/5)
			for vertex in [Vector3(xa,base.y+2.76,front+.15),Vector3(xb,base.y+2.76,front+.15),Vector3(xa,base.y+2.53,front+1.53),Vector3(xb,base.y+2.76,front+.15),Vector3(xb,base.y+2.53,front+1.53),Vector3(xa,base.y+2.53,front+1.53),Vector3(xa,base.y+2.53,front+1.53),Vector3(xb,base.y+2.53,front+1.53),Vector3(xa,ya,front+1.56),Vector3(xb,base.y+2.53,front+1.53),Vector3(xb,yb,front+1.56),Vector3(xa,ya,front+1.56)]: st.add_vertex(vertex)
		st.generate_normals()
		var fabric := MeshInstance3D.new()
		fabric.mesh=st.commit()
		fabric.material_override=canvas if i%2 else stripe
		add_child(fabric)
	for side in [-1,1]:
		_cylinder(Vector3(base.x+side*(size.x*.5-.12),base.y+1.3,front+1.44),.035,2.6,wood)
	_box(Vector3(base.x,base.y+3.13,front+.17),Vector3(size.x*.75,.52,.17),wood)
	_box(Vector3(base.x,base.y+3.13,front+.27),Vector3(size.x*.71,.42,.025),dark)
	_sign(title,Vector3(base.x,base.y+3.13,front+.30),.087)
	# Chalkboard and hanging floats stay outside the clear path.
	var chalk := _box(Vector3(base.x-size.x*.39,base.y+.47,front+1.40),Vector3(.52,.87,.06),wood)
	chalk.rotation.x=-.12
	_box(chalk.position+Vector3(0,.04,.055),Vector3(.42,.67,.026),dark)
	_sign("RODS" if tackle else "TODAY",chalk.position+Vector3(0,.20,.087),.031)
	for i in range(4):
		_box(chalk.position+Vector3(0,.045-i*.065,.09),Vector3(.27-i*.025,.012,.014),trim)

func _harbor_stair() -> void:
	var width := 2.2
	for i in range(18):
		var rise := (i+1)*.125
		var z := -4.0-(i+.5)*4.6/18
		_box(Vector3(-12.6,1+rise*.5,z),Vector3(width,rise,4.6/18+.015),stone)
		_box(Vector3(-12.6,1+rise+.007,z+.11),Vector3(width+.025,.028,.07),trim)
	_box(Vector3(-12.6,2.1,-9.1),Vector3(2.8,2.3,1.0),stone,true)
	# Smooth collision ramp follows the staircase; the visual steps remain fine enough
	# to feel like steps without bumping the third-person camera on each riser.
	var body := StaticBody3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points=PackedVector3Array([Vector3(-13.7,.95,-4),Vector3(-11.5,.95,-4),Vector3(-13.7,1,-4),Vector3(-11.5,1,-4),Vector3(-13.7,.95,-8.6),Vector3(-11.5,.95,-8.6),Vector3(-13.7,3.25,-8.6),Vector3(-11.5,3.25,-8.6)])
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	add_child(body)
	for side in [-1,1]:
		for i in range(5):
			var t := i/4.0
			_box(Vector3(-12.6+side*1.23,1.43+t*2.25,-4-t*4.6),Vector3(.17,.85,.19),stone)
		var start := Vector3(-12.6+side*1.23,1.91,-4)
		var end := Vector3(-12.6+side*1.23,4.16,-8.6)
		var rail := _cylinder((start+end)*.5,.042,start.distance_to(end),dark)
		rail.quaternion=Quaternion(Vector3.UP,(end-start).normalized())
	_box(Vector3(-12.6,3.74,-9.59),Vector3(2.8,.95,.18),stone,true)
	_box(Vector3(-12.6,4.24,-9.59),Vector3(2.92,.14,.26),trim)
	_planter(Vector3(-13.55,3.25,-9.25))
	_bush(Vector3(-11.40,3.45,-9.35),Vector3(.44,.50,.37))

func _sign(title: String, pos: Vector3, pixel: float) -> void:
	var label := Label3D.new()
	label.text = title
	label.position = pos
	label.font_size = 40
	label.pixel_size = pixel/10
	label.modulate = Color("f6e4b9")
	label.outline_size = 3
	label.outline_modulate = Color("3c5349")
	label.no_depth_test = false
	# Back faces otherwise show large mirrored dock text when sailing away.
	label.double_sided = false
	add_child(label)

func _bench(pos: Vector3) -> void:
	for i in range(4):
		_box(pos+Vector3(0,.5,-.26+i*.17),Vector3(1.85,.065,.135),wood)
	for i in range(3):
		_box(pos+Vector3(0,.78+i*.13,-.31),Vector3(1.85,.10,.055),wood)
	for side in [-1,1]:
		_box(pos+Vector3(side*.68,.25,0),Vector3(.075,.5,.51),dark)
		_box(pos+Vector3(side*.68,.76,-.32),Vector3(.055,.77,.055),dark)
		_box(pos+Vector3(side*.91,.68,-.03),Vector3(.045,.05,.49),dark)

func _lamp(pos: Vector3) -> void:
	_cylinder(pos+Vector3(0,1.7,0),.06,3.4,dark)
	_box(pos+Vector3(0,3.47,0),Vector3(.33,.45,.33),trim)
	_cylinder(pos+Vector3(0,3.78,0),.3,.18,dark,.02)

func _planter(pos: Vector3) -> void:
	_cylinder(pos+Vector3(0,.3,0),.38,.6,roof,.48)
	_bush(pos+Vector3(0,.76,0),Vector3(.64,.52,.6))
	for i in range(5):
		_sphere(pos+Vector3(rng.randf_range(-.4,.4),rng.randf_range(.8,1.1),rng.randf_range(-.4,.4)),Vector3(.12,.12,.12),_mat(Color("eeb577")))

func _tree(pos: Vector3, height: float) -> void:
	var trunk := _cylinder(pos+Vector3(0,height*.42,0),height*.052,height*.84,_mat(Color("766d48")),height*.024)
	trunk.rotation.z=rng.randf_range(-.08,.08)
	for i in range(4):
		var angle := i*TAU/4+rng.randf_range(-.4,.4)
		var branch := _cylinder(pos+Vector3(cos(angle)*height*.12,height*.68,sin(angle)*height*.12),height*.025,height*.42,wood,height*.012)
		branch.rotation.z=cos(angle)*.65
		branch.rotation.x=sin(angle)*.65
		_bush(pos+Vector3(cos(angle)*height*.23,height*.82,sin(angle)*height*.23),Vector3(height*.36,height*.28,height*.33))
	_bush(pos+Vector3(0,height*1.06,0),Vector3(height*.35,height*.32,height*.34))

func _bush(pos: Vector3, size: Vector3) -> void:
	for j in range(18):
		var offset := Vector3(rng.randf_range(-.75,.75),rng.randf_range(-.65,.65),rng.randf_range(-.75,.75))*size
		var scale_factor := rng.randf_range(.35,.66)
		leaf_transforms.append(Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf()*TAU,rng.randf())).scaled(size*scale_factor),pos+offset))
		var color := Color("91995e").lerp(Color("576f49"),rng.randf())
		if region_index==1: color=color.lerp(Color("8f9a7c"),.25)
		elif region_index==2: color=color.lerp(Color("b99d53"),.35)
		leaf_colors.append(color)

func _rock(pos: Vector3, size: Vector3) -> void:
	rock_transforms.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-.3,.3),rng.randf()*TAU,rng.randf_range(-.3,.3))).scaled(size),pos))
	rock_colors.append(Color("aaa995").darkened(rng.randf_range(0,.3)))

func _landscape() -> void:
	_hillside_mesh()
	# A lower belt of exposed limestone and herbs joins village shelves to the coast.
	for i in range(24):
		var x := -31.0+i*2.75
		var z := -14.1-sin(i*.7)*1.7
		var yy := _hill_height(x,z)
		_rock(Vector3(x,yy+.12,z),Vector3(2.9,1.9,2.4))
		if i%2==0: _bush(Vector3(x,yy+.93,z),Vector3(1.0,.65,.8))
	for i in range(88):
		var x := rng.randf_range(-59,52)
		var z := rng.randf_range(-63,-16)
		var yy := _hill_height(x,z)
		# Rocky seams and plants knit terraces to the larger landform.
		_rock(Vector3(x,yy-.4,z),Vector3(rng.randf_range(3,7),rng.randf_range(1.8,4),rng.randf_range(2.5,5)))
		if i%3==0:
			_cypress(Vector3(x,yy,z),rng.randf_range(6,10))
		elif i%3==1:
			_tree(Vector3(x,yy,z),rng.randf_range(4.5,8))
		else:
			_bush(Vector3(x,yy+.6,z),Vector3(2.5,1.6,2.4))
	for side in [-1,1]:
		for i in range(12):
			var x: float = side*rng.randf_range(28,51)
			var z := rng.randf_range(-15,-3)
			var yy := _hill_height(x,z)
			if yy>1:
				_tree(Vector3(x,yy,z),rng.randf_range(5,8))
	# Side promontories leave all navigable water clear.
	for side in [-1,1]:
		for i in range(16):
			var z := -9.0+i*1.35
			var x: float = side*(25.0+i*.65)
			if z > 2.0:
				x = side*(36.0+(z-2.0)*.4)
				if side>0:
					z=_east_coast_front(x)+rng.randf_range(-.35,.28)
			_rock(Vector3(x,.0,z),Vector3(rng.randf_range(1.4,2.4),rng.randf_range(.85,1.8),rng.randf_range(1.3,2.5)))
			if i<7 and i%2==0:
				_rock(Vector3(x,.2,z-2),Vector3(6,3.0,5))
				_tree(Vector3(x,1.4,z-2),rng.randf_range(3,5))
	# Distinct region landmarks beyond the harbor support orientation on water.
	if region_index==1:
		for i in range(12):
			_rock(Vector3(-43+rng.randf_range(-4,4),0,29+i*2),Vector3(4,rng.randf_range(3,8),4))
			if i%2==0: _tree(Vector3(-40,3,29+i*2),5)
	elif region_index==2:
		for i in range(7):
			_rock(Vector3(39+i*2,0,15+i*6),Vector3(4,8+i*.9,5))
		for side in [-1,1]:
			_sea_stack(Vector3(side*39,0,48),10.0,2.7)

func _lighthouse(pos: Vector3) -> void:
	for i in range(12):
		_rock(pos+Vector3(rng.randf_range(-5,5),-.2,rng.randf_range(-4,4)),Vector3(rng.randf_range(2,4),rng.randf_range(1,2),rng.randf_range(2,4)))
	_cylinder(pos+Vector3(0,3,0),1,6,trim,.7)
	_cylinder(pos+Vector3(0,5.4,0),.88,.42,roof)
	_cylinder(pos+Vector3(0,6.3,0),.55,1.2,dark)
	_cylinder(pos+Vector3(0,6.35,0),.47,.8,_mat(Color("e4ca8a")))
	_cylinder(pos+Vector3(0,7.0,0),.83,.55,roof,.01)
	_cylinder(pos+Vector3(0,5.87,0),1.1,.13,trim)
	for i in range(10):
		var angle := i*TAU/10
		_cylinder(pos+Vector3(cos(angle),6.12,sin(angle)),.03,.5,dark)

func _sailboat(pos: Vector3, size: float) -> void:
	var hull := _sphere(pos,Vector3(1.0,.48,2.8)*size,trim)
	hull.rotation.y=.6
	_cylinder(pos+Vector3(0,2.4*size,0),.045*size,4.8*size,wood)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.add_vertex(Vector3(.08,.7,0)*size)
	surface.add_vertex(Vector3(.08,4.7,0)*size)
	surface.add_vertex(Vector3(2.4,.7,.15)*size)
	surface.generate_normals()
	var item := MeshInstance3D.new()
	item.mesh=surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("f7ead0")
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	item.material_override=material
	item.position=pos
	add_child(item)

func _flush_instances() -> void:
	var mesh := _leaf_mesh()
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/foliage.gdshader")
	material.set_shader_parameter("tint",Color.WHITE)
	material.set_shader_parameter("leaf_spray",_leaf_texture())
	var leaf_chunks: Dictionary = {}
	for i in range(leaf_transforms.size()):
		var pos := leaf_transforms[i].origin
		var key := Vector2i(floori(pos.x/18),floori(pos.z/18))
		if not leaf_chunks.has(key): leaf_chunks[key]={"transforms":[],"colors":[]}
		leaf_chunks[key].transforms.append(leaf_transforms[i])
		leaf_chunks[key].colors.append(leaf_colors[i])
	for chunk in leaf_chunks.values():
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		transforms.assign(chunk.transforms)
		colors.assign(chunk.colors)
		_instances(mesh,transforms,colors,material)
	var rock_material := ShaderMaterial.new()
	rock_material.shader=load("res://shaders/coastal_rock.gdshader")
	_instances(_coastal_rock_mesh(),rock_transforms,rock_colors,rock_material)

func _instances(mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], material: Material, cast_shadows: bool = true) -> void:
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.use_colors=true
	multi.mesh=mesh
	multi.instance_count=transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i,transforms[i])
		multi.set_instance_color(i,colors[i].srgb_to_linear() if material == null else colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh=multi
	if not cast_shadows:
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material==null:
		var standard := StandardMaterial3D.new()
		standard.vertex_color_use_as_albedo=true
		standard.roughness=.9
		instance.material_override=standard
	else: instance.material_override=material
	add_child(instance)

func _batch_boxes() -> void:
	# Hundreds of windows, shutters and plank pieces share a few draw calls.
	var batches: Dictionary = {}
	for node in get_children():
		if not node is MeshInstance3D or not node.mesh is BoxMesh or node.get_child_count() > 0:
			continue
		var key: int = node.material_override.get_instance_id()
		if not batches.has(key):
			batches[key] = {"material":node.material_override,"transforms":[],"colors":[]}
		var trans: Transform3D = node.transform
		trans.basis = trans.basis * Basis.from_scale(node.mesh.size)
		batches[key].transforms.append(trans)
		batches[key].colors.append(Color.WHITE)
		remove_child(node)
		node.queue_free()
	for batch in batches.values():
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		transforms.assign(batch.transforms)
		colors.assign(batch.colors)
		_instances(_bevel_box(.025),transforms,colors,batch.material)

func _leaf_mesh() -> ArrayMesh:
	# A local painted leaf spray supplies rounded botanical edges at a low triangle cost.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed=98
	for i in range(18):
		var theta := random.randf()*TAU
		var elevation := random.randf_range(-.8,.9)
		var center := Vector3(cos(theta)*sqrt(1-elevation*elevation),elevation,sin(theta)*sqrt(1-elevation*elevation))*random.randf_range(.15,.68)
		var normal := (center*Vector3(1,1.7,1)+Vector3.UP*.5).normalized()
		var card_normal := Vector3(random.randf_range(-1,1),random.randf_range(-.3,1),random.randf_range(-1,1)).normalized()
		var basis := Basis(Quaternion(Vector3.FORWARD,card_normal))
		var radius := random.randf_range(.33,.50)
		var corners := [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
		for j in [0,1,2,0,2,3]:
			surface.set_uv(corners[j]*.5+Vector2.ONE*.5)
			surface.set_normal(normal)
			surface.add_vertex(center+basis*Vector3(corners[j].x*radius,corners[j].y*radius,0))
	return surface.commit()

func _leaf_texture() -> ImageTexture:
	# Original almond leaves with veins, painted into a texture once per region build.
	var picture := Image.create(128,128,false,Image.FORMAT_RGBA8)
	picture.fill(Color.TRANSPARENT)
	for i in range(94):
		var yy := 19+i
		var xx := int(62+sin(yy*.045)*4)
		picture.set_pixel(xx,yy,Color(.35,.43,.24,1))
		picture.set_pixel(xx+1,yy,Color(.43,.5,.28,1))
	for level in range(6):
		for side in [-1,1]:
			var center := Vector2(64+side*(17+level%2*3),23+level*15)
			var axis := Vector2(side*.80,-.61).normalized()
			var across := Vector2(-axis.y,axis.x)
			var length := 20.0+level%3*2.0
			var width := 9.5-level*.32
			for y in range(maxi(0,int(center.y-length)),mini(128,int(center.y+length)+1)):
				for x in range(maxi(0,int(center.x-length)),mini(128,int(center.x+length)+1)):
					var delta := Vector2(x,y)-center
					var u := delta.dot(axis)/length
					var v := delta.dot(across)/width
					var edge := u*u+v*v*(1+absf(u)*.75)
					if edge>=1: continue
					var shade := .79+.16*(1-v)*.5+.07*sin(level*2.3)
					if absf(v)<.040: shade*=.70
					if edge>.79: shade*=.83
					var value := Color(shade*.94,shade,shade*.84,clampf((1-edge)*10,0,1))
					picture.set_pixel(x,y,value)
	picture.generate_mipmaps()
	return ImageTexture.create_from_image(picture)

func _regional_details(season: int) -> void:
	# Shared harbor interactions stay fixed; surrounding coast changes its silhouette.
	if region_index == 0:
		for x in [-19,-5,10,20]:
			for i in range(4):
				_bush(Vector3(x,1.6+i*.55,-5.7),Vector3(.38,.44,.22))
		# Low flowering vines spill over the sunlit sea wall.
		for x in [-21,-17,-6,7,16,21]:
			_bush(Vector3(x,.95,.24),Vector3(.52,.23,.22))
	elif region_index == 1:
		# Jade Lagoon has a timber lookout, reeds, and rocky evergreen islets.
		for i in range(28):
			var reed_pos := Vector3(-35-rng.randf_range(0,3),.43,2+i*.38)
			var reed := _cylinder(reed_pos,.025,rng.randf_range(.7,1.2),green,.014)
			reed.rotation.z=.16
			if i%3==0: _cylinder(Vector3(-34+rng.randf_range(-1,1),.12,3+i*.32),.24,.02,green)
		var tower_pos := Vector3(-37,1,8)
		for dx in [-1.0,1.0]:
			for dz in [-1.0,1.0]:
				_cylinder(tower_pos+Vector3(dx,2.0,dz),.14,4.0,wood)
		_box(tower_pos+Vector3(0,4,0),Vector3(3.1,.2,3.1),wood)
		_roof(tower_pos+Vector3(0,6,0),3.7,3.7,1.1)
		for dx in [-1.2,1.2]:
			for dz in [-1.2,1.2]:
				_cylinder(tower_pos+Vector3(dx,5,dz),.08,2,wood)
		for i in range(11):
			var z := 19.0+i*3.1
			var x := -39.0-rng.randf_range(0,5)
			_rock(Vector3(x,0,z),Vector3(6,5,6))
			_pine(Vector3(x,2,z),rng.randf_range(6,10))
		for i in range(9):
			_lamp(Vector3(-20+i*5,1,-3.6))
	else:
		# Stormglass coast: eroded pillars, a broken stone arch, and wind-bent pines.
		for i in range(9):
			var x := 38.0+i*2.5
			var z := 16.0+i*3.4
			_sea_stack(Vector3(x+1.0,0,z),6.0+i*.8,2.25)
		_rock_arch(Vector3(-41,0,38))
		for i in range(5):
			_pine(Vector3(-29-i*1.5,3,-12-i*3),5+i*.6)
	if season > 0:
		var particles := CPUParticles3D.new()
		particles.amount=180
		particles.lifetime=3.5
		particles.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents=Vector3(35,2,30)
		particles.direction=Vector3(.5,-1,.15)
		particles.initial_velocity_min=3
		particles.initial_velocity_max=5
		particles.gravity=Vector3(1,-2,0)
		var rain := BoxMesh.new()
		rain.size=Vector3(.018,.22,.018)
		var material := StandardMaterial3D.new()
		material.albedo_color=Color(.65,.82,.85,.42)
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		rain.material=material
		particles.mesh=rain
		particles.position=Vector3(0,14,14)
		add_child(particles)

func _pine(pos: Vector3, height: float) -> void:
	_cylinder(pos+Vector3(0,height*.45,0),.16,height*.9,wood,.07)
	for i in range(6):
		var radius := (1.0-i/7.0)*height*.26
		_bush(pos+Vector3(i*.07,height*.35+i*height*.105,0),Vector3(radius,.48,radius))

func _bevel_box(bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var inner := .5-bevel
	for axis in range(3):
		for sign_value in [-1,1]:
			var poly: Array[Vector3] = []
			for signs in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var v := Vector3.ZERO
				v[axis]=sign_value*.5
				v[(axis+1)%3]=signs.x*inner
				v[(axis+2)%3]=signs.y*inner
				poly.append(v)
			_add_face(st,poly)
	for axis in range(3):
		for a in [-1,1]:
			for b in [-1,1]:
				var poly: Array[Vector3] = []
				for pair in [Vector2(-inner,0),Vector2(inner,0),Vector2(inner,1),Vector2(-inner,1)]:
					var v := Vector3.ZERO
					v[axis]=pair.x
					v[(axis+1)%3]=a*(.5 if pair.y==0 else inner)
					v[(axis+2)%3]=b*(inner if pair.y==0 else .5)
					poly.append(v)
				_add_face(st,poly)
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]:
				var poly: Array[Vector3] = [Vector3(x*.5,y*inner,z*inner),Vector3(x*inner,y*.5,z*inner),Vector3(x*inner,y*inner,z*.5)]
				_add_face(st,poly)
	st.generate_normals()
	return st.commit()

func _add_face(st: SurfaceTool, poly: Array[Vector3]) -> void:
	var center := Vector3.ZERO
	for p in poly: center+=p
	center/=poly.size()
	if (poly[1]-poly[0]).cross(poly[2]-poly[0]).dot(center)>0:
		poly.reverse()
	for i in range(1,poly.size()-1):
		st.add_vertex(poly[0])
		st.add_vertex(poly[i])
		st.add_vertex(poly[i+1])

func _hill_height(x: float, z: float) -> float:
	var depth := clampf((-z-11.0)/34.0,0,1)
	var ridge := depth*(9.0+20.0*exp(-pow((x+19.0)/29.0,2)))
	var side_coast := (5.4 if x>0 else 11.0)*exp(-pow((absf(x)-37.0)/10.0,2))*exp(-pow((z+16.0)/17.0,2))
	var edge := clampf((72.0-absf(x))/16.0,0,1)*clampf((-z+7.0)/14.0,0,1)
	var height := maxf(ridge,side_coast)*edge+sin(x*.19+z*.14)*.45-1.0
	# The low eastern shore curves toward the distant beacon. Its settled houses
	# remain in ordinary eastbound views, beyond the compact navigable bay.
	var coast_z := _east_coast_front(x)-4.0
	var east_window := smoothstep(24.0,32.0,x)*(1.0-smoothstep(78.0,96.0,x))
	var east_height := lerpf(4.2,1.8,clampf((x-28.0)/62.0,0,1))*exp(-pow((z-coast_z)/6.5,2))*east_window-1.0
	height=maxf(height,east_height)
	var back_ridge := lerpf(14.0,6.5,clampf((x-28.0)/50.0,0,1))*exp(-pow((z-(_east_coast_front(x)-24.0))/16.0,2))*east_window-1.0
	height=maxf(height,back_ridge)
	# The old Gaussian extended several metres beyond its stone edge as bare turf.
	# Sink the coast beyond its authored waterline below the seabed instead.
	var shore_drop := smoothstep(_east_coast_front(x)-.8,_east_coast_front(x)+3.0,z)*east_window
	height=lerpf(height,-22.0,shore_drop)
	var quay_clearance := smoothstep(-17,-10,z)*(1.0-smoothstep(21.5,27.5,absf(x)))
	height=lerpf(height,-1.3,quay_clearance)
	var open_bay := smoothstep(-1,4,z)*(1.0-smoothstep(32.0,37.0,absf(x)))
	return lerpf(height,-22.0,open_bay)

func _hillside_mesh() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Only the dedicated seabed owns submerged ground. Clip the land mesh at
	# the wet shoreline, instead of leaving its rectangular outer grid in water.
	var step := 1.25
	for zz in range(86):
		for xx in range(140):
			var x := -67.5+xx*step
			var z := -75.0+zz*step
			var a := Vector3(x,_hill_height(x,z),z)
			var b := Vector3(x+step,_hill_height(x+step,z),z)
			var c := Vector3(x,_hill_height(x,z+step),z+step)
			var d := Vector3(x+step,_hill_height(x+step,z+step),z+step)
			_add_dry_terrain_triangle(surface,[a,b,c])
			_add_dry_terrain_triangle(surface,[b,d,c])
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh=surface.commit()
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/terrain.gdshader")
	instance.material_override=material
	add_child(instance)

func _add_dry_terrain_triangle(surface: SurfaceTool, triangle: Array[Vector3]) -> void:
	const WET_EDGE := -.25
	var polygon: Array[Vector3] = []
	for i in range(3):
		var a := triangle[i]
		var b := triangle[(i+1)%3]
		var a_dry := a.y>=WET_EDGE
		var b_dry := b.y>=WET_EDGE
		if a_dry:
			polygon.append(a)
		if a_dry!=b_dry:
			polygon.append(a.lerp(b,(WET_EDGE-a.y)/(b.y-a.y)))
	for i in range(1,polygon.size()-1):
		for point: Vector3 in [polygon[0],polygon[i],polygon[i+1]]:
			var moss := .5+.5*sin(point.x*.6)*cos(point.z*.47)
			var color := Color("788151").lerp(Color("9d9a73"),moss*.65)
			surface.set_color(color.srgb_to_linear())
			surface.add_vertex(point)

func _terrace(base: Vector3, width: float, depth: float) -> void:
	var front := base.z+depth*.5
	_box(base+Vector3(0,-1.6,0),Vector3(width,3.1,depth),stone)
	var blocks: Array[Transform3D] = []
	var colors: Array[Color] = []
	for row in range(9):
		var x := base.x-width*.5
		while x<base.x+width*.5:
			var span := minf(rng.randf_range(.43,.74),base.x+width*.5-x)
			blocks.append(Transform3D(Basis.from_euler(Vector3(0,0,rng.randf_range(-.025,.025))).scaled(Vector3(maxf(.08,span-.02),.29,.19)),Vector3(x+span*.5,base.y-.17-row*.32,front+.04)))
			colors.append(Color("a6a28c").darkened(rng.randf_range(0,.16)))
			x+=span
	_instances(_bevel_box(.065),blocks,colors,null)
	_box(Vector3(base.x,base.y+.10,front),Vector3(width+.12,.15,.36),trim)
	for i in range(int(width/1.3)):
		_box(Vector3(base.x-width*.5+.25+i*1.3,base.y+.43,front),Vector3(.13,.74,.15),stone)
	_box(Vector3(base.x,base.y+.78,front),Vector3(width,.10,.16),trim)
	for i in range(4):
		_bush(Vector3(base.x-width*.40+i*width*.26,base.y-.22,front+.08),Vector3(.57,.72,.30))

func _cypress(pos: Vector3, height: float) -> void:
	_cylinder(pos+Vector3(0,height*.43,0),.12,height*.86,wood,.055)
	for i in range(6):
		var width := sin((i+1)*PI/8)*height*.11
		_bush(pos+Vector3(.12*sin(i),height*.30+i*height*.11,0),Vector3(width,height*.17,width*.85))

func _batch_cylinders() -> void:
	var batches: Dictionary = {}
	for node in get_children():
		if not node is MeshInstance3D or not node.mesh is CylinderMesh or node.get_child_count()>0:
			continue
		var radius: float = node.mesh.bottom_radius
		var ratio: float = node.mesh.top_radius/radius
		var key := str(node.material_override.get_instance_id())+"_"+str(snappedf(ratio,.01))
		if not batches.has(key):
			batches[key]={"material":node.material_override,"transforms":[],"colors":[],"ratio":ratio}
		var trans: Transform3D = node.transform
		trans.basis=trans.basis*Basis.from_scale(Vector3(radius,node.mesh.height,radius))
		batches[key].transforms.append(trans)
		batches[key].colors.append(Color.WHITE)
		remove_child(node)
		node.queue_free()
	for batch in batches.values():
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		transforms.assign(batch.transforms)
		colors.assign(batch.colors)
		var mesh := CylinderMesh.new()
		mesh.bottom_radius=1.0
		mesh.top_radius=batch.ratio
		mesh.height=1.0
		mesh.radial_segments=10
		_instances(mesh,transforms,colors,batch.material)

func set_daylight(fraction: float) -> void:
	if daylight_environment == null or not is_instance_valid(daylight_sun):
		return
	var sunset := 1.0-smoothstep(0.0,.46,clampf(fraction,0,1))
	daylight_sun.light_color=Color("ffedce").lerp(Color("ffbd7e"),sunset)
	daylight_sun.light_energy=lerpf(.72,.43,sunset)
	daylight_sun.rotation_degrees.x=lerpf(-43.0,-18.0,sunset)
	daylight_environment.ambient_light_energy=lerpf(.56,.45,sunset)
	daylight_environment.ambient_light_color=Color("b9d8df").lerp(Color("c5bccb"),sunset)
	daylight_environment.fog_light_color=Color("aac7c9").lerp(Color("d8b7a0"),sunset)
	daylight_sky.set_shader_parameter("sky_top",daylight_top.lerp(Color("78799b"),sunset))
	daylight_sky.set_shader_parameter("sky_horizon",daylight_horizon.lerp(Color("ecc4a3"),sunset))

func _shopkeeper(pos: Vector3, buyer: bool) -> void:
	var shirt := _mat(Color("6b9292") if buyer else Color("b87350"))
	var skin := _mat(Color("a97856") if buyer else Color("d4a574"))
	var apron := _mat(Color("e4d3a9"))
	var hair := _mat(Color("635447"))
	# Small apron-clad people and counters remain behind the clear shopping walkway.
	for side in [-1,1]:
		_cylinder(pos+Vector3(side*.105,.28,0),.09,.48,dark)
		_box(pos+Vector3(side*.105,.07,.08),Vector3(.18,.13,.30),hair)
	_box(pos+Vector3(0,.86,0),Vector3(.47,.67,.32),shirt)
	_box(pos+Vector3(0,.72,.18),Vector3(.37,.61,.045),apron)
	_cylinder(pos+Vector3(0,1.25,0),.065,.13,skin)
	_sphere(pos+Vector3(0,1.46,0),Vector3(.34,.39,.32),skin)
	_sphere(pos+Vector3(0,1.53,-.055),Vector3(.36,.28,.28),hair)
	for side in [-1,1]:
		_sphere(pos+Vector3(side*.065,1.48,.148),Vector3(.025,.026,.014),dark)
		var arm := _cylinder(pos+Vector3(side*.29,.90,.06),.075,.55,shirt)
		arm.rotation.z=side*.2
		_sphere(pos+Vector3(side*.34,.65,.11),Vector3(.12,.14,.12),skin)
	_sphere(pos+Vector3(0,1.42,.167),Vector3(.065,.077,.06),skin)
	_cylinder(pos+Vector3(0,1.66,0),.24,.06,apron)
	_cylinder(pos+Vector3(0,1.73,0),.16,.13,apron,.14)
	_box(pos+Vector3(0,.47,.52),Vector3(1.45,.82,.62),wood)
	_box(pos+Vector3(0,.93,.52),Vector3(1.55,.12,.72),trim)
	for i in range(4):
		var goods := _sphere(pos+Vector3(-.48+i*.30,1.02,.57),Vector3(.22,.07,.11) if buyer else Vector3(.08,.11,.08),_mat(Color("7caaa9") if buyer else Color("bd774f")))
		goods.rotation.y=.3

func _boundary_buoys() -> void:
	# Small navigation marks make the compact bay boundary readable from a boat.
	var positions: Array[Vector3] = []
	for side in [-1,1]:
		for z in [18,33,43]: positions.append(Vector3(side*30.0,0,z))
	for x in [-15,0,15]: positions.append(Vector3(x,0,43))
	var coral := _mat(Color("cd7657"))
	var cream := _mat(Color("ead9b2"))
	for pos in positions:
		_cylinder(pos+Vector3(0,.21,0),.24,.28,coral,.20)
		_cylinder(pos+Vector3(0,.37,0),.19,.10,cream,.15)
		_cylinder(pos+Vector3(0,.66,0),.032,.55,dark)
		_sphere(pos+Vector3(0,.99,0),Vector3(.15,.15,.15),cream)
		_box(pos+Vector3(.10,.85,0),Vector3(.21,.13,.02),coral)

func _sea_stack(pos: Vector3, height: float, radius: float) -> void:
	# Layered eroded sandstone, with an undercut waist and a broken mossy crown.
	var random := RandomNumberGenerator.new()
	random.seed=int(absf(pos.x*17.3+pos.z*11.9)*157)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rings: Array = []
	var sides := 11
	for level in range(8):
		var ring: Array[Vector3] = []
		var t := level/7.0
		var taper := 1.18-t*.44-.15*sin(t*PI)
		var center := Vector3(sin(t*2.4)*radius*.15,t*height,cos(t*3.1)*radius*.11)
		for j in range(sides):
			var angle := j*TAU/sides
			var rr := radius*taper*(1.0+.13*sin(j*2.4)+random.randf_range(-.09,.09))
			var yy := random.randf_range(-.12,.12) if level<7 else random.randf_range(-.35,.35)
			ring.append(center+Vector3(cos(angle)*rr,yy,sin(angle)*rr))
		rings.append(ring)
	for level in range(7):
		for j in range(sides):
			var next := (j+1)%sides
			var color := Color("8a9086").lerp(Color("b4ac95"),random.randf_range(.1,.85))
			if level==0: color=color.darkened(.23)
			if level==5: color=color.darkened(.10)
			st.set_color(color.srgb_to_linear())
			for vertex in [rings[level][j],rings[level][next],rings[level+1][j],rings[level][next],rings[level+1][next],rings[level+1][j]]:
				st.add_vertex(pos+vertex)
	for j in range(sides):
		st.set_color(Color("7e8762").srgb_to_linear())
		for vertex in [Vector3(0,height-.1,0),rings[7][j],rings[7][(j+1)%sides]]:
			st.add_vertex(pos+vertex)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh=st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=1.0
	mesh.material_override=material
	add_child(mesh)
	for j in range(3):
		var angle := j*TAU/3+.4
		_rock(pos+Vector3(cos(angle)*radius*.8,.10,sin(angle)*radius*.8),Vector3(radius*1.2,1.3,radius*1.1))
	_bush(pos+Vector3(radius*.15,height+.05,0),Vector3(radius*.5,.42,radius*.42))

func _rock_arch(pos: Vector3) -> void:
	# A continuous irregular stone arch, rather than columns with a rectangular lintel.
	_sea_stack(pos+Vector3(-4.5,0,0),6.2,1.65)
	_sea_stack(pos+Vector3(4.5,0,0),6.2,1.65)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var outer_front: Array[Vector3] = []
	var inner_front: Array[Vector3] = []
	var outer_back: Array[Vector3] = []
	var inner_back: Array[Vector3] = []
	for i in range(13):
		var a := i*PI/12
		var variation := .16*sin(i*2.7)
		outer_front.append(Vector3(cos(a)*(5.5+variation),5.7+sin(a)*(3.8+variation),1.25+variation))
		inner_front.append(Vector3(cos(a)*(3.65+variation),5.7+sin(a)*(1.85+variation),1.15+variation))
		outer_back.append(outer_front[i]*Vector3(1,1,-1))
		inner_back.append(inner_front[i]*Vector3(1,1,-1))
	for i in range(12):
		var color := Color("959a8a").lerp(Color("b1aa93"),(.5+.5*sin(i*1.7))*.6)
		st.set_color(color.srgb_to_linear())
		for quad in [[outer_front[i],inner_front[i],inner_front[i+1],outer_front[i+1]], [outer_back[i+1],inner_back[i+1],inner_back[i],outer_back[i]], [outer_front[i+1],outer_back[i+1],outer_back[i],outer_front[i]], [inner_front[i],inner_back[i],inner_back[i+1],inner_front[i+1]]]:
			for index in [0,1,2,0,2,3]: st.add_vertex(pos+quad[index])
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh=st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=1.0
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.material_override=material
	add_child(mesh)
	for i in range(3):
		var a := .55+i*.88
		_bush(pos+Vector3(cos(a)*4.7,6.0+sin(a)*3.7,0),Vector3(.9,.42,.7))

func _coastal_rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bands: Array = []
	var levels := 9
	var sides := 17
	for level in range(levels):
		var ring: Array[Vector3] = []
		var t := level/float(levels-1)
		var radius := sin(t*PI)*.47+.035
		for i in range(sides):
			var angle := i*TAU/sides
			var rough := 1.0+.075*sin(i*3.1+level*.72)+.035*cos(i*1.5-level)
			ring.append(Vector3(cos(angle)*radius*rough+sin(level*.73)*.025,(t-.5)*.90+sin(i*2.1+level)*.014,sin(angle)*radius*rough))
		bands.append(ring)
	for level in range(levels-1):
		for i in range(sides):
			var next := (i+1)%sides
			for vertex in [bands[level][i],bands[level][next],bands[level+1][i],bands[level][next],bands[level+1][next],bands[level+1][i]]: st.add_vertex(vertex)
	st.generate_normals()
	return st.commit()

func _east_coast_front(x: float) -> float:
	return -5.0+(x-28.0)*.22+sin(x*.23)*.45

func _coastal_quarter() -> void:
	# These waterfront homes continue the inhabited coastline ahead of the boat,
	# rather than exposing an empty terrain wedge when the player leaves the berth.
	var positions := [Vector2(30,-10),Vector2(40,-8),Vector2(50,-5.3),Vector2(61,-2.8),Vector2(72,-.5)]
	for i in range(positions.size()):
		var p: Vector2 = positions[i]
		var yy := _hill_height(p.x,p.y-1.7)+.25
		var size := Vector3(5.2-i*.24,4.8-(i%3)*.5,4.6-(i%2)*.4)
		_terrace(Vector3(p.x,yy,p.y),size.x+2.0,size.z+2.0)
		_building(Vector3(p.x,yy,p.y),size,palette[(i+1)%palette.size()],"",false,-.12+i*.045)
		_tree(Vector3(p.x-3.6,yy-.25,p.y-.6),4.9-i*.3)
		if i%2==0: _cypress(Vector3(p.x+3.1,yy-.15,p.y-3.1),5.6-i*.25)
		for j in range(3):
			_bush(Vector3(p.x-size.x*.45+j*size.x*.45,yy-.18,p.y+size.z*.5+.85),Vector3(.79,.64,.54))
	# Staggered homes step up two inland shelves. Their massing and gardens make
	# the normal alongshore camera see a village with depth, not one row of façades.
	for i in range(7):
		var x := 27.0+i*7.9+sin(i*1.7)*1.1
		var z := _east_coast_front(x)-14.5-rng.randf_range(0,2.8)
		var yy := _hill_height(x,z-2.0)+.15
		var size := Vector3(rng.randf_range(4.3,5.7),rng.randf_range(4.4,6.5),rng.randf_range(4.6,5.9))
		_terrace(Vector3(x,yy,z),size.x+1.9,size.z+2.1)
		_building(Vector3(x,yy,z),size,palette[(i+3)%palette.size()],"",false,rng.randf_range(-.25,.30)+(PI/2 if i%3==1 else 0.0))
		_tree(Vector3(x-size.x*.55-1.1,yy-.2,z+.5),rng.randf_range(4.8,6.6))
		_cypress(Vector3(x+size.x*.52+.8,yy-.25,z-1),rng.randf_range(6.5,8.3))
	for i in range(5):
		var x := 28.0+i*10.2+rng.randf_range(-1.1,1.1)
		var z := _east_coast_front(x)-27.5-rng.randf_range(0,4.0)
		var yy := _hill_height(x,z-2)+.18
		var size := Vector3(rng.randf_range(3.8,5.8),rng.randf_range(3.6,5.4),rng.randf_range(4.3,6.1))
		_terrace(Vector3(x,yy,z),size.x+1.7,size.z+1.9)
		_building(Vector3(x,yy,z),size,palette[(i+1)%palette.size()],"",false,rng.randf_range(-.38,.38))
		_cypress(Vector3(x+size.x*.65,yy,z+1.5),rng.randf_range(6.3,8.5))
		_tree(Vector3(x-size.x*.6,yy,z-1),rng.randf_range(4.6,6.3))
	# Narrow stone lanes climb between the tiers; shrubs overlap their edges.
	for i in range(4):
		var x := 33.0+i*10.3
		var front := _east_coast_front(x)
		_coastal_path([Vector2(x,front-3.7),Vector2(x-2.5,front-8.2),Vector2(x+1.0,front-12.5),Vector2(x-1.3,front-21.0)],1.0)
	for i in range(78):
		var x := rng.randf_range(25.0,78.0)
		var z := _east_coast_front(x)-rng.randf_range(3.8,28.0)
		var yy := _hill_height(x,z)
		if yy<.2: continue
		if i%4==0:
			_tree(Vector3(x,yy,z),rng.randf_range(4.2,6.5))
		else:
			_bush(Vector3(x,yy+.3,z),Vector3(rng.randf_range(.8,1.5),rng.randf_range(.45,.95),rng.randf_range(.75,1.35)))
	# Uneven outcrops overlap at the waterline: broad low slabs, tilted boulders,
	# and small loose stones break up a manufactured row without changing the coast.
	var coast_x := 25.0
	while coast_x<87.0:
		var spacing := rng.randf_range(1.85,3.15)
		var z := _east_coast_front(coast_x)
		var count := 2 if rng.randf()<.65 else 3
		for j in range(count):
			var xx := coast_x+rng.randf_range(-.65,.70)
			var zz := _east_coast_front(xx)+rng.randf_range(-.45,.30)
			var slab := j==0 and rng.randf()<.55
			_rock(Vector3(xx,rng.randf_range(-.16,.14),zz),Vector3(rng.randf_range(1.25,2.55),rng.randf_range(.65,1.05) if slab else rng.randf_range(1.15,1.80),rng.randf_range(1.2,2.25)))
		_rock(Vector3(coast_x+rng.randf_range(-.4,.5),rng.randf_range(.55,.95),z-rng.randf_range(1.0,1.7)),Vector3(rng.randf_range(1.6,2.8),rng.randf_range(1.7,2.5),rng.randf_range(1.5,2.3)))
		for j in range(3):
			var xx := coast_x+spacing*.55+rng.randf_range(-.4,.4)
			var zz := _east_coast_front(xx)+rng.randf_range(-.45,.18)
			_rock(Vector3(xx,-.10,zz),Vector3(rng.randf_range(.36,.82),rng.randf_range(.30,.65),rng.randf_range(.42,.85)))
		if rng.randf()<.78:
			var herb_z := z-rng.randf_range(2.1,2.65)
			_bush(Vector3(coast_x,_hill_height(coast_x,herb_z)+.24,herb_z),Vector3(rng.randf_range(.45,.92),rng.randf_range(.30,.53),rng.randf_range(.42,.74)))
		coast_x+=spacing
	# The far beacon sits on a low, irregular connected breakwater.
	for i in range(12):
		_rock(Vector3(81+i*.68,-.20,10.7+i*.39),Vector3(1.7,1.15,1.8))

func _coastal_path(points: Array, width: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(points.size()-1):
		var a: Vector2 = points[segment]
		var b: Vector2 = points[segment+1]
		var steps := maxi(1,ceili(a.distance_to(b)/.55))
		var side := Vector2(-(b-a).y,(b-a).x).normalized()*width*.5
		for i in range(steps):
			var aa := a.lerp(b,i/float(steps))
			var bb := a.lerp(b,(i+1)/float(steps))
			for p in [aa-side,bb-side,aa+side,aa+side,bb-side,bb+side]:
				st.add_vertex(Vector3(p.x,_hill_height(p.x,p.y)+.055,p.y))
	st.generate_normals()
	var path := MeshInstance3D.new()
	path.mesh=st.commit()
	path.material_override=trim
	add_child(path)
