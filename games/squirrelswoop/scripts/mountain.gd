class_name SwoopMountain
extends Node3D

const Geometry = preload("res://scripts/geometry.gd")

const SIZE := 64.0
const STEP := 4.0
var mountain_seed := 1
var phase := 0.0
var chunks: Dictionary = {}
var pending: Array[Vector2i] = []
var focus := Vector2i(0,0)
var trunk_mesh: ArrayMesh
var crown_mesh: ArrayMesh
var crown_distant: ArrayMesh
var rock_mesh: ArrayMesh
var fern_mesh: ArrayMesh
var grass_mesh: ArrayMesh
var land_material: ShaderMaterial
var water_material: ShaderMaterial
var generated_count := 0
var generation_ms := 0.0

func _ready() -> void:
 trunk_mesh=Geometry.trunk()
 crown_mesh=Geometry.crown()
 crown_distant=Geometry.crown(false)
 rock_mesh=Geometry.rock()
 fern_mesh=Geometry.fern()
 grass_mesh=Geometry.grass()
 land_material=ShaderMaterial.new()
 land_material.shader=load("res://shaders/land.gdshader")
 water_material=ShaderMaterial.new()
 water_material.shader=load("res://shaders/water.gdshader")

func reset(value: int) -> void:
 for c in chunks.values(): c.node.free()
 chunks.clear()
 pending.clear()
 mountain_seed=value
 phase=float(posmod(value,10000))*0.001
 land_material.set_shader_parameter("mountain_seed",phase)
 generated_count=0
 focus=Vector2i(99999,99999)
 update_focus(Vector3.ZERO)
 # Populate the opening vista before revealing it.
 while not pending.is_empty(): build_chunk(pending.pop_front())

# Stable section parameters never depend on generation order or retain old sections.
func section_value(section: int, salt: int) -> float:
 return float(posmod(hash("%d:%d:%d"%[mountain_seed,section,salt]),100003))/100003.0

func section_blend(d: float, salt: int) -> float:
 var q := d/320.0
 var section := floori(q)
 var t := smoothstep(0.0,1.0,q-float(section))
 return lerpf(section_value(section,salt),section_value(section+1,salt),t)

func stream_x(d: float) -> float:
 return 12.0*sin(d*0.006+phase)+6.0*sin(d*0.017+phase*2.0)

func route(x: float, d: float) -> int:
 var relative := x-stream_x(d)
 if relative < -23.0: return 0
 if relative > 23.0: return 2
 return 1

func height_at(x: float, d: float) -> float:
 var relative := x-stream_x(d)
 var forest := smoothstep(12.0,75.0,relative)
 var waves := sin(d*0.027+phase)*1.3+sin(x*0.053+d*0.016)*0.8
 var knolls := sin(x*0.083+d*0.054+phase)*sin(d*0.036-x*0.02)*1.1
 var ravine := -3.2*exp(-pow(relative/7.0,2.0))
 # Smooth, seeded rock shelves descend sharply then recover over a gentler apron.
 # Each shelf meets its neighbours at zero displacement and zero derivative.
 var section := floori(d/320.0)
 var t := fposmod(d,320.0)/320.0
 var depth := lerpf(13.0,21.0,section_value(section,40))
 var shelf := smoothstep(0.12,0.28,t)*(1.0-smoothstep(0.48,0.96,t))
 var broken_ground := sin(x*0.22+d*0.17+phase)*sin(d*0.115-x*0.14)*1.25
 var drops := forest*(-depth*shelf+sin(d*0.045+phase)*1.1+broken_ground)
 return -d*0.47+waves+knolls+ravine+drops

func passage_centers(d: float, r: int) -> Vector2:
 var center := stream_x(d)
 var drift: float = (section_blend(d,10+r)-0.5)*[10.0,3.0,10.0][r]
 var fork: float = (section_blend(d,20+r)-0.5)*[10.0,1.5,8.0][r]
 match r:
  0: return Vector2(center-62.0+sin(d*0.010)*5.0+drift,center-100.0+sin(d*0.014+phase)*6.0-fork)
  1: return Vector2(center-9.0+drift,center+10.0-fork)
  _: return Vector2(center+43.0+sin(d*0.012+phase)*4.0+drift,center+76.0+sin(d*0.010+phase)*5.0-fork)

func connection_x(d: float) -> float:
 # A broad diagonal clearing continuously joins all three landscapes. Its maximum
 # sideways/downhill gradient is <0.48, reachable even at the 40m/s dive limit.
 var q := (d+phase*24.0)/800.0
 var section := floori(q)
 var t := smoothstep(0.0,1.0,q-float(section))
 if posmod(section,2)==1: t=1.0-t
 return stream_x(d)+lerpf(-70.0,80.0,t)

func clearance(x: float, d: float) -> float:
 var r := route(x,d)
 var centers := passage_centers(d,r)
 var width := [12.0,6.5,4.7][r] as float
 width+=section_blend(d,30+r)*[4.0,1.5,1.0][r]
 var along_route := minf(absf(x-centers.x),absf(x-centers.y))-width
 return minf(along_route,absf(x-connection_x(d))-7.5)

func formation_at(d: float) -> int:
 return mini(3,int(section_value(floori(d/320.0),50)*4.0))

func update_focus(pos: Vector3) -> void:
 var key := Vector2i(floori(pos.x/SIZE),floori(-pos.z/SIZE))
 if key==focus: return
 focus=key
 var wanted: Dictionary={}
 for dz in range(-2,7):
  for dx in range(-3,4):
   var k := key+Vector2i(dx,dz)
   wanted[k]=true
   if not chunks.has(k) and not pending.has(k): pending.append(k)
 for k in chunks.keys():
  if not wanted.has(k):
   chunks[k].node.queue_free()
   chunks.erase(k)
 pending=pending.filter(func(k: Vector2i) -> bool: return wanted.has(k))
 pending.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.distance_squared_to(focus)<b.distance_squared_to(focus))

func stream_next() -> void:
 if pending.is_empty(): return
 var started := Time.get_ticks_usec()
 build_chunk(pending.pop_front())
 generation_ms=float(Time.get_ticks_usec()-started)/1000.0

func instance_batch(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], shadow := true, begin := 0.0, end := 0.0) -> void:
 if transforms.is_empty(): return
 var multi := MultiMesh.new()
 multi.transform_format=MultiMesh.TRANSFORM_3D
 multi.mesh=mesh
 multi.instance_count=transforms.size()
 for i in transforms.size(): multi.set_instance_transform(i,transforms[i])
 var node := MultiMeshInstance3D.new()
 node.multimesh=multi
 node.visibility_range_begin=begin
 node.visibility_range_end=end
 if not shadow: node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(node)

func build_chunk(key: Vector2i) -> void:
 if chunks.has(key): return
 var root := Node3D.new()
 root.name="Section_%d_%d"%[key.x,key.y]
 add_child(root)
 var x0 := float(key.x)*SIZE
 var d0 := float(key.y)*SIZE
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for zi in 16:
  for xi in 16:
   var x := x0+float(xi)*STEP
   var d := d0+float(zi)*STEP
   var a := Vector3(x,height_at(x,d),-d)
   var b := Vector3(x+STEP,height_at(x+STEP,d),-d)
   var c := Vector3(x,height_at(x,d+STEP),-d-STEP)
   var e := Vector3(x+STEP,height_at(x+STEP,d+STEP),-d-STEP)
   for p in [a,c,b,b,c,e]:
    var px := p.x as float
    var pd := -p.z as float
    var dx := (height_at(px+0.1,pd)-height_at(px-0.1,pd))/0.2
    var dz := (height_at(px,pd-0.1)-height_at(px,pd+0.1))/0.2
    st.set_normal(Vector3(-dx,1,-dz).normalized())
    st.add_vertex(p)
 var land := MeshInstance3D.new()
 st.set_material(land_material)
 land.mesh=st.commit()
 root.add_child(land)
 # A winding ribbon shares the exact terrain function at every section seam.
 var ws := SurfaceTool.new()
 ws.begin(Mesh.PRIMITIVE_TRIANGLES)
 var has_water := false
 for zi in 32:
  var da := d0+float(zi)*2.0
  var db := da+2.0
  var cx := stream_x(da)
  if cx<x0-4.0 or cx>x0+SIZE+4.0: continue
  # Each water quad belongs to exactly one lateral section.
  if floori(cx/SIZE)!=key.x: continue
  has_water=true
  var cx2 := stream_x(db)
  var a := Vector3(cx-2.2,height_at(cx,da)+0.42,-da)
  var b := Vector3(cx+2.2,a.y,-da)
  var c := Vector3(cx2-2.2,height_at(cx2,db)+0.42,-db)
  var e := Vector3(cx2+2.2,c.y,-db)
  for p in [a,c,b,b,c,e]: ws.add_vertex(p)
 if has_water:
  var water := MeshInstance3D.new()
  water.mesh=Geometry.finish(ws,water_material)
  root.add_child(water)
 var rng := RandomNumberGenerator.new()
 rng.seed=hash("%d:%d:%d"%[mountain_seed,key.x,key.y])
 var trunks: Array[Transform3D]=[]
 var crowns: Array[Transform3D]=[]
 var rocks: Array[Transform3D]=[]
 var ferns: Array[Transform3D]=[]
 var grass: Array[Transform3D]=[]
 var obstacles: Array[Dictionary]=[]
 for zi in 8:
  for xi in 8:
   var x := x0+(float(xi)+rng.randf_range(0.15,0.85))*8.0
   var d := d0+(float(zi)+rng.randf_range(0.15,0.85))*8.0
   var r := route(x,d)
   var formation := formation_at(d)
   var progression := smoothstep(180.0,2600.0,maxf(0.0,d))
   var density := [0.10,0.29+progression*0.09,0.62+progression*0.20][r] as float
   # Groves, boulder gardens, fern glades and mixed woods change local line choices.
   # Meadows retain their cap; challenge grows through combinations outside passages.
   var clump := 0.5+0.5*sin(x*0.075+d*0.041+section_value(floori(d/320.0),51)*TAU)
   if formation==0: density*=lerpf(0.55,1.25,clump)
   elif formation==1: density*=0.55
   elif formation==2: density*=0.40
   var section_t := fposmod(d,320.0)/320.0
   var recovery := section_t>0.83
   if recovery: density*=0.38
   density=minf(density,[0.12,0.44,0.91][r])
   var scale_t := rng.randf_range(0.76,1.40)
   var radius := 0.92*scale_t
   var choice := rng.randf()
   var opening := d<35.0 and d> -24.0 and absf(x)<115.0
   var clear := clearance(x,d)
   # Check an interval, not just a point: bends cannot be pinched by an adjacent tree.
   clear=minf(clear,minf(clearance(x,d-5.0),clearance(x,d+5.0)))
   if choice<density and clear>radius+1.4 and not opening:
    var pos := Vector3(x,height_at(x,d)-0.35,-d)
    var basis_t := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(scale_t,scale_t,scale_t))
    trunks.append(Transform3D(basis_t,pos))
    crowns.append(Transform3D(basis_t,pos))
    obstacles.append({"kind":"tree","pos":pos,"radius":radius*0.86,"height":32.0*scale_t,"id":"%sT%d"%[key,zi*8+xi]})
    # Match the shared tree's solid branches. Foliage is deliberately soft.
    for branch_i in 11:
     var angle := float(branch_i)*2.399
     var h := 11.0+float(branch_i)*1.5
     var branch_a := pos+basis_t*Vector3(0,h,0)
     var branch_b := pos+basis_t*Vector3(cos(angle)*3.3,h+0.5,sin(angle)*3.3)
     obstacles.append({"kind":"branch","pos":branch_a,"end":branch_b,"radius":0.15*scale_t,"id":"%sT%dB%d"%[key,zi*8+xi,branch_i]})
    # Low deadwood gives the woods vertical choices, always outside guaranteed passages.
    var deadwood_chance := (0.12+progression*0.13)*(1.5 if formation==3 else 0.7)
    if r==2 and rng.randf()<deadwood_chance and clear>6.0:
     var b := pos+Vector3(-2.8,3.2,0)
     var e := pos+Vector3(3.6,3.8,0.6)
     var bs := SurfaceTool.new()
     bs.begin(Mesh.PRIMITIVE_TRIANGLES)
     Geometry.branch(bs,b,e,0.24,0.10,Color(0.27,0.23,0.13))
     var branch_node := MeshInstance3D.new()
     branch_node.mesh=Geometry.finish(bs,Geometry.material(Color.WHITE,true))
     root.add_child(branch_node)
     obstacles.append({"kind":"branch","pos":b,"end":e,"radius":0.22,"id":"%sB%d"%[key,zi*8+xi]})
   elif choice<density+(0.37 if formation==1 else 0.18) and clear>4.0 and not opening:
    var s := rng.randf_range(1.8,4.5) if r==2 else rng.randf_range(0.7,1.7)
    if clear<s*1.12+0.85: continue
    var pos := Vector3(x,height_at(x,d),-d)
    var rock_rotation := Basis(Vector3.UP,rng.randf()*TAU)
    rocks.append(Transform3D(rock_rotation.scaled(Vector3(s,s*0.8,s*1.1)),pos))
    obstacles.append({"kind":"rock","pos":pos+Vector3(0,s*0.46,0),"radius":s*0.95,"extents":Vector3(s*0.85,s*0.50,s*1.0),"inverse_rotation":rock_rotation.inverse(),"height":s*1.0,"id":"%sR%d"%[key,zi*8+xi]})
 # Small stones settle into the duff; below the body clearance they are surface detail.
 var chips: Array[Transform3D]=[]
 for i in 60:
  var x := x0+rng.randf()*SIZE
  var d := d0+rng.randf()*SIZE
  if route(x,d)!=2: continue
  var size_c := rng.randf_range(0.18,0.48)
  chips.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(size_c,size_c*0.3,size_c)),Vector3(x,height_at(x,d)-0.04,-d)))
 instance_batch(root,rock_mesh,chips,false,0,90)
 for i in 170:
  var x := x0+rng.randf()*SIZE
  var d := d0+rng.randf()*SIZE
  if absf(x-stream_x(d))<3.2: continue
  var pos := Vector3(x,height_at(x,d),-d)
  var s := rng.randf_range(0.5,1.1)
  var t := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*s),pos)
  if route(x,d)==2: ferns.append(t)
  else: grass.append(t)
 instance_batch(root,trunk_mesh,trunks)
 instance_batch(root,crown_mesh,crowns,true,0,140)
 instance_batch(root,crown_distant,crowns,false,140,360)
 instance_batch(root,rock_mesh,rocks)
 instance_batch(root,fern_mesh,ferns,false,0,105)
 instance_batch(root,grass_mesh,grass,false,0,110)
 chunks[key]={"node":root,"obstacles":obstacles}
 generated_count+=1

func obstacles_near(pos: Vector3) -> Array[Dictionary]:
 var out: Array[Dictionary]=[]
 var key := Vector2i(floori(pos.x/SIZE),floori(-pos.z/SIZE))
 for dz in range(-1,2):
  for dx in range(-1,2):
   var k := key+Vector2i(dx,dz)
   if chunks.has(k):
    for obstacle in chunks[k].obstacles:
     var obstacle_pos: Vector3=obstacle.pos
     if absf(obstacle_pos.x-pos.x)>20.0 or absf(obstacle_pos.z-pos.z)>42.0: continue
     # Crown branches are numerous, but only the nearby flight-height band can hit.
     if obstacle.kind=="branch" and absf(obstacle_pos.y-pos.y)>7.0: continue
     out.append(obstacle)
 return out
