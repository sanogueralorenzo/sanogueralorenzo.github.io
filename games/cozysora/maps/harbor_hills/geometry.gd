extends RefCounted
## Harbor's static geometry is batched by material and spatial cell.
var root: Node3D
var groups = {}
var materials = {}
var primitives = {}
var collision: PhysicsBody3D
var ground_height: Callable

func _init(parent: Node3D,moving:bool=false) -> void:
	root=parent
	collision=AnimatableBody3D.new() if moving else StaticBody3D.new()
	collision.name="District collision"
	root.add_child(collision)

func material(color: String, kind: String="plaster") -> Material:
	var key=color+kind
	if materials.has(key):return materials[key]
	var m=ShaderMaterial.new()
	if kind=="foliage":
		m.shader=load("res://maps/harbor_hills/leaves.gdshader")
		m.set_shader_parameter("leaf_cards",true)
		m.set_shader_parameter("base_color",Color(color))
		materials[key]=m
		return m
	m.shader=load("res://maps/harbor_hills/surface.gdshader")
	m.set_shader_parameter("base_color",Color(color))
	m.set_shader_parameter("grain",.045 if kind=="metal" else .12)
	m.set_shader_parameter("pattern",1 if kind=="siding" else 2 if kind=="brick" else 3 if kind=="roof" else 0)
	materials[key]=m
	return m

func shape(kind: String) -> Mesh:
	if primitives.has(kind):return primitives[kind]
	var mesh: Mesh
	if kind=="box":mesh=BoxMesh.new()
	elif kind=="sphere":
		mesh=SphereMesh.new();mesh.radius=.5;mesh.height=1;mesh.radial_segments=10;mesh.rings=5
	elif kind=="leaf":
		var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var random=RandomNumberGenerator.new();random.seed=491
		for i in range(64):
			var center=Vector3(random.randf_range(-.48,.48),random.randf_range(-.35,.35),random.randf_range(-.48,.48))
			var normal=Vector3(random.randf_range(-1,1),random.randf_range(.15,1),random.randf_range(-1,1)).normalized()
			var basis=Basis(Quaternion(Vector3.FORWARD,normal));var radius=random.randf_range(.11,.23)
			var shade=random.randf_range(.72,1.22);st.set_color(Color(shade,shade,shade))
			var corners=[Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
			for j in [0,1,2,0,2,3]:
				st.set_uv(corners[j]*.5+Vector2.ONE*.5);st.set_normal(normal);st.add_vertex(center+basis*Vector3(corners[j].x*radius,corners[j].y*radius,0))
		mesh=st.commit()
	else:
		mesh=CylinderMesh.new();mesh.top_radius=.5;mesh.bottom_radius=.5;mesh.height=1;mesh.radial_segments=10
	primitives[kind]=mesh
	return mesh

func add(kind: String,pos: Vector3,size: Vector3,color: String,rotation: Vector3=Vector3.ZERO,solid: bool=false,finish: String="plaster") -> void:
	if kind=="leaf":finish="foliage"
	var transform=Transform3D(Basis.from_euler(rotation)*Basis.from_scale(size),pos)
	var cell=Vector2i(floori(pos.x/40),floori(pos.z/40))
	var key=kind+color+finish+str(cell)
	if not groups.has(key):groups[key]={"kind":kind,"material":material(color,finish),"transforms":[],"cell":cell}
	groups[key].transforms.append(transform)
	if solid:box_collision(pos,size,rotation)

func box(pos: Vector3,size: Vector3,color: String,solid: bool=false,yaw: float=0,finish: String="plaster") -> void:
	add("box",pos,size,color,Vector3(0,yaw,0),solid,finish)

func box_collision(pos: Vector3,size: Vector3,rotation: Vector3=Vector3.ZERO) -> void:
	var c=CollisionShape3D.new();var s=BoxShape3D.new();s.size=size;c.shape=s;c.position=pos;c.rotation=rotation;collision.add_child(c)

func beam(a: Vector3,b: Vector3,radius: float,color: String) -> void:
	var delta=b-a
	add("cylinder",(a+b)*.5,Vector3(radius*2,delta.length(),radius*2),color,Quaternion(Vector3.UP,delta.normalized()).get_euler(),false,"metal")

func ribbon(points: Array,width: float,color: String,solid: bool=false,drape: bool=true) -> void:
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a:Vector3=points[i];var b:Vector3=points[i+1]
		var side=(b-a).cross(Vector3.UP).normalized()*width*.5
		var corners=[a-side,b-side,b+side,a+side]
		if drape and ground_height.is_valid():
			# Keep the authored clearance while sampling both sides of the slope.
			var clearance_a=a.y-ground_height.call(a.x,a.z)
			var clearance_b=b.y-ground_height.call(b.x,b.z)
			for j in range(4):
				var v:Vector3=corners[j]
				v.y=ground_height.call(v.x,v.z)+(clearance_a if j in [0,3] else clearance_b)
				corners[j]=v
		for j in [0,1,2,0,2,3]:st.add_vertex(corners[j])
	st.generate_normals();var mesh=st.commit();var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=material(color);root.add_child(node)
	if solid:
		var c=CollisionShape3D.new();c.shape=mesh.create_trimesh_shape();collision.add_child(c)

func label(text: String,pos: Vector3,width: float,color: String="f4eedb",yaw: float=0,font_size: int=64) -> void:
	var n=Label3D.new();n.text=text;n.font_size=font_size;n.pixel_size=minf(width/maxf(1,text.length()*font_size*.57),.5/font_size);n.modulate=Color(color);n.position=pos;n.rotation.y=yaw;n.outline_size=0;n.no_depth_test=false;n.shaded=true;n.double_sided=false;n.visibility_range_end=85;root.add_child(n)

func finish() -> void:
	for key in groups:
		var group=groups[key];var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=shape(group.kind);mm.instance_count=group.transforms.size()
		var origin=Vector3(group.cell.x*40+20,0,group.cell.y*40+20)
		for i in mm.instance_count:
			var t:Transform3D=group.transforms[i];t.origin-=origin;mm.set_instance_transform(i,t)
		var node=MultiMeshInstance3D.new();node.name="Crafted district";node.multimesh=mm;node.material_override=group.material;node.position=origin;root.add_child(node)
	groups.clear()
