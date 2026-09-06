extends Node3D
## World-space ball feedback. No gameplay state or contact decisions live here.
const G=preload("res://scripts/three_d/geometry.gd")
var ball:MeshInstance3D
var trail:MeshInstance3D
var ribbon:=ImmediateMesh.new()
var samples:Array[Vector3]=[]
var pulse_nodes:Array[MeshInstance3D]=[]
var pulses:Array[Dictionary]=[]

func _ready() -> void:
	var material:=ShaderMaterial.new()
	material.shader=preload("res://shaders/three_d/ball.gdshader")
	ball=G.sphere(self,Vector3.ZERO,Vector3.ONE*0.11,material)
	var trail_material:=G.matte(Color.WHITE)
	trail_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.vertex_color_use_as_albedo=true
	trail_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	trail=G.instance(self,ribbon,Vector3.ZERO,trail_material)
	trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in range(4):
		var torus:=TorusMesh.new()
		torus.inner_radius=0.92
		torus.outer_radius=1.0
		torus.rings=32
		torus.ring_segments=6
		var pulse_material:=G.matte(Color("ffe7a0"))
		pulse_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		pulse_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		var node:=G.instance(self,torus,Vector3.ZERO,pulse_material)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible=false
		pulse_nodes.append(node)

func contact(at:Vector3,quality:float,reduced:bool) -> void:
	if reduced: return
	var index:=0
	for i in range(pulse_nodes.size()):
		if not pulse_nodes[i].visible: index=i; break
	pulse_nodes[index].visible=true
	pulse_nodes[index].position=at
	pulses.append({"index":index,"age":0.0,"strength":quality})

func update_ball(at:Vector3,spin:float,delta:float,shown:bool,in_flight:bool,reduced:bool,camera:Camera3D) -> void:
	ball.visible=shown
	ball.position=at
	ball.rotation=Vector3(spin*0.3,spin,spin*0.2)
	ribbon.clear_surfaces()
	if not shown or not in_flight or reduced:
		samples.clear()
	elif delta>0:
		if not samples.is_empty() and samples[0].distance_to(at)>3: samples.clear()
		samples.push_front(at)
		if samples.size()>8: samples.pop_back()
	if samples.size()>2 and samples[0].distance_to(samples[-1])>0.00001:
		ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(samples.size()-1):
			var direction:=samples[i+1]-samples[i]
			if direction.length_squared()<0.000000001: continue
			var across:=direction.cross(camera.global_position-samples[i]).normalized()
			for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				var k:int=i+corner.y
				var fade:=1.0-float(k)/(samples.size()-1)
				ribbon.surface_set_color(Color(1,0.91,0.69,fade*0.28))
				ribbon.surface_add_vertex(samples[k]+across*(1 if corner.x==0 else -1)*0.043*fade)
		ribbon.surface_end()
	for pulse in pulses:
		pulse.age+=delta
		var node:MeshInstance3D=pulse_nodes[pulse.index]
		var fraction:float=clampf(pulse.age/0.18,0,1)
		node.scale=Vector3.ONE*lerpf(0.11,0.28,fraction)
		node.quaternion=Quaternion(Vector3.UP,(camera.global_position-node.position).normalized())
		node.material_override.albedo_color=Color(1,0.88,0.53,(1-fraction)*0.72)
		if fraction>=1: node.visible=false
	pulses=pulses.filter(func(p): return p.age<0.18)
