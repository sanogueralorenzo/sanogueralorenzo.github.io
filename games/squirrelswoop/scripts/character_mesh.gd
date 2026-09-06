class_name SwoopCharacterMesh
extends RefCounted

# Character-only modelling helpers. Profiles are (z, half width, half height, y).
static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
 st.set_color(color)
 st.add_vertex(a)
 st.add_vertex(b)
 st.add_vertex(c)

static func surface() -> SurfaceTool:
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 st.set_smooth_group(0)
 return st

static func finish(st: SurfaceTool, material: Material) -> ArrayMesh:
 st.generate_normals()
 st.set_material(material)
 return st.commit()

static func loft(profiles: Array[Vector4], color: Color, material: Material, underside := Color(0.63,0.48,0.30), sides := 24) -> ArrayMesh:
 var st := surface()
 for ring in range(profiles.size()-1):
  var a := profiles[ring]
  var b := profiles[ring+1]
  for i in sides:
   var angle := float(i)*TAU/float(sides)
   var next := float(i+1)*TAU/float(sides)
   var p := Vector3(cos(angle)*a.y,sin(angle)*a.z+a.w,a.x)
   var q := Vector3(cos(angle)*b.y,sin(angle)*b.z+b.w,b.x)
   var r := Vector3(cos(next)*b.y,sin(next)*b.z+b.w,b.x)
   var s := Vector3(cos(next)*a.y,sin(next)*a.z+a.w,a.x)
   var shade := color.lerp(underside,smoothstep(0.05,0.85,-sin(angle))*0.8)
   triangle(st,p,q,r,shade)
   triangle(st,p,r,s,shade)
 return finish(st,material)

static func tapered_limb(material: Material) -> ArrayMesh:
 var mesh := loft([Vector4(-1,0.22,0.22,0),Vector4(-0.83,0.82,0.82,0),Vector4(-0.35,1,1,0),Vector4(0.4,0.73,0.73,0),Vector4(0.91,0.52,0.52,0),Vector4(1,0.16,0.16,0)],Color(0.45,0.275,0.145),material,Color(0.57,0.405,0.245),12)
 return mesh

static func ear(material: Material) -> ArrayMesh:
 var st := surface()
 var outline := [Vector2(-0.065,0),Vector2(-0.10,0.11),Vector2(-0.075,0.23),Vector2(-0.025,0.29),Vector2(0.045,0.255),Vector2(0.09,0.14),Vector2(0.075,0.025)]
 var front := Vector3(0,0.12,0.015)
 var back := Vector3(0,0.12,0.07)
 for i in outline.size():
  var a: Vector2 = outline[i]
  var b: Vector2 = outline[(i+1)%outline.size()]
  var pa := Vector3(a.x,a.y,-0.015)
  var pb := Vector3(b.x,b.y,-0.015)
  triangle(st,front,pa,pb,Color(0.60,0.425,0.265))
  triangle(st,back,pb,pa,Color(0.37,0.22,0.125))
 return finish(st,material)

static func paw(material: Material, rear: bool) -> ArrayMesh:
 var st := surface()
 # Flattened palm, four slender curved digits, and small hooked claws.
 var profiles: Array[Vector4] = [Vector4(0.07,0.02,0.02,0),Vector4(0.015,0.07,0.035,0),Vector4(-0.095,0.063,0.025,-0.005),Vector4(-0.13,0.035,0.015,-0.015)]
 profiles.reverse()
 var palm := loft(profiles,Color(0.38,0.225,0.13),material,Color(0.50,0.36,0.23),12)
 st.append_from(palm,0,Transform3D.IDENTITY)
 for finger in 4:
  var x := float(finger)*0.035-0.0525
  var length := (0.125 if rear else 0.105)*(1.0-absf(float(finger)-1.5)*0.12)
  var a := Vector3(x,-0.002,-0.085)
  var b := a+Vector3(x*0.38,-0.005,-length*0.66)
  var c := b+Vector3(x*0.10,-0.025,-length*0.34)
  digit(st,a,b,0.015,0.011,Color(0.45,0.285,0.175))
  digit(st,b,c,0.011,0.006,Color(0.40,0.255,0.16))
  digit(st,c,c+Vector3(0,-0.018,-0.022),0.006,0.001,Color(0.25,0.205,0.15))
 return finish(st,material)

static func digit(st: SurfaceTool, a: Vector3, b: Vector3, width: float, end_width: float, color: Color) -> void:
 var axis := (b-a).normalized()
 var side := axis.cross(Vector3.UP).normalized()
 var up := side.cross(axis).normalized()
 for i in 8:
  var angle := float(i)*TAU/8.0
  var next := float(i+1)*TAU/8.0
  var n := side*cos(angle)+up*sin(angle)
  var n2 := side*cos(next)+up*sin(next)
  triangle(st,a+n*width,b+n2*end_width,b+n*end_width,color)
  triangle(st,a+n*width,a+n2*width,b+n2*end_width,color)

static func brush_tail(material: Material) -> ArrayMesh:
 var profiles: Array[Vector4]=[]
 for i in 25:
  var t := float(i)/24.0
  # Broad through the middle, then a gradual tip; much flatter than the torso.
  var width := 0.012+0.32*pow(sin(t*PI),0.8)+(1.0-t)*0.075
  var height := 0.018+sin(t*PI)*0.065
  profiles.append(Vector4(t*1.61,width,height,0.055+sin(t*PI)*0.065))
 var mesh := loft(profiles,Color(0.43,0.255,0.135),material,Color(0.50,0.335,0.185),24)
 var st := surface()
 st.append_from(mesh,0,Transform3D.IDENTITY)
 var coat := coat_locks(profiles,material,true)
 st.append_from(coat,0,Transform3D.IDENTITY)
 # Short overlapping scallops outline the brush; no random porcupine spikes.
 for side in [-1.0,1.0]:
  for i in 21:
   var t := 0.12+float(i)*0.037
   var width := 0.012+0.32*pow(sin(t*PI),0.8)+(1.0-t)*0.075
   var y := 0.055+sin(t*PI)*0.065
   var p := Vector3(side*width,y,t*1.61)
   var tip := p+Vector3(side*(0.025+sin(t*PI)*0.025),-0.015,0.095)
   triangle(st,p+Vector3(-side*0.04,0,0.055),tip,p+Vector3(0,0,-0.04),Color(0.46,0.29,0.16))
 return finish(st,material)


static func coat_locks(profiles: Array[Vector4], material: Material, tail_coat := false) -> ArrayMesh:
 var st := surface()
 var first := -0.60 if not tail_coat else 0.12
 var last := 0.55 if not tail_coat else 1.42
 var rows := 7 if not tail_coat else 8
 # Sparse staggered shallow locks suggest the coat's flow without a stitched grid.
 for row in rows:
  for column in 5:
   var phase := float(row*17+column*11)
   var z := lerpf(first,last,float(row)/float(rows-1))+sin(phase*2.17)*0.038
   z=clampf(z,first,last)
   var shape := profiles[0]
   for i in range(profiles.size()-1):
    if z>=profiles[i].x and z<=profiles[i+1].x:
     shape=profiles[i].lerp(profiles[i+1],inverse_lerp(profiles[i].x,profiles[i+1].x,z))
     break
   var stagger := (0.24 if row%2==0 else -0.24)+sin(phase*1.73)*0.13
   var angle := lerpf(0.26,PI-0.26,clampf((float(column)+stagger)/4.0,0.0,1.0))
   var normal := Vector3(cos(angle)*0.5,sin(angle),0).normalized()
   var across := Vector3(-sin(angle),cos(angle),0).normalized()
   var p := Vector3(cos(angle)*shape.y,sin(angle)*shape.z+shape.w,z)
   var half_width := (0.025 if not tail_coat else 0.028)*(0.8+sin(phase*2.51)*0.2)
   var length := 0.09+(0.5+sin(phase*1.91)*0.5)*0.055
   var relief := 0.006+(0.5+sin(phase*2.31)*0.5)*0.003
   var root_left := p-across*half_width+normal*0.002
   var root_right := p+across*half_width+normal*0.002
   var ridge := p+Vector3(0,0,length*0.38)+normal*relief
   var tip := p+Vector3(cos(angle)*0.012,-0.005,length)+normal*0.002
   var base := Color(0.455,0.285,0.16) if not tail_coat else Color(0.43,0.26,0.14)
   var shade := base.lightened((0.5+sin(phase*2.7)*0.5)*0.018)
   triangle(st,root_left,ridge,root_right,shade)
   triangle(st,ridge,tip,root_right,shade)
 return finish(st,material)
