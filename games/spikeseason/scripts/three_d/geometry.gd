extends RefCounted
## Project-owned mesh vocabulary. Profiles and skeleton poses own their proportions.

static func matte(color:Color) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.albedo_color=color
	m.roughness=0.92
	m.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	return m

static func surface(color:Color,pattern:int=0,grain:float=0.12) -> ShaderMaterial:
	var m:=ShaderMaterial.new()
	m.shader=preload("res://shaders/three_d/surface.gdshader")
	m.set_shader_parameter("base_color",color)
	m.set_shader_parameter("pattern",pattern)
	m.set_shader_parameter("grain",grain)
	return m

static func instance(parent:Node3D,mesh:Mesh,at:Vector3,material:Material) -> MeshInstance3D:
	var n:=MeshInstance3D.new()
	n.mesh=mesh
	n.material_override=material
	n.position=at
	parent.add_child(n)
	return n

static func box(parent:Node3D,at:Vector3,size:Vector3,material:Material) -> MeshInstance3D:
	var mesh:=BoxMesh.new()
	mesh.size=size
	return instance(parent,mesh,at,material)

static func sphere(parent:Node3D,at:Vector3,radii:Vector3,material:Material) -> MeshInstance3D:
	var mesh:=SphereMesh.new()
	mesh.radius=1.0
	mesh.height=2.0
	mesh.radial_segments=24
	mesh.rings=12
	var n:=instance(parent,mesh,at,material)
	n.scale=radii
	return n

static func beam(parent:Node3D,a:Vector3,b:Vector3,radius:float,material:Material,tip:float=-1.0,segments:int=10) -> MeshInstance3D:
	var mesh:=CylinderMesh.new()
	mesh.bottom_radius=radius
	mesh.top_radius=radius if tip<0 else tip
	mesh.height=a.distance_to(b)
	mesh.radial_segments=segments
	var n:=instance(parent,mesh,(a+b)*0.5,material)
	n.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	return n

static func profile(rings:Array,segments:int=24,hem_wave:float=0.0) -> ArrayMesh:
	# Each section stores height, half-width, and half-depth. Smooth elliptical loft.
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for r in range(rings.size()-1):
		for j in range(segments):
			for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				var ring:Vector3=rings[r+corner.y]
				var angle:=TAU*float(j+corner.x)/segments
				st.set_uv(Vector2(float(j+corner.x)/segments,float(r+corner.y)/(rings.size()-1)))
				st.add_vertex(Vector3(sin(angle)*ring.y,ring.x+hem_wave*sin(angle*3+0.7)*pow(1.0-float(r+corner.y)/(rings.size()-1),3),cos(angle)*ring.z))
	st.generate_normals()
	return st.commit()

static func lock_mesh(path:Array,width:float,depth:float) -> ArrayMesh:
	if path.size()==3:
		var curve:Array=[]
		for i in range(8):
			var t:=float(i)/7.0
			curve.append(path[0]*(1-t)*(1-t)+path[1]*2*t*(1-t)+path[2]*t*t)
		path=curve
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for r in range(path.size()-1):
		for j in range(8):
			for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				var k:int=r+corner.y
				var tangent:Vector3=(path[mini(k+1,path.size()-1)]-path[maxi(k-1,0)]).normalized()
				var basis:=Basis(Quaternion(Vector3.UP,tangent))
				var t:=float(k)/(path.size()-1)
				var taper:=maxf(0.015,pow(1.0-t,0.7))
				var angle:=TAU*float(j+corner.x)/8.0
				st.set_uv(Vector2(float(j+corner.x)/8,t))
				st.add_vertex(path[k]+basis*Vector3(sin(angle)*width*taper,0,cos(angle)*depth*taper))
	st.generate_normals()
	return st.commit()

static func pose_bone(node:Node3D,a:Vector3,b:Vector3) -> void:
	node.position=a
	node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	node.scale=Vector3(1,maxf(0.001,a.distance_to(b)),1)

static func text(parent:Node3D,value:String,at:Vector3,size:int,pixel:float,color:Color,back:bool=false) -> Label3D:
	var label:=Label3D.new()
	label.text=value
	label.font_size=size
	label.pixel_size=pixel
	label.modulate=color
	label.outline_size=0
	label.no_depth_test=false
	label.shaded=true
	label.position=at
	if not back: label.rotation.y=PI
	parent.add_child(label)
	return label

static func merge_static(parent:Node3D,excluded:Array=[]) -> void:
	var groups:Dictionary={}
	var replaced:Array[MeshInstance3D]=[]
	for child in parent.get_children():
		if not child is MeshInstance3D or excluded.has(child): continue
		var material:Material=child.material_override
		if not groups.has(material):
			var builder:=SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[material]=builder
		# All inputs must use the same index mode. Mixing indexed primitives with
		# non-indexed sculpted meshes otherwise leaves sculpted vertices unreferenced.
		var source:=SurfaceTool.new()
		source.create_from(child.mesh,0)
		source.deindex()
		groups[material].append_from(source.commit(),0,child.transform)
		replaced.append(child)
	for material in groups: instance(parent,groups[material].commit(),Vector3.ZERO,material)
	for child in replaced: child.free()
