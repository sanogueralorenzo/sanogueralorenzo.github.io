class_name SwoopSquirrel
extends Node3D

const CharacterMesh = preload("res://scripts/character_mesh.gd")

var membrane: MeshInstance3D
var tail: Node3D
var paws: Array[Node3D]=[]
var bones: Array[Node3D]=[]
var ears: Array[Node3D]=[]
var fur_material: ShaderMaterial
var membrane_material: ShaderMaterial
var time := 0.0
var tuck := 0.0
var bank_pose := 0.0

func add_mesh(parent: Node3D, mesh: Mesh, position_at := Vector3.ZERO) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 node.mesh=mesh
 node.position=position_at
 parent.add_child(node)
 return node

func eye(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
 var material := StandardMaterial3D.new()
 material.albedo_color=color
 material.roughness=0.32
 var mesh := SphereMesh.new()
 mesh.radius=1.0
 mesh.height=2.0
 mesh.radial_segments=16
 mesh.rings=8
 mesh.material=material
 var node := add_mesh(parent,mesh,pos)
 node.scale=size

func _ready() -> void:
 fur_material=ShaderMaterial.new()
 fur_material.shader=preload("res://shaders/character_fur.gdshader")
 membrane_material=ShaderMaterial.new()
 membrane_material.shader=preload("res://shaders/membrane.gdshader")
 # One continuous profile joins muzzle, cheeks, shoulders, waist and haunches.
 var torso: Array[Vector4]=[
  Vector4(-1.20,0.025,0.026,0.015),Vector4(-1.13,0.10,0.065,0.025),
  Vector4(-1.03,0.18,0.13,0.060),Vector4(-0.88,0.255,0.22,0.10),
  Vector4(-0.73,0.27,0.24,0.085),Vector4(-0.57,0.285,0.215,0.045),
  Vector4(-0.39,0.325,0.215,0.020),Vector4(-0.13,0.335,0.205,0.015),
  Vector4(0.15,0.31,0.20,0.005),Vector4(0.39,0.29,0.195,-0.005),
  Vector4(0.57,0.235,0.17,-0.01),Vector4(0.73,0.12,0.10,0.0),
  Vector4(0.79,0.035,0.035,0.0)]
 add_mesh(self,CharacterMesh.loft(torso,Color(0.46,0.285,0.16),fur_material))
 add_mesh(self,CharacterMesh.coat_locks(torso,fur_material))
 var nose := CharacterMesh.surface()
 CharacterMesh.triangle(nose,Vector3(-0.05,0.045,-1.16),Vector3(0.05,0.045,-1.16),Vector3(0,0.005,-1.235),Color(0.16,0.12,0.085))
 CharacterMesh.triangle(nose,Vector3(-0.05,0.045,-1.16),Vector3(0,0.005,-1.235),Vector3(0,-0.02,-1.17),Color(0.19,0.135,0.09))
 CharacterMesh.triangle(nose,Vector3(0.05,0.045,-1.16),Vector3(0,-0.02,-1.17),Vector3(0,0.005,-1.235),Color(0.19,0.135,0.09))
 add_mesh(self,CharacterMesh.finish(nose,fur_material))
 var ear_mesh := CharacterMesh.ear(fur_material)
 var limb_mesh := CharacterMesh.tapered_limb(fur_material)
 var front_paw := CharacterMesh.paw(fur_material,false)
 var rear_paw := CharacterMesh.paw(fur_material,true)
 for side in [-1.0,1.0]:
  var ear := add_mesh(self,ear_mesh,Vector3(side*0.215,0.245,-0.725))
  ear.rotation.z=-side*0.22
  ears.append(ear)
  eye(self,Vector3(side*0.239,0.14,-0.95),Vector3(0.053,0.060,0.043),Color(0.035,0.022,0.015))
  eye(self,Vector3(side*0.258,0.166,-0.978),Vector3(0.012,0.014,0.009),Color(0.82,0.79,0.68))
  for i in 4: bones.append(add_mesh(self,limb_mesh))
  paws.append(add_mesh(self,front_paw))
  paws.append(add_mesh(self,rear_paw))
 # A few broad cheek/shoulder locks define fur direction without hiding the anatomy.
 var locks := CharacterMesh.surface()
 for side in [-1.0,1.0]:
  for i in 9:
   var z := -0.65+float(i)*0.145
   var width := 0.28+sin(float(i)/8.0*PI)*0.045
   var y := 0.08 if i<3 else 0.055
   var a := Vector3(side*width,y,z)
   CharacterMesh.triangle(locks,a+Vector3(-side*0.05,0.045,-0.025),a+Vector3(side*0.025,-0.008,0.115),a+Vector3(-side*0.02,-0.025,0.05),Color(0.47,0.30,0.17))
 add_mesh(self,CharacterMesh.finish(locks,fur_material))
 membrane=MeshInstance3D.new()
 add_child(membrane)
 tail=Node3D.new()
 tail.position=Vector3(0,0.005,0.68)
 add_child(tail)
 add_mesh(tail,CharacterMesh.brush_tail(fur_material))
 update_pose(0.016,0,0,0)

func pose_bone(node: Node3D, start: Vector3, end: Vector3, width: float, flatten := 1.0) -> void:
 var direction := end-start
 node.position=(start+end)*0.5
 node.quaternion=Quaternion(Vector3.BACK,direction.normalized())
 node.scale=Vector3(width,width*flatten,direction.length()*0.5)

func update_pose(delta: float, bank: float, pitch: float, dive: float) -> void:
 time+=delta
 tuck=lerpf(tuck,dive,1.0-exp(-delta*9.0))
 bank_pose=lerpf(bank_pose,bank,1.0-exp(-delta*8.0))
 rotation.z=-bank_pose*0.65
 rotation.x=lerpf(rotation.x,pitch*0.78,1.0-exp(-delta*7.0))
 # The tail steers into a bank and aligns with a dive; no periodic wing beats.
 tail.rotation.y=lerpf(tail.rotation.y,-bank_pose*0.28+sin(time*1.8)*0.018,1.0-exp(-delta*5.0))
 tail.rotation.x=lerpf(tail.rotation.x,-tuck*0.17+pitch*0.10,1.0-exp(-delta*6.0))
 tail.rotation.z=-bank_pose*0.07
 for i in ears.size(): ears[i].rotation.x=tuck*0.28
 var st := CharacterMesh.surface()
 for side_index in 2:
  var side := -1.0 if side_index==0 else 1.0
  var load := side*bank_pose*(1.0-tuck)
  var wrist := Vector3(side*lerpf(1.20,0.37,tuck),-0.055+load*0.055,lerpf(-0.74,-0.53,tuck))
  var ankle := Vector3(side*lerpf(0.89,0.31,tuck),-0.07-load*0.02,lerpf(0.74,0.67,tuck))
  var shoulder := Vector3(side*0.23,0.02,-0.45)
  var elbow := Vector3(side*lerpf(0.69,0.34,tuck),0.01+load*0.035,-0.48)
  var hip := Vector3(side*0.23,0.005,0.38)
  var knee := Vector3(side*lerpf(0.56,0.30,tuck),-0.025,0.48)
  var offset := side_index*4
  pose_bone(bones[offset],shoulder,elbow,0.078)
  pose_bone(bones[offset+1],elbow,wrist,0.049,0.82)
  pose_bone(bones[offset+2],hip,knee,0.092)
  pose_bone(bones[offset+3],knee,ankle,0.051,0.8)
  paws[side_index*2].position=wrist
  paws[side_index*2].rotation=Vector3(-0.08,-side*lerpf(0.52,0.05,tuck),-load*0.1)
  paws[side_index*2+1].position=ankle
  paws[side_index*2+1].rotation=Vector3(-0.12,-side*lerpf(2.35,2.85,tuck),0)
  # Patagium stays attached from forelimb to ankle, pulling taut as the limbs spread.
  for row in 16:
   for band in 4:
    var values := [Vector2(float(band)/4.0,float(row)/16.0),Vector2(float(band+1)/4.0,float(row)/16.0),Vector2(float(band)/4.0,float(row+1)/16.0),Vector2(float(band+1)/4.0,float(row+1)/16.0)]
    var points: Array[Vector3]=[]
    for uv: Vector2 in values:
     var t := uv.y
     var u := uv.x
     var edge := lerpf(absf(wrist.x),absf(ankle.x),t)-sin(t*PI)*0.26*(1.0-tuck)
     var x := lerpf(0.18,edge,u)
     var z := lerpf(wrist.z,ankle.z,t)+sin(t*PI)*u*0.03
     var tension := sin(t*PI)*sin(u*PI)
     var camber := tension*0.18*(1.0-tuck)
     var y := -0.065+camber+lerpf(wrist.y+0.055,ankle.y+0.07,t)*u
     y+=sin(time*10.0+t*7.0)*0.004*sin(t*PI)*u*u*(1.0-tuck)
     points.append(Vector3(side*x,y,z))
    var indices := [0,1,2,1,3,2] if side>0 else [0,2,1,1,2,3]
    for index: int in indices:
     var uv: Vector2 = values[index]
     var border := sin(uv.y*PI)
     var shade := Color(0.43,0.27,0.15).lerp(Color(0.66,0.50,0.32),pow(uv.x,0.7)*pow(border,0.35)*0.85)
     st.set_color(shade)
     st.set_uv(uv)
     st.add_vertex(points[index])
 membrane.mesh=CharacterMesh.finish(st,membrane_material)
