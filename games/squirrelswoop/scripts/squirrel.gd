class_name SwoopSquirrel
extends Node3D

const Geometry = preload("res://scripts/geometry.gd")

var membrane: MeshInstance3D
var limbs: Array[Node3D]=[]
var tail: Node3D
var chestnut := Geometry.material(Color(0.30,0.105,0.032))
var fur_light := Geometry.material(Color(0.44,0.20,0.069))
var cream := Geometry.material(Color(0.61,0.42,0.23))
var skin := Geometry.material(Color(0.49,0.24,0.105))
var time := 0.0
var tuck := 0.0

func ellipsoid(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 var mesh := SphereMesh.new()
 mesh.radius=1.0
 mesh.height=2.0
 mesh.radial_segments=20
 mesh.rings=12
 node.mesh=mesh
 node.material_override=mat
 node.position=pos
 node.scale=size
 parent.add_child(node)
 return node

func _ready() -> void:
 skin.vertex_color_use_as_albedo=true
 skin.albedo_color=Color.WHITE
 skin.cull_mode=BaseMaterial3D.CULL_DISABLED
 skin.roughness=0.86
 ellipsoid(self,Vector3(0,0,0),Vector3(0.35,0.25,0.79),chestnut)
 ellipsoid(self,Vector3(0,-0.065,-0.08),Vector3(0.31,0.18,0.69),cream)
 ellipsoid(self,Vector3(0,0.08,-0.76),Vector3(0.30,0.27,0.33),fur_light)
 ellipsoid(self,Vector3(0,-0.02,-1.0),Vector3(0.19,0.15,0.22),chestnut)
 var dark := Geometry.material(Color(0.033,0.019,0.009))
 dark.roughness=0.25
 ellipsoid(self,Vector3(0,0.005,-1.17),Vector3(0.065,0.047,0.04),dark)
 for s in [-1.0,1.0]:
  var ear := ellipsoid(self,Vector3(s*0.23,0.28,-0.65),Vector3(0.125,0.19,0.08),chestnut)
  ear.rotation.z=-s*0.25
  ellipsoid(self,Vector3(s*0.235,0.29,-0.714),Vector3(0.075,0.12,0.025),cream)
  ellipsoid(self,Vector3(s*0.248,0.13,-0.896),Vector3(0.069,0.075,0.055),dark)
  ellipsoid(self,Vector3(s*0.265,0.16,-0.935),Vector3(0.018,0.021,0.012),Geometry.material(Color(0.97,0.94,0.80)))
 membrane=MeshInstance3D.new()
 add_child(membrane)
 for i in 4:
  var limb := Node3D.new()
  add_child(limb)
  limbs.append(limb)
  ellipsoid(limb,Vector3.ZERO,Vector3(0.11,0.07,0.17),chestnut)
  for toe in 3:
   ellipsoid(limb,Vector3(float(toe-1)*0.058,-0.025,-0.12),Vector3(0.024,0.025,0.11),cream)
 tail=Node3D.new()
 tail.position=Vector3(0,0.015,0.62)
 add_child(tail)
 # A continuous flattened brush, with a jagged fur silhouette and tapered tip.
 var tail_surface := SurfaceTool.new()
 tail_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 tail_surface.set_smooth_group(0)
 var tail_rng := RandomNumberGenerator.new()
 tail_rng.seed=771
 var rings: Array[PackedVector3Array]=[]
 for i in 17:
  var t := float(i)/16.0
  var width := 0.025+sin(t*PI)*0.32+(1.0-t)*0.055
  var thickness := 0.025+sin(t*PI)*0.070
  var ring := PackedVector3Array()
  for j in 18:
   var a := float(j)/18.0*TAU
   var irregular := tail_rng.randf_range(0.94,1.06)
   ring.append(Vector3(sin(t*1.4)*0.10+cos(a)*width*irregular,0.08+sin(t*2.6)*0.12+sin(a)*thickness,t*1.70))
  rings.append(ring)
 for i in 16:
  for j in 18:
   var k := (j+1)%18
   var shade := Color(0.37,0.17,0.055)
   Geometry.tri(tail_surface,rings[i][j],rings[i+1][j],rings[i+1][k],shade)
   Geometry.tri(tail_surface,rings[i][j],rings[i+1][k],rings[i][k],shade)
 var tail_shape := MeshInstance3D.new()
 var tail_material := ShaderMaterial.new()
 tail_material.shader=preload("res://shaders/fur.gdshader")
 tail_shape.mesh=Geometry.finish(tail_surface,tail_material)
 tail.add_child(tail_shape)
 var tail_fur_surface := SurfaceTool.new()
 tail_fur_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in 600:
  var t := tail_rng.randf_range(0.02,0.96)
  var a := tail_rng.randf()*TAU
  var width := 0.025+sin(t*PI)*0.32+(1.0-t)*0.055
  var thickness := 0.025+sin(t*PI)*0.070
  var p := Vector3(sin(t*1.4)*0.10+cos(a)*width,0.08+sin(t*2.6)*0.12+sin(a)*thickness,t*1.70)
  var normal := Vector3(cos(a)*0.8,sin(a)*0.5,0.8).normalized()
  var strand_side := Vector3(-sin(a),cos(a),0)*tail_rng.randf_range(0.007,0.014)
  var length := tail_rng.randf_range(0.065,0.16)
  Geometry.tri(tail_fur_surface,p-strand_side,p+normal*length,p+strand_side,Color(0.29,0.11,0.029).lerp(Color(0.50,0.26,0.09),tail_rng.randf()))
 var strand_material := Geometry.material(Color.WHITE,true)
 strand_material.cull_mode=BaseMaterial3D.CULL_DISABLED
 var tail_fur := MeshInstance3D.new()
 tail_fur.mesh=Geometry.finish(tail_fur_surface,strand_material)
 tail.add_child(tail_fur)
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rng := RandomNumberGenerator.new()
 rng.seed=452
 for i in 1100:
  var a := rng.randf()*TAU
  var z := rng.randf_range(-0.64,0.70)
  var r := sqrt(maxf(0.0,1.0-pow(z/0.82,2.0)))
  var p := Vector3(cos(a)*0.35*r,sin(a)*0.25*r,z)
  var normal := Vector3(cos(a),sin(a),0.1).normalized()
  var length := rng.randf_range(0.025,0.085)
  var side := Vector3(-sin(a),cos(a),0)*0.009
  Geometry.tri(st,p-side,p+normal*length+Vector3(0,0,length*0.6),p+side,Color(0.30,0.12,0.037).lerp(Color(0.54,0.29,0.105),rng.randf()))
 var fur := MeshInstance3D.new()
 fur.mesh=Geometry.finish(st,strand_material)
 add_child(fur)
 update_pose(0.016,0,0,0)

func update_pose(delta: float, bank: float, pitch: float, dive: float) -> void:
 time+=delta
 tuck=lerpf(tuck,dive,1.0-exp(-delta*9.0))
 rotation.z=lerpf(rotation.z,-bank*0.65,1.0-exp(-delta*8.0))
 rotation.x=lerpf(rotation.x,pitch*0.78,1.0-exp(-delta*7.0))
 tail.rotation.y=sin(time*2.8)*0.09-bank*0.3
 tail.rotation.x=-tuck*0.18+sin(time*3.2)*0.035
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 st.set_smooth_group(0)
 for side in [-1.0,1.0]:
  for j in 16:
   var t0 := float(j)/16.0
   var t1 := float(j+1)/16.0
   var pts: Array[Vector3]=[]
   for t in [t0,t1]:
    var z := lerpf(-0.72,0.78,t)
    var edge := lerpf(1.32,1.04,t)-sin(t*PI)*0.20
    edge=lerpf(edge,0.37,tuck)
    var billow := sin(t*PI)*0.24*(1.0-tuck)
    var flutter := sin(time*13.0+t*9.0)*0.012*(1.0-tuck)*sin(t*PI)
    pts.append(Vector3(side*0.24,-0.07,z))
    pts.append(Vector3(side*(edge*0.57+0.1),billow-0.055,z))
    pts.append(Vector3(side*edge,-0.09+flutter,z))
   var color := Color(0.36,0.17,0.058).lerp(Color(0.67,0.44,0.23),sin(t0*PI)*0.86)
   for band in 2:
    if side>0:
     Geometry.tri(st,pts[band],pts[band+1],pts[band+3],color)
     Geometry.tri(st,pts[band+1],pts[band+4],pts[band+3],color)
    else:
     Geometry.tri(st,pts[band],pts[band+3],pts[band+1],color)
     Geometry.tri(st,pts[band+1],pts[band+3],pts[band+4],color)
  var ix := 0 if side<0 else 2
  limbs[ix].position=Vector3(side*lerpf(1.32,0.37,tuck),-0.075,-0.72)
  limbs[ix+1].position=Vector3(side*lerpf(1.04,0.37,tuck),-0.075,0.78)
 membrane.mesh=Geometry.finish(st,skin)
