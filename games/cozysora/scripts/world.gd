extends Node3D
## Coordinate system, deterministic height field and shared primitive construction.
## World dimensions and authored placements for Cozy Sora.

var roads: Array = []
var rail_points: Array[Vector2] = []
var _segments: Array = []
var _road_grid: Dictionary = {}
var _materials: Dictionary = {}
var player: CharacterBody3D
var _capture := ""
var _capture_frames := 0
var _capture_dir := ""
var _capture_views: Array[String] = []
var _ready_world := false
var _loading_layer: CanvasLayer
var _loading_label: Label
var _profile_elapsed := 0.0
var _profile_enabled := false
const ZONES := {
	"paddy": Rect2(63,-8,39,52), "paddy_in": Rect2(42,0,10,30),
	"farm": Rect2(28,42,36,34), "yard": Rect2(36,50,18,14),
	"village": Rect2(-36,56,50,32), "street": Rect2(-34,71,46,8),
	"vending": Rect2(-74,8,18,34), "pave": Rect2(-70,12,10,26),
	"gully": Rect2(10,88,36,18), "bed": Rect2(14,91,30,10)
}

func _ready() -> void:
	var start := Time.get_ticks_msec()
	_show_loading()
	await get_tree().process_frame
	_build_roads()
	_build_environment()
	_loading_label.text="GROWING THE WORLD…"
	await get_tree().process_frame
	_build_terrain()
	_build_coast_props()
	var settlement = load("res://scripts/settlements.gd").new()
	add_child(settlement)
	settlement.build(self)
	_loading_label.text="GROWING THE SUMMER GARDENS…"
	await get_tree().process_frame
	var vegetation = load("res://scripts/vegetation.gd").new()
	add_child(vegetation)
	vegetation.build(self)
	var life = load("res://scripts/summer_life.gd").new()
	add_child(life)
	life.build(self)
	player = load("res://scripts/player.gd").new()
	add_child(player)
	player.setup(self)
	_build_post()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): _capture = arg.trim_prefix("--capture=")
		if arg.begins_with("--capture-dir="):
			_capture_dir = arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(_capture_dir)
			_capture_views.assign(["coast","paddy","farm","rail","village","alley","vending","viaduct","shrine","top"])
			_capture = _capture_dir.path_join("start.png")
	_loading_layer.queue_free()
	_profile_enabled = "--profile" in OS.get_cmdline_user_args()
	_ready_world = true
	print("Cozy Sora READY build_ms=",Time.get_ticks_msec()-start," nodes=",get_tree().get_node_count())

func _process(_delta: float) -> void:
	if _ready_world and _profile_enabled:
		_profile_elapsed += _delta
		if _profile_elapsed>=5:
			_profile_elapsed=0
			print("Cozy Sora RUNTIME fps=",Engine.get_frames_per_second()," process_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	if is_instance_valid(player): RenderingServer.global_shader_parameter_set("cat_position",player.global_position)
	if _ready_world and not _capture.is_empty():
		_capture_frames += 1
		if _capture_frames == 45:
			var fps: float = Engine.get_frames_per_second()
			var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS)*1000
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_capture)
			print("Cozy Sora CAPTURE ",_capture," fps=",fps," drawcalls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," process_ms=",process_ms," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			if not _capture_views.is_empty():
				var next_view: String = _capture_views.pop_front()
				player.set_view(next_view)
				_capture = _capture_dir.path_join(next_view+".png")
				_capture_frames = 0
			elif "--quit-after-capture" in OS.get_cmdline_user_args(): get_tree().quit()

static func curve(x: float) -> float:
	return -.0022*x*x + .00001*x*x*x

static func smooth(a: float, b: float, value: float) -> float:
	var t := clampf((value-a)/(b-a),0,1)
	return t*t*(3-2*t)

static func hash2(x: float, z: float) -> float:
	return fposmod(sin(x*127.1+z*311.7)*43758.5453,1)

static func noise2(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := smooth(0,1,x-ix)
	var fz := smooth(0,1,z-iz)
	return lerpf(lerpf(hash2(ix,iz),hash2(ix+1,iz),fx),lerpf(hash2(ix,iz+1),hash2(ix+1,iz+1),fx),fz)

func spline(points: Array, closed: bool, subdivisions: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count := points.size()
	for i in range(count if closed else count-1):
		var p0: Vector2 = points[posmod(i-1,count) if closed else maxi(0,i-1)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i+1)%count]
		var p3: Vector2 = points[(i+2)%count if closed else mini(count-1,i+2)]
		for j in subdivisions:
			var t := float(j)/subdivisions
			out.append(.5*(2*p1+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
	if not closed: out.append(points[-1])
	return out

func _build_roads() -> void:
	var loop: Array = []
	for x in range(-38,39,4): loop.append(Vector2(x,-12.5+curve(x)))
	for p in [[50,-8],[56,4],[57,20],[55,36],[50,50],[40,60],[26,66],[10,68],[-10,68],[-26,66],[-40,60],[-50,50],[-55,36],[-57,20],[-56,4],[-50,-8]]:
		loop.append(Vector2(p[0],p[1]))
	var coast: Array = []
	for x in range(-100,131,5): coast.append(Vector2(x,-12.5+curve(x)))
	roads = [spline(loop,true,6),spline(coast,false,4)]
	for ri in roads.size():
		var pts: Array = roads[ri]
		var along := 0.0
		for i in range(pts.size() if ri==0 else pts.size()-1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i+1)%pts.size()]
			var length := a.distance_to(b)
			var id := _segments.size()
			_segments.append([a,b,length,along,ri])
			along += length
			for gz in range(floori((minf(a.y,b.y)-14)/8),floori((maxf(a.y,b.y)+14)/8)+1):
				for gx in range(floori((minf(a.x,b.x)-14)/8),floori((maxf(a.x,b.x)+14)/8)+1):
					var key := Vector2i(gx,gz)
					if not _road_grid.has(key): _road_grid[key]=[]
					_road_grid[key].append(id)
	var rails: Array=[]
	for p in [[-80,36],[-52,54],[-44,68],[-40,84],[-20,96],[60,96],[108,70]]: rails.append(Vector2(p[0],p[1]))
	rail_points = spline(rails,false,8)

func road_info(x: float,z: float) -> Dictionary:
	var out := {"d":99.0,"s":0.0,"tx":1.0,"tz":0.0,"side":1.0,"road":-1}
	var point := Vector2(x,z)
	var best := 9801.0
	for id in _road_grid.get(Vector2i(floori(x/8),floori(z/8)),[]):
		var seg: Array = _segments[id]
		var a: Vector2 = seg[0]
		var v: Vector2 = seg[1]-a
		var t := clampf((point-a).dot(v)/v.length_squared(),0,1)
		var delta := point-(a+v*t)
		var ds := delta.length_squared()
		if ds<best:
			best=ds
			out.s=seg[3]+t*seg[2]
			out.tx=v.x/seg[2]
			out.tz=v.y/seg[2]
			out.side=1.0 if v.cross(delta)>=0 else -1.0
			out.road=seg[4]
	out.d=sqrt(best)
	return out

func rail_distance(x: float,z: float) -> float:
	var best := 1000000.0
	var point := Vector2(x,z)
	for i in rail_points.size()-1:
		var a := rail_points[i]
		var v := rail_points[i+1]-a
		best=minf(best,(point-a-v*clampf((point-a).dot(v)/v.length_squared(),0,1)).length_squared())
	return sqrt(best)

func zone_weight(zone: Rect2,x: float,z: float,margin: float) -> float:
	var d := Vector2(maxf(maxf(zone.position.x-x,x-zone.end.x),0),maxf(maxf(zone.position.y-z,z-zone.end.y),0))
	return 1-smooth(0,margin,d.length())

func road_height(_x: float,z: float) -> float:
	return clampf(.045*(z+12),0,3)

func height_at(x: float,z: float) -> float:
	var zr := z-curve(x)
	var rough := (noise2(x*.08+3.1,z*.08+7.7)-.5)*1.4+(noise2(x*.35,z*.35)-.5)*.25
	var h := road_height(x,z)+rough
	h += smooth(-74,-125,x)*20*(1+.25*noise2(x*.03,z*.03))
	h += smooth(88,135,z)*25*(1+.25*noise2(x*.03+5,z*.03))
	h += smooth(104,145,x)*12*(1+.25*noise2(x*.03+9,z*.03+2))
	var radius := Vector2(x,z-30).length()
	h += 8*(1-smooth(8,27,radius))*(1+.08*noise2(x*.2,z*.2))
	if radius<8: h-=rough*.8
	for pair in [["paddy",.4],["paddy_in",.4],["farm",2.6],["village",3.0]]:
		h=lerpf(h,pair[1],zone_weight(ZONES[pair[0]],x,z,6))
	h=lerpf(h,road_height(x,z),zone_weight(ZONES.vending,x,z,6))
	h-=5.5*zone_weight(ZONES.bed,x,z,7)*(1-.3*noise2(x*.3,z*.3))
	h=lerpf(h,road_height(x,z),1-smooth(4.6,9.5,road_info(x,z).d))
	var lay := smooth(-12,-8,x)*(1-smooth(-4.8,.2,x))*(1-smooth(6,11,zr))*smooth(-11.5,-8.5,zr)
	h=lerpf(h,0,lay)+lay*(noise2(x*.6,z*.6)-.5)*.12
	if z< -4: h-=smooth(17,26,-zr)*34
	return maxf(h,-34)

func walkable(x: float,z: float) -> bool:
	return absf(x)<=118 and z<=100 and z>=-40 and not(z< -4 and z-curve(x)<-19.2) and height_at(x,z)>=-1.5

func excluded(x: float,z: float,margin: float=1.5) -> bool:
	if road_info(x,z).d<4+margin: return true
	for pair in [["paddy",1],["paddy_in",1],["yard",1],["street",4],["pave",2],["gully",2]]:
		if (ZONES[pair[0]] as Rect2).grow(pair[1]).has_point(Vector2(x,z)): return true
	return (z>30 and rail_distance(x,z)<4) or Vector2(x,z-30).length()<8 or (x>-11 and x<11 and z>5 and z<23)

func mat(hex: String) -> StandardMaterial3D:
	if _materials.has(hex): return _materials[hex]
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(hex)
	material.roughness=1
	material.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	_materials[hex]=material
	return material

func box(parent: Node3D,pos: Vector3,size: Vector3,material: Material,collision: bool=false) -> MeshInstance3D:
	var mesh:=BoxMesh.new()
	mesh.size=size
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material
	node.position=pos
	parent.add_child(node)
	if collision: add_collision_box(parent,pos,size)
	return node

func cylinder(parent: Node3D,pos: Vector3,bottom: float,top: float,height: float,material: Material) -> MeshInstance3D:
	var mesh:=CylinderMesh.new()
	mesh.bottom_radius=bottom
	mesh.top_radius=top
	mesh.height=height
	mesh.radial_segments=10
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material
	node.position=pos
	parent.add_child(node)
	return node

func sphere(parent: Node3D,pos: Vector3,size: Vector3,material: Material) -> MeshInstance3D:
	var mesh:=SphereMesh.new()
	mesh.radius=1
	mesh.height=2
	mesh.radial_segments=10
	mesh.rings=5
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material
	node.position=pos
	node.scale=size
	parent.add_child(node)
	return node

func beam(parent: Node3D,a: Vector3,b: Vector3,radius: float,material: Material) -> MeshInstance3D:
	var n:=cylinder(parent,(a+b)/2,radius,radius,a.distance_to(b),material)
	n.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	return n

func add_collision_box(parent: Node3D,pos: Vector3,size: Vector3) -> void:
	var body:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var primitive:=BoxShape3D.new()
	primitive.size=size
	shape.shape=primitive
	body.position=pos
	body.add_child(shape)
	parent.add_child(body)

func _build_terrain() -> void:
	var signature: String = get_script().source_code.sha256_text().substr(0,16)
	var terrain_cache: String = "user://terrain_"+signature+".res"
	var layout_cache: String = "user://layout_"+signature+".res"
	if FileAccess.file_exists(terrain_cache) and FileAccess.file_exists(layout_cache):
		_install_terrain(load(terrain_cache), load(layout_cache))
		return
	var image:=Image.create(1024,1024,false,Image.FORMAT_RGBA8)
	for j in 1024:
		var z := -180+(j+.5)*360/1024
		for i in 1024:
			var x := -180+(i+.5)*360/1024
			var ri := road_info(x,z)
			var zone := 0.0
			var point:=Vector2(x,z)
			if ZONES.paddy.has_point(point) or ZONES.paddy_in.has_point(point): zone=.2
			elif ZONES.street.has_point(point) or ZONES.pave.has_point(point): zone=.4
			elif ZONES.yard.has_point(point): zone=.6
			elif ZONES.bed.has_point(point) or (z>40 and z<110 and x>-90 and x<120 and rail_distance(x,z)<3.5): zone=.8
			image.set_pixel(i,j,Color(minf(ri.d,16)/16,fposmod(ri.s,8)/8,zone,1))
	var layout := ImageTexture.create_from_image(image)
	ResourceSaver.save(layout,layout_cache)
	# Sample the 360m terrain at .818m intervals.
	var verts:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var indices:=PackedInt32Array()
	const N:=440
	for j in N+1:
		var z:float=-180.0+360.0*j/N
		for i in N+1:
			var x:float=-180.0+360.0*i/N
			verts.append(Vector3(x,height_at(x,z),z))
			normals.append(Vector3.UP)
			uv.append(Vector2((x+180)/360,(z+180)/360))
	for j in range(1,N):
		for i in range(1,N):
			var k:=j*(N+1)+i
			normals[k]=Vector3(verts[k-1].y-verts[k+1].y,720.0/N,verts[k-N-1].y-verts[k+N+1].y).normalized()
	for j in N:
		for i in N:
			var a:=j*(N+1)+i
			indices.append_array([a,a+1,a+N+1,a+1,a+N+2,a+N+1])
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	ResourceSaver.save(mesh,terrain_cache)
	_install_terrain(mesh,layout)

func _install_terrain(mesh: ArrayMesh, layout: Texture2D) -> void:
	var terrain_mat:=ShaderMaterial.new()
	terrain_mat.shader=load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("layout_map",layout)
	var node:=MeshInstance3D.new()
	node.name="ProceduralTerrain"
	node.mesh=mesh
	node.material_override=terrain_mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	# Terrain collision covers the full playable area. Camera rays use the same surface.
	node.create_trimesh_collision()

func _build_environment() -> void:
	var env:=Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky:=Sky.new()
	var sky_mat:=ShaderMaterial.new()
	sky_mat.shader=load("res://shaders/sky.gdshader")
	sky.sky_material=sky_mat
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("7fb0d8")
	env.ambient_light_energy=.52
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure=1.0
	env.fog_enabled=true
	env.fog_light_color=Color("c9d6de")
	env.fog_mode=Environment.FOG_MODE_DEPTH
	env.fog_depth_begin=40
	env.fog_depth_end=260
	env.fog_depth_curve=1.0
	env.fog_sky_affect=.1
	var environment:=WorldEnvironment.new()
	environment.environment=env
	add_child(environment)
	var sun:=DirectionalLight3D.new()
	sun.name="SummerSun"
	sun.light_color=Color("ffcf9c")
	sun.light_energy=1.15
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=110
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias=.03
	sun.shadow_normal_bias=.7
	add_child(sun)
	sun.position=Vector3(-.55,.7,-.38)*120
	sun.look_at(Vector3.ZERO)
	var fill:=DirectionalLight3D.new()
	fill.light_color=Color("c9d6ec")
	fill.light_energy=.25
	add_child(fill)
	fill.position=Vector3(60,50,90)
	fill.look_at(Vector3.ZERO)
	var ocean:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(4000,4000)
	ocean.mesh=plane
	ocean.position.y=-30
	var water:=ShaderMaterial.new()
	water.shader=load("res://shaders/ocean.gdshader")
	ocean.material_override=water
	add_child(ocean)

func _build_post() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=-1
	var rect:=ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var effect:=ShaderMaterial.new()
	effect.shader=load("res://shaders/paint.gdshader")
	rect.material=effect
	layer.add_child(rect)
	add_child(layer)

func _wire(a: Vector3,b: Vector3,sag: float) -> void:
	var previous:=a
	for i in range(1,21):
		var t:=i/20.0
		var point:=a.lerp(b,t)-Vector3.UP*sin(t*PI)*sag
		beam(self,previous,point,.021,mat("5c636a"))
		previous=point

func _guardrail(points: Array[Vector2]) -> void:
	var previous:=Vector3.ZERO
	for i in points.size():
		var p:=Vector3(points[i].x,height_at(points[i].x,points[i].y),points[i].y)
		box(self,p+Vector3(0,.5,0),Vector3(.12,1,.12),mat("828986"),true)
		if i>0:
			var a:=previous+Vector3.UP*.7
			var b:=p+Vector3.UP*.7
			var n:=box(self,(a+b)/2,Vector3(.1,.25,a.distance_to(b)),mat("a3a9a4"))
			n.look_at_from_position((a+b)/2,b)
			# The low guardrail has a matching collision ribbon.
			add_collision_box(n,Vector3.ZERO,Vector3(.14,.7,a.distance_to(b)))
		previous=p

func _sign(pos:Vector3,text:String,color:String,size:Vector2=Vector2(.8,.5),yaw:float=0) -> void:
	var sign_root:=Node3D.new()
	add_child(sign_root)
	sign_root.position=pos
	sign_root.rotation.y=yaw
	cylinder(sign_root,Vector3(0,.65,0),.035,.035,1.3,mat("828986"))
	box(sign_root,Vector3(0,1.3,0),Vector3(size.x,size.y,.045),mat(color))
	if text==">>":
		for dx in [-size.x*.22,size.x*.19]:
			for side in [-1,1]:
				var bar:=box(sign_root,Vector3(dx,1.3+side*size.y*.14,.028),Vector3(size.x*.29,.055,.008),mat("343b3c"))
				bar.rotation.z=-side*.65
	else:
		var label:=Label3D.new()
		label.text=text
		label.font_size=64
		label.pixel_size=.005
		label.modulate=Color("343b3c")
		label.position=Vector3(0,1.3,.03)
		sign_root.add_child(label)

func _build_coast_props() -> void:
	var points:Array[Vector2]=[]
	for i in 7: points.append(Vector2(-9.35,6.5-i*2))
	for i in 13:
		var x:float=-10.2-i*3
		points.append(Vector2(x,-7.5+curve(x)))
	_guardrail(points)
	points=[]
	for x in range(-60,37,3): points.append(Vector2(x,-17.5+curve(x)))
	_guardrail(points)
	var tops:Array[Vector3]=[]
	for p in [Vector2(-34,-6.3+curve(-34)),Vector2(-10.5,-17.3+curve(-10.5)),Vector2(16,-17.3+curve(16)),Vector2(42,-17.3+curve(42)),Vector2(64,-17.3+curve(64))]:
		var y:=height_at(p.x,p.y)
		cylinder(self,Vector3(p.x,y+5,p.y),.19,.12,10.5,mat("9c9478"))
		box(self,Vector3(p.x,y+9,p.y),Vector3(2,.12,.18),mat("5c6358"))
		for dx in [-.85,0,.85]:
			cylinder(self,Vector3(p.x+dx,y+9.2,p.y),.085,.08,.3,mat("d9d9c8"))
		tops.append(Vector3(p.x,y+9.35,p.y))
		add_collision_box(self,Vector3(p.x,y+5,p.y),Vector3(.35,10,.35))
	for i in tops.size()-1:
		for dx in [-.85,0,.85]: _wire(tops[i]+Vector3(dx,0,0),tops[i+1]+Vector3(dx,0,0),1)
		_wire(tops[i]-Vector3.UP*2,tops[i+1]-Vector3.UP*2,1.2)
	var gantry_z:float=-18+curve(8)
	var base:=height_at(8,gantry_z)
	for x in [7.4,8.6]: cylinder(self,Vector3(x,base+5.1,gantry_z),.16,.13,10.5,mat("9c9478"))
	for y in [6.9,9.8]: box(self,Vector3(8,base+y,gantry_z),Vector3(1.4,.12,.16),mat("5c6358"))
	box(self,Vector3(8,base+6.5,gantry_z),Vector3(.85,.9,.14),mat("dadac8"))
	for x in [7.4,8.6]: _wire(Vector3(x,base+10,gantry_z),tops[2],.3)
	_sign(Vector3(-8.75,height_at(-8.75,3.2),3.2),">>","ddd879",Vector2(.5,.38))
	_sign(Vector3(-1,height_at(-1,-17.05),-17.05),">>","e5d478",Vector2(.85,.58),-.95)
	_sign(Vector3(40,height_at(40,-17.1+curve(40)),-17.1+curve(40)),">>","e5d478",Vector2(.8,.55),-1.35)
	_sign(Vector3(-12.5,height_at(-12.5,-17.2+curve(-12.5)),-17.2+curve(-12.5)),"↗","e5c063",Vector2(.7,.7))
	_sign(Vector3(24,height_at(24,-17.2+curve(24)),-17.2+curve(24)),"40","efe5d6",Vector2(.8,.8))
	# Parked olive kei car, 4.6m length, with distinct dark roof and glass cabin.
	var car:=Node3D.new()
	add_child(car)
	car.position=Vector3(21.5,height_at(21.5,-14.2+curve(21.5)),-14.2+curve(21.5))
	car.rotation.y=.08
	box(car,Vector3(0,.62,0),Vector3(4.6,.62,1.65),mat("70867e"),true)
	box(car,Vector3(0,1.2,0),Vector3(2.55,.65,1.5),mat("26394a"))
	box(car,Vector3(0,1.56,0),Vector3(2.7,.12,1.65),mat("3a3d44"))
	for x in [-1.5,1.5]:
		for z in [-.82,.82]:
			var wheel:=cylinder(car,Vector3(x,.37,z),.36,.36,.2,mat("1c1c1c"))
			wheel.rotation.x=PI/2
	for z in [-.56,.56]: box(car,Vector3(-2.31,.74,z),Vector3(.045,.2,.32),mat("c83332"))

func _show_loading() -> void:
	_loading_layer=CanvasLayer.new()
	_loading_layer.layer=10
	add_child(_loading_layer)
	var backdrop:=ColorRect.new()
	backdrop.color=Color("101e27")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(backdrop)
	_loading_label=Label.new()
	_loading_label.text="GROWING THE WORLD…"
	_loading_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_label.add_theme_color_override("font_color",Color("dcd9cc"))
	_loading_label.add_theme_font_size_override("font_size",16)
	_loading_layer.add_child(_loading_label)

func surface_at(x:float,z:float) -> String:
	var relative_z:=z-curve(x)
	if x>-9 and x<-3.8 and relative_z>-8.5 and relative_z<7: return "dirt"
	if road_info(x,z).d<4.3: return "road"
	if relative_z<-27 and z<-4: return "sea"
	var p:=Vector2(x,z)
	if ZONES.paddy.has_point(p) or ZONES.paddy_in.has_point(p): return "paddy"
	if ZONES.street.has_point(p) or ZONES.pave.has_point(p): return "concrete"
	if ZONES.yard.has_point(p): return "hardpack"
	if ZONES.bed.has_point(p) or (z>40 and rail_distance(x,z)<3.5): return "gravel"
	return "grass"
