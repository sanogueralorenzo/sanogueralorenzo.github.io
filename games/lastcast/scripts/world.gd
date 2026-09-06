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
	palette = [Color("e9b68d"), Color("e6c6a0"), Color("e4a18c"), Color("f0d8b0"), Color("c6d2bb")]
	if region == 1:
		palette = [Color("d5bdba"), Color("d9d3bb"), Color("a9bdc6"), Color("e7c8a9"), Color("cad4c3")]
	elif region == 2:
		palette = [Color("e4ac85"), Color("d5b597"), Color("c7b6a0"), Color("e1c997"), Color("babdaf")]
	stone = _mat(Color("b2b19a"))
	trim = _mat(Color("f1dec0"))
	wood = _mat(Color("937148"))
	dark = _mat(Color("25494b"))
	roof = ShaderMaterial.new()
	roof.shader = load("res://shaders/roof.gdshader")
	green = _mat(Color("657b50"))
	_environment(season)
	_water(season)
	_quay()
	_village()
	_shopkeeper(Vector3(-8,1,-4.6), false)
	_shopkeeper(Vector3(6,1,-4.6), true)
	_regional_details(season)
	_dock(Vector3(0, 0, 4), 3.2, 8.0)
	_dock(Vector3(-12, 0, 2.5), 3.0, 5.0)
	_sign("SHORE CASTING", Vector3(-14.0, 2.15, .4), .075)
	_sign("BOAT BERTH", Vector3(2.5, 2.2, .3), .085)
	_landscape()
	_lighthouse(Vector3(42, 0, 48))
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
	env.ambient_light_energy = .50
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
	sun.light_energy = .80
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
		material.set_shader_parameter("shallow", Color("51bfb2"))
		material.set_shader_parameter("deep", Color("175c73"))
	elif region_index == 2:
		material.set_shader_parameter("shallow", Color("369caa"))
		material.set_shader_parameter("deep", Color("163d64"))
	material.set_shader_parameter("wind", 1.0 + region_index * .35 + season * .25)
	item.material_override = material
	add_child(item)
	_box(Vector3(0, -1.15, 13), Vector3(75, .3, 30), _mat(Color("80b4a0")))

func _quay() -> void:
	_box(Vector3(0, -.35, -6.5), Vector3(46, 2.7, 13), stone, true)
	# Pavers use one MultiMesh, with warm variation and small joints.
	var pavers: Array[Transform3D] = []
	var colors: Array[Color] = []
	for z in range(13):
		for x in range(46):
			var offset := .5 if z % 2 else 0.0
			pavers.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.96, .08, .96)), Vector3(-22.7+x+offset,1.005,-12.5+z)))
			colors.append(Color("d1c6ab").darkened(rng.randf_range(0,.13)))
	_instances(_bevel_box(.025), pavers, colors, null, false)
	var blocks: Array[Transform3D] = []
	var block_colors: Array[Color] = []
	for row in range(3):
		for x in range(38):
			blocks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.15,.43,.4)),Vector3(-22.4+x*1.2+(row%2)*.3,.78-row*.46,.04)))
			block_colors.append(Color("b8b8a3").darkened(rng.randf_range(0,.22)))
	_instances(_bevel_box(.065),blocks,block_colors,null)
	for x in [-21,-17,-7,-4,5,9,14,19,22]:
		_box(Vector3(x,1.45,.0),Vector3(.30,.85,.33),stone)
		_cylinder(Vector3(x,1.93,.0),.20,.10,trim)
	for x in [-19,12,20]:
		_bench(Vector3(x,1,-2.6))
	for x in [-20,-3,15]:
		_lamp(Vector3(x,1,-3.7))
	for x in [-16,-2,12,21]:
		_planter(Vector3(x,1,-4.5))

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
	for i in range(12):
		_box(Vector3(-12.6,1+i*.25,-5.5-i*.47),Vector3(2.2,.25,.5),trim)
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
	_box(base+Vector3(0,size.y-.15,0),Vector3(size.x+.24,.23,size.z+.25),trim)
	_roof(base+Vector3(0,size.y,0),size.x+ .65,size.z+.65,1.15)
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
				_box(Vector3(x+side*.62,y,front+.05),Vector3(.29,1.2,.10),green)
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
	_box(Vector3(base.x,base.y+.96,front+.04),Vector3(.95,1.9,.12),dark)
	_box(Vector3(base.x+.32,base.y+.9,front+.15),Vector3(.06,.07,.05),trim)
	_cylinder(base+Vector3(size.x*.3,size.y+1.1,-size.z*.2),.23,1.3,stone)
	if awning:
		var canvas := _mat(Color("a8ad73") if title=="TACKLE" else Color("dfbb88"))
		var stripe := _mat(Color("efe0b7"))
		for i in range(10):
			var part := _box(Vector3(base.x-size.x*.5+(i+.5)*size.x/10,base.y+2.65,front+.72),Vector3(size.x/10,.085,1.65),canvas if i%2 else stripe)
			part.rotation.x = .13
			_box(Vector3(part.position.x,base.y+2.47,front+1.53),Vector3(size.x/10,.23,.07),canvas if i%2 else stripe)
		for side in [-1,1]:
			_cylinder(Vector3(base.x+side*(size.x*.5-.12),base.y+1.3,front+1.44),.055,2.6,wood)
		_box(Vector3(base.x,base.y+3.26,front+.18),Vector3(size.x*.85,.63,.18),wood)
		_sign(title,Vector3(base.x,base.y+3.27,front+.30),.105)

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

func _roof(pos: Vector3, width: float, depth: float, height: float) -> void:
	var vertices := PackedVector3Array([
		Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(0,height,-depth/2),
		Vector3(-width/2,0,depth/2),Vector3(0,height,depth/2),Vector3(width/2,0,depth/2),
		Vector3(-width/2,0,-depth/2),Vector3(0,height,-depth/2),Vector3(0,height,depth/2),
		Vector3(-width/2,0,-depth/2),Vector3(0,height,depth/2),Vector3(-width/2,0,depth/2),
		Vector3(0,height,-depth/2),Vector3(width/2,0,-depth/2),Vector3(width/2,0,depth/2),
		Vector3(0,height,-depth/2),Vector3(width/2,0,depth/2),Vector3(0,height,depth/2)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in vertices: surface.add_vertex(v)
	surface.generate_normals()
	var item := MeshInstance3D.new()
	item.mesh=surface.commit()
	item.material_override=roof
	item.position=pos
	add_child(item)
	for i in range(int(depth/.4)):
		_cylinder(pos+Vector3(0,height+.02,-depth*.5+i*.4),.12,.42,roof).rotation.x=PI/2

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
	_box(pos+Vector3(0,.5,0),Vector3(2.1,.14,.65),wood)
	_box(pos+Vector3(0,.95,-.30),Vector3(2.1,.55,.10),wood)
	for side in [-1,1]:
		_box(pos+Vector3(side*.77,.25,0),Vector3(.15,.5,.53),dark)

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
	for j in range(20):
		var offset := Vector3(rng.randf_range(-.75,.75),rng.randf_range(-.65,.65),rng.randf_range(-.75,.75))*size
		var scale_factor := rng.randf_range(.35,.66)
		leaf_transforms.append(Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf()*TAU,rng.randf())).scaled(size*scale_factor),pos+offset))
		var color := Color("94a65b").lerp(Color("4c713f"),rng.randf())
		if region_index==1: color=color.lerp(Color("8f9a7c"),.25)
		elif region_index==2: color=color.lerp(Color("b99d53"),.35)
		leaf_colors.append(color)

func _rock(pos: Vector3, size: Vector3) -> void:
	rock_transforms.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-.3,.3),rng.randf()*TAU,rng.randf_range(-.3,.3))).scaled(size),pos))
	rock_colors.append(Color("aaa995").darkened(rng.randf_range(0,.3)))

func _landscape() -> void:
	_hillside_mesh()
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
			if z > 2.0: x = side*(36.0+(z-2.0)*.4)
			_rock(Vector3(x,.0,z),Vector3(rng.randf_range(2,4),rng.randf_range(1,3.5),rng.randf_range(2,4)))
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
	var rock_mesh := SphereMesh.new()
	rock_mesh.radial_segments=7
	rock_mesh.rings=3
	_instances(rock_mesh,rock_transforms,rock_colors,null)

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
		_instances(BoxMesh.new(),transforms,colors,batch.material)

func _leaf_mesh() -> ArrayMesh:
	# Small bent leaf diamonds replace spherical canopy blobs with botanical edges.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random := RandomNumberGenerator.new()
	random.seed = 98
	for i in range(32):
		var theta := random.randf()*TAU
		var elevation := random.randf_range(-.9,.9)
		var origin := Vector3(cos(theta)*sqrt(1-elevation*elevation),elevation,sin(theta)*sqrt(1-elevation*elevation))*random.randf_range(.15,.65)
		var basis := Basis.from_euler(Vector3(random.randf()*PI,random.randf()*TAU,random.randf()*PI))
		var scale_factor := random.randf_range(.7,1.3)
		var points := [Vector3(0,.035,0),Vector3(0,0,.30),Vector3(.115,.025,0),Vector3(0,0,-.22),Vector3(-.115,.025,0)]
		for triangle in [[1,2,3],[1,3,4]]:
			for index in triangle:
				surface.add_vertex(origin+basis*(points[index]*scale_factor))
	surface.generate_normals()
	return surface.commit()

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
	if z > 2.0 and absf(x) < 34.0:
		return -1.5
	if z>-12.0 and absf(x)<24.0:
		return -1.5
	var depth := clampf((-z-11.0)/34.0,0,1)
	var ridge := depth*(9.0+20.0*exp(-pow((x+19.0)/29.0,2)))
	var side_coast := 11.0*exp(-pow((absf(x)-37.0)/10.0,2))*exp(-pow((z+16.0)/17.0,2))
	var edge := clampf((66.0-absf(x))/13.0,0,1)*clampf((-z+5.0)/12.0,0,1)
	return maxf(ridge,side_coast)*edge+sin(x*.19+z*.14)*.55-1.0

func _hillside_mesh() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zz in range(34):
		for xx in range(54):
			var x := -67.5+xx*2.5
			var z := -75.0+zz*2.5
			for off in [Vector2(0,0),Vector2(2.5,0),Vector2(0,2.5),Vector2(2.5,0),Vector2(2.5,2.5),Vector2(0,2.5)]:
				var yy := _hill_height(x+off.x,z+off.y)
				var moss := .5+.5*sin((x+off.x)*.6)*cos((z+off.y)*.47)
				var color := Color("788151").lerp(Color("9d9a73"),moss*.65)
				surface.set_color(color.srgb_to_linear())
				surface.add_vertex(Vector3(x+off.x,yy,z+off.y))
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh=surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.roughness=1.0
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	instance.material_override=material
	add_child(instance)

func _terrace(base: Vector3, width: float, depth: float) -> void:
	var front := base.z+depth*.5
	_box(base+Vector3(0,-1.6,0),Vector3(width,3.1,depth),stone)
	var blocks: Array[Transform3D] = []
	var colors: Array[Color] = []
	for row in range(5):
		for col in range(int(width/.8)):
			blocks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.77,.45,.26)),Vector3(base.x-width*.5+.4+col*.8+(row%2)*.13,base.y-.25-row*.48,front+.06)))
			colors.append(Color("b2b094").darkened(rng.randf_range(.05,.25)))
	_instances(_bevel_box(.04),blocks,colors,null)
	_box(Vector3(base.x,base.y+.12,front),Vector3(width+.15,.19,.42),trim)
	for i in range(int(width/1.3)):
		_box(Vector3(base.x-width*.5+.25+i*1.3,base.y+.48,front),Vector3(.16,.85,.18),stone)
	_box(Vector3(base.x,base.y+.84,front),Vector3(width,.13,.19),trim)
	for i in range(3):
		_bush(Vector3(base.x-width*.35+i*width*.35,base.y-.3,front+.1),Vector3(.62,.7,.23))

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
	daylight_sun.light_energy=lerpf(.80,.48,sunset)
	daylight_sun.rotation_degrees.x=lerpf(-43.0,-18.0,sunset)
	daylight_environment.ambient_light_energy=lerpf(.50,.41,sunset)
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
