class_name SwoopMountain
extends Node3D

const Geometry = preload("res://scripts/geometry.gd")

const SIZE := 64.0
const STEP := 4.0
const COLLISION_CELL := 12.0
var mountain_seed := 1
var phase := 0.0
var chunks: Dictionary = {}
var pending: Array[Vector2i] = []
var focus := Vector2i(0,0)
var tree_variants: Array[Dictionary]=[]
var vertex_heights: Dictionary={}
var formation_regions: Dictionary={}
var section_values: Dictionary={}
var generation_epoch := 0
var building := false
var active_chunk: Node3D
var generation_slice_ms := 0.0
var last_generation_frame := -1
var wood_material: ShaderMaterial
var rock_mesh: ArrayMesh
var fern_mesh: ArrayMesh
var grass_mesh: ArrayMesh
var land_material: ShaderMaterial
var water_material: ShaderMaterial
var generated_count := 0
var generation_ms := 0.0

func _ready() -> void:
 for i in 3: tree_variants.append(Geometry.tree_variant(i))
 wood_material=ShaderMaterial.new()
 wood_material.shader=load("res://shaders/bark.gdshader")
 rock_mesh=Geometry.rock()
 fern_mesh=Geometry.fern()
 grass_mesh=Geometry.grass()
 land_material=ShaderMaterial.new()
 land_material.shader=load("res://shaders/land.gdshader")
 water_material=ShaderMaterial.new()
 water_material.shader=load("res://shaders/water.gdshader")

func reset(value: int) -> void:
 generation_epoch+=1
 if is_instance_valid(active_chunk): active_chunk.free()
 active_chunk=null
 building=false
 section_values.clear()
 for c in chunks.values(): c.node.free()
 chunks.clear()
 pending.clear()
 vertex_heights.clear()
 formation_regions.clear()
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
 var key := Vector2i(section,salt)
 if not section_values.has(key): section_values[key]=float(posmod(hash("%d:%d:%d"%[mountain_seed,section,salt]),100003))/100003.0
 return section_values[key]

# Unequal spans are derived locally: visiting a distant region never walks or stores
# the entire mountain. Three or four formations share each 1024m region.
func formation_span(d: float) -> Vector3:
 var region := floori(d/1024.0)
 if not formation_regions.has(region):
  var count := 3+int(section_value(region,70)*2.0)
  var weights: Array[float]=[]
  var total := 0.0
  for i in count:
   var weight := lerpf(0.75,1.30,section_value(region,71+i))
   weights.append(weight)
   total+=weight
  var spans: Array[Vector3]=[]
  var cursor := float(region)*1024.0
  for i in count:
   var next := cursor+1024.0*weights[i]/total
   if i==count-1: next=float(region+1)*1024.0
   spans.append(Vector3(cursor,next,float(region*4+i)))
   cursor=next
  formation_regions[region]=spans
 var spans: Array=formation_regions[region]
 for span: Vector3 in spans:
  if d<span.y: return span
 return spans.back()

func formation_progress(d: float) -> float:
 var span := formation_span(d)
 return clampf((d-span.x)/(span.y-span.x),0.0,1.0)

func section_blend(d: float, salt: int) -> float:
 # Independent, broad drift keeps route curvature bounded across formation changes.
 var q := d/420.0
 var section := floori(q)
 var t := smoothstep(0.0,1.0,q-float(section))
 return lerpf(section_value(section,salt),section_value(section+1,salt),t)

func stream_x(d: float) -> float:
 return 12.0*sin(d*0.006+phase)+6.0*sin(d*0.017+phase*2.0)

func channel_x(d: float) -> float:
 return stream_x(d)+0.85*sin(d*0.09+phase)

func stream_pool(d: float) -> float:
 return pow(maxf(0.0,sin(d*0.047+phase*1.3)),6.0)

func stream_width(d: float) -> float:
 return 1.55+0.35*sin(d*0.031+phase)+0.22*sin(d*0.079+phase*1.7)+stream_pool(d)*0.70

func route(x: float, d: float) -> int:
 var relative := x-stream_x(d)
 if relative < -23.0: return 0
 if relative > 23.0: return 2
 return 1

func raw_height(x: float, d: float) -> float:
 var relative := x-stream_x(d)
 var forest := smoothstep(12.0,75.0,relative)
 var waves := sin(d*0.027+phase)*1.3+sin(x*0.053+d*0.016)*0.8
 var knolls := sin(x*0.083+d*0.054+phase)*sin(d*0.036-x*0.02)*1.1
 var ravine := -(3.2-stream_pool(d)*0.40)*exp(-pow((x-channel_x(d))/7.0,2.0))
 var span := formation_span(d)
 var t := (d-span.x)/(span.y-span.x)
 var formation := formation_at(d)
 # The short spans receive shallower shelves, bounding grade independently of seed.
 var depth := minf(23.0,(span.y-span.x)*0.066)*lerpf(0.80,1.0,section_value(int(span.z),40))
 depth*=[0.88,1.0,0.52,0.95][formation]
 var shelf := smoothstep(0.16,0.37,t)*(1.0-smoothstep(0.52,0.97,t))
 var broken_ground := sin(x*0.22+d*0.17+phase)*sin(d*0.115-x*0.14)*0.85
 var drops := forest*(-depth*shelf+sin(d*0.045+phase)*1.1+broken_ground)
 return -d*0.47+waves+knolls+ravine+drops

func grid_height(x: int, d: int) -> float:
 var key := Vector2i(x,d)
 if not vertex_heights.has(key): vertex_heights[key]=raw_height(float(x)*STEP,float(d)*STEP)
 return vertex_heights[key]

func height_at(x: float, d: float) -> float:
 # Exact barycentric height on the visible a-c-b / b-c-e triangle pair. Physics,
 # roots, stones and water all use this same surface, including across chunk seams.
 var gx := floori(x/STEP)
 var gd := floori(d/STEP)
 var u := x/STEP-float(gx)
 var v := d/STEP-float(gd)
 var b := grid_height(gx+1,gd)
 var c := grid_height(gx,gd+1)
 if u+v<=1.0:
  return grid_height(gx,gd)*(1.0-u-v)+b*u+c*v
 return grid_height(gx+1,gd+1)*(u+v-1.0)+b*(1.0-v)+c*(1.0-u)

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

func route_clearance(x: float, d: float, r: int) -> float:
 var centers := passage_centers(d,r)
 var width := [12.0,6.5,4.7][r] as float
 width+=section_blend(d,30+r)*[4.0,1.5,1.0][r]
 return minf(absf(x-centers.x),absf(x-centers.y))-width

func clearance(x: float, d: float) -> float:
 var r := route(x,d)
 var relative := x-stream_x(d)
 var along_route := route_clearance(x,d,r)
 # A large obstacle beside a biome transition must respect its neighbour's opening.
 if r!=0 and relative< -7.0: along_route=minf(along_route,route_clearance(x,d,0))
 if r!=1 and absf(relative)<39.0: along_route=minf(along_route,route_clearance(x,d,1))
 if r!=2 and relative>7.0: along_route=minf(along_route,route_clearance(x,d,2))
 return minf(along_route,absf(x-connection_x(d))-7.5)

func formation_at(d: float) -> int:
 var span := formation_span(d)
 return mini(3,int(section_value(int(span.z),50)*4.0))

func update_focus(pos: Vector3) -> void:
 var key := Vector2i(floori(pos.x/SIZE),floori(-pos.z/SIZE))
 if key==focus: return
 var previous := focus
 focus=key
 section_values.clear()
 # Retire only the strips that left the window, avoiding an 18k-key copy/scan.
 if absi(previous.x-key.x)>4 or absi(previous.y-key.y)>7:
  vertex_heights.clear()
 else:
  var old_min := Vector2i((previous.x-3)*16-4,(previous.y-2)*16-4)
  var old_max := Vector2i((previous.x+4)*16+4,(previous.y+7)*16+4)
  var new_min := Vector2i((key.x-3)*16-4,(key.y-2)*16-4)
  var new_max := Vector2i((key.x+4)*16+4,(key.y+7)*16+4)
  for row in range(old_min.y,old_max.y+1):
   for col in range(old_min.x,mini(old_max.x+1,new_min.x)): vertex_heights.erase(Vector2i(col,row))
   for col in range(maxi(old_min.x,new_max.x+1),old_max.x+1): vertex_heights.erase(Vector2i(col,row))
  for col in range(maxi(old_min.x,new_min.x),mini(old_max.x,new_max.x)+1):
   for row in range(old_min.y,mini(old_max.y+1,new_min.y)): vertex_heights.erase(Vector2i(col,row))
   for row in range(maxi(old_min.y,new_max.y+1),old_max.y+1): vertex_heights.erase(Vector2i(col,row))
 var region := floori(float(key.y)*SIZE/1024.0)
 for region_key: int in formation_regions.keys():
  if absi(region_key-region)>2: formation_regions.erase(region_key)
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
 if building or pending.is_empty() or last_generation_frame==Engine.get_process_frames(): return
 last_generation_frame=Engine.get_process_frames()
 building=true
 build_chunk(pending.pop_front(),true)

func generation_checkpoint(context: Dictionary) -> bool:
 var now := Time.get_ticks_usec()
 var spent: int=now-int(context.started)
 if spent<4000: return true
 context.work=int(context.work)+spent
 context.maximum=maxi(int(context.maximum),spent)
 generation_slice_ms=float(context.maximum)/1000.0
 await get_tree().process_frame
 if int(context.epoch)!=generation_epoch: return false
 var key: Vector2i=context.key
 if key.x<focus.x-3 or key.x>focus.x+3 or key.y<focus.y-2 or key.y>focus.y+6:
  if is_instance_valid(active_chunk): active_chunk.queue_free()
  active_chunk=null
  building=false
  last_generation_frame=Engine.get_process_frames()
  return false
 context.started=Time.get_ticks_usec()
 last_generation_frame=Engine.get_process_frames()
 return true

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

func build_chunk(key: Vector2i, sliced := false) -> void:
 if chunks.has(key):
  if sliced: building=false
  return
 var context := {"epoch":generation_epoch,"key":key,"started":Time.get_ticks_usec(),"work":0,"maximum":0}
 var root := Node3D.new()
 root.name="Section_%d_%d"%[key.x,key.y]
 add_child(root)
 if sliced: active_chunk=root
 var x0 := float(key.x)*SIZE
 var d0 := float(key.y)*SIZE
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for zi in 16:
  if sliced and not await generation_checkpoint(context): return
  for xi in 16:
   var x := x0+float(xi)*STEP
   var d := d0+float(zi)*STEP
   var a := Vector3(x,grid_height(key.x*16+xi,key.y*16+zi),-d)
   var b := Vector3(x+STEP,grid_height(key.x*16+xi+1,key.y*16+zi),-d)
   var c := Vector3(x,grid_height(key.x*16+xi,key.y*16+zi+1),-d-STEP)
   var e := Vector3(x+STEP,grid_height(key.x*16+xi+1,key.y*16+zi+1),-d-STEP)
   for p in [a,c,b,b,c,e]:
    var px := p.x as float
    var pd := -p.z as float
    var dx := (grid_height(roundi(px/STEP)+1,roundi(pd/STEP))-grid_height(roundi(px/STEP)-1,roundi(pd/STEP)))/(STEP*2.0)
    var dz := (grid_height(roundi(px/STEP),roundi(pd/STEP)-1)-grid_height(roundi(px/STEP),roundi(pd/STEP)+1))/(STEP*2.0)
    st.set_normal(Vector3(-dx,1,-dz).normalized())
    st.add_vertex(p)
 var land := MeshInstance3D.new()
 st.set_material(land_material)
 land.mesh=st.commit()
 root.add_child(land)
 # Water follows the same visible triangles as the banks. Narrow wet channels and
 # small embedded gravel replace a constant-width elevated ribbon.
 var ws := SurfaceTool.new()
 ws.begin(Mesh.PRIMITIVE_TRIANGLES)
 var has_water := false
 for zi in 32:
  if sliced and not await generation_checkpoint(context): return
  var da := d0+float(zi)*2.0
  var db := da+2.0
  var cx := channel_x(da)
  if floori(cx/SIZE)!=key.x: continue
  has_water=true
  var cx2 := channel_x(db)
  var wa := stream_width(da)
  var wb := stream_width(db)
  var fall := clampf((height_at(cx,da)-height_at(cx2,db))/2.0,0.0,1.0)
  for strip in 2:
   var ua := float(strip)-1.0
   var ub := ua+1.0
   var ax := cx+wa*ua
   var bx := cx+wa*ub
   var ex := cx2+wb*ub
   var cxx := cx2+wb*ua
   var a := Vector3(ax,height_at(ax,da)+0.075,-da)
   var b := Vector3(bx,height_at(bx,da)+0.075,-da)
   var c := Vector3(cxx,height_at(cxx,db)+0.075,-db)
   var e := Vector3(ex,height_at(ex,db)+0.075,-db)
   var vertices := [a,c,b,b,c,e]
   var coordinates := [Vector2((ua+1.0)*0.5,da),Vector2((ua+1.0)*0.5,db),Vector2((ub+1.0)*0.5,da),Vector2((ub+1.0)*0.5,da),Vector2((ua+1.0)*0.5,db),Vector2((ub+1.0)*0.5,db)]
   for vi in 6:
    ws.set_uv(coordinates[vi])
    ws.set_color(Color(fall,1,1,1))
    ws.add_vertex(vertices[vi])
 if has_water:
  var water := MeshInstance3D.new()
  water.mesh=Geometry.finish(ws,water_material)
  root.add_child(water)
 var rng := RandomNumberGenerator.new()
 rng.seed=hash("%d:%d:%d"%[mountain_seed,key.x,key.y])
 var families: Array=[]
 for i in 3:
  var transforms: Array[Transform3D]=[]
  families.append(transforms)
 var rocks: Array[Transform3D]=[]
 var chips: Array[Transform3D]=[]
 var ferns: Array[Transform3D]=[]
 var grass: Array[Transform3D]=[]
 var obstacles: Array[Dictionary]=[]
 var timber := SurfaceTool.new()
 timber.begin(Mesh.PRIMITIVE_TRIANGLES)
 var wood_count := 0
 for zi in 8:
  for xi in 8:
   if sliced and not await generation_checkpoint(context): return
   var x := x0+(float(xi)+rng.randf_range(0.10,0.90))*8.0
   var d := d0+(float(zi)+rng.randf_range(0.10,0.90))*8.0
   var r := route(x,d)
   var formation := formation_at(d)
   var span := formation_span(d)
   var stage := formation_progress(d)
   var progression := smoothstep(180.0,2600.0,maxf(0.0,d))
   var density := [0.10,0.28+progression*0.09,0.64+progression*0.18][r] as float
   var clump := 0.5+0.5*sin(x*0.075+d*0.041+section_value(int(span.z),51)*TAU)
   if formation==0: density*=lerpf(0.65,1.35,clump)
   elif formation==1: density*=0.63
   elif formation==2: density*=0.45
   # Each formation opens up to reveal its next combination, then provides a quiet apron.
   var challenge := smoothstep(0.12,0.29,stage)*(1.0-smoothstep(0.68,0.87,stage))
   density*=lerpf(0.40,1.0,challenge)
   density=minf(density,[0.12,0.44,0.91][r])
   var opening := d<100.0 and d> -24.0 and absf(x)<115.0
   if opening: continue
   var choice := rng.randf()
   var clear := clearance(x,d)
   var object_id := "%s_%d"%[key,zi*8+xi]
   if choice<density and clear>3.0:
    var family := 2 if r==0 else rng.randi_range(0,2)
    if r==2 and formation==0 and rng.randf()<0.55: family=0
    var variant: Dictionary=tree_variants[family]
    var scale_t := rng.randf_range(0.82,1.24)
    var pos := Vector3(x,height_at(x,d)-0.25,-d)
    var basis_t := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_t)
    var segments: Array[Dictionary]=[]
    var safe := true
    var part_index := 0
    for part: Dictionary in variant.segments:
     var a: Vector3=pos+basis_t*part.a
     var b: Vector3=pos+basis_t*part.b
     var r0: float=float(part.r0)*scale_t
     var r1: float=float(part.r1)*scale_t
     if not segment_clear(a,b,maxf(r0,r1),part_index>=8):
      safe=false
      break
     part_index+=1
     segments.append({"kind":"wood","pos":a,"end":b,"radius":r0*0.92,"radius_end":r1*0.92,"id":object_id+"T%d"%segments.size(),"pass_id":object_id+"T"})
    if not safe: continue
    families[family].append(Transform3D(basis_t,pos))
    obstacles.append_array(segments)
    # Roots settle independently on both uphill and downhill ground; they never float
    # as an unadjusted tree foot would on this slope.
    for root_i in 4:
     var angle := rng.randf()*TAU
     var reach := rng.randf_range(2.9,4.6)*scale_t
     var tip := pos+Vector3(cos(angle)*reach,0,sin(angle)*reach)
     tip.y=height_at(tip.x,-tip.z)+0.05
     var base := pos+Vector3(0,rng.randf_range(0.7,1.5)*scale_t,0)
     var knee := base.lerp(tip,0.45)
     knee.y=height_at(knee.x,-knee.z)+0.32*scale_t
     var thick := float(variant.radius)*0.29*scale_t
     if segment_clear(base,knee,thick) and segment_clear(knee,tip,thick*0.60):
      add_wood(timber,obstacles,base,knee,thick,thick*0.60,object_id+"A%d"%root_i,object_id+"T")
      add_wood(timber,obstacles,knee,tip,thick*0.60,0.04,object_id+"B%d"%root_i,object_id+"T")
      wood_count+=2
   elif choice<density+(0.40 if formation==1 else 0.16) and clear>3.0:
    var s := rng.randf_range(1.8,4.3) if r==2 else rng.randf_range(0.65,1.5)
    place_rock(rocks,obstacles,x,d,Vector3(s,s*0.8,s*1.1),rng.randf()*TAU,s*0.16,object_id+"R")
 # Put substantial outcrops beside visible openings, rather than depending on random
 # scatter to happen near the camera. Jittered owners and alternating shoulders keep
 # the sequence varied; each individual hull still respects every reserved passage.
 for band in range(floori(d0/32.0),floori((d0+SIZE)/32.0)):
  var d := float(band)*32.0+7.0+section_value(band,82)*19.0
  var centers := passage_centers(d,2)
  var formation := formation_at(d)
  var activity := formation_progress(d)
  for passage in 2:
   if sliced and not await generation_checkpoint(context): return
   var chance := 0.84 if formation==1 else 0.64
   if activity>0.83: chance*=0.60
   if section_value(band,83+passage)>chance: continue
   var center := centers.x if passage==0 else centers.y
   var side := -1.0 if passage==0 else 1.0
   if section_value(band,85+passage)>0.58: side=-side
   var width := 4.7+section_blend(d,32)
   var span_x := lerpf(3.0,4.2,section_value(band,87+passage))
   var x := center+side*(width+maxf(span_x,5.0)*1.18+2.6)
   if floori(x/SIZE)!=key.x or d<100.0: continue
   for piece in 5:
    if sliced and not await generation_checkpoint(context): return
    var pd := d+(float(piece)-2.0)*6.0
    var piece_centers := passage_centers(pd,2)
    var piece_center := piece_centers.x if passage==0 else piece_centers.y
    var piece_width := 4.7+section_blend(pd,32)
    var px := piece_center+side*(piece_width+maxf(span_x,5.0)*1.18+2.6+float(piece%2)*0.45)
    var height_r := lerpf(2.3,3.9,section_value(band,90+piece+passage*5))
    var scales := Vector3(span_x,height_r,lerpf(4.0,5.0,section_value(band,112+piece+passage*5)))
    place_rock(rocks,obstacles,px,pd,scales,side*0.13,0.55,"%sQ%d_%d_%d"%[key,band,passage,piece])
   if formation==3 or section_value(band,97+passage)<0.35:
    var a := Vector3(x+side*0.6,0,-d-6.5)
    var b := Vector3(x+side*1.4,0,-d+3.5)
    a.y=height_at(a.x,-a.z)+0.38
    b.y=height_at(b.x,-b.z)+0.30
    if segment_clear(a,b,0.58):
     add_wood(timber,obstacles,a,b,0.58,0.30,"%sJ%d_%d"%[key,band,passage])
     wood_count+=1
 # Ledges follow a loose contour between the principal woodland passages. Their
 # pieces have individual visible collision hulls and remain partly embedded.
 for zi in 4:
  for xi in 4:
   if sliced and not await generation_checkpoint(context): return
   var x := x0+(float(xi)+rng.randf_range(0.20,0.80))*16.0
   var d := d0+(float(zi)+rng.randf_range(0.20,0.80))*16.0
   if route(x,d)!=2 or d<100.0: continue
   var formation := formation_at(d)
   var stage := formation_progress(d)
   if stage<0.19 or stage>0.78: continue
   if formation==1 and rng.randf()<0.48:
    var angle := rng.randf_range(-0.40,0.40)
    var direction := Vector2(cos(angle),sin(angle))
    for piece in 3:
     var offset := (float(piece)-1.0)*3.4
     var px := x+direction.x*offset
     var pd := d+direction.y*offset
     var size_r := rng.randf_range(2.5,4.3)
     place_rock(rocks,obstacles,px,pd,Vector3(size_r*1.35,size_r*0.78,size_r*0.66),-angle,size_r*0.38,"%sL%d_%d_%d"%[key,zi,xi,piece])
   elif (formation==3 or formation==0) and rng.randf()<(0.42 if formation==3 else 0.16):
    var angle := rng.randf_range(-0.7,0.7)
    var reach := rng.randf_range(3.8,6.8)
    var radius := rng.randf_range(0.38,0.65)
    var a := Vector3(x-cos(angle)*reach,0,-d-sin(angle)*reach)
    var b := Vector3(x+cos(angle)*reach,0,-d+sin(angle)*reach)
    a.y=height_at(a.x,-a.z)+radius*0.55
    b.y=height_at(b.x,-b.z)+radius*0.55
    var middle := a.lerp(b,0.5)
    middle.y=maxf(middle.y,height_at(middle.x,-middle.z)+radius*0.8)
    if segment_clear(a,middle,radius) and segment_clear(middle,b,radius):
     add_wood(timber,obstacles,a,middle,radius,radius*0.8,"%sF%d_%dA"%[key,zi,xi],"%sF%d_%d"%[key,zi,xi])
     add_wood(timber,obstacles,middle,b,radius*0.8,radius*0.55,"%sF%d_%dB"%[key,zi,xi],"%sF%d_%d"%[key,zi,xi])
     wood_count+=2
     var splinter := middle+Vector3(0.4,2.2,0.7)
     if segment_clear(middle,splinter,0.16):
      add_wood(timber,obstacles,middle,splinter,0.16,0.025,"%sF%d_%dC"%[key,zi,xi],"%sF%d_%d"%[key,zi,xi])
      wood_count+=1
 # Two irregular gravel margins frame shallow pockets and interrupt the wet edge.
 # Stream gravel is no taller than the ground collision margin; substantial channel
 # stones use the same reserved-aperture check and collider as woodland rocks.
 for i in 32:
  if sliced and not await generation_checkpoint(context): return
  var d := d0+float(i)*2.0+rng.randf()*1.8
  var cx := channel_x(d)
  for side_sign in [-1.0,1.0]:
   for bank_row in 2:
    var offset := rng.randf_range(-0.22,0.18) if bank_row==0 else rng.randf_range(0.60,1.60)
    var x: float=cx+side_sign*(stream_width(d)+offset)
    if floori(x/SIZE)!=key.x: continue
    var size_c := rng.randf_range(0.34,0.72) if bank_row==0 else rng.randf_range(0.42,0.88)
    var scales := Vector3(size_c,size_c*0.13,size_c*rng.randf_range(0.70,1.20))
    chips.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU)*Basis.from_scale(scales),Vector3(x,height_at(x,d)-0.020,-d)))
  if i%7==0 and floori(cx/SIZE)==key.x:
   var size_r := rng.randf_range(0.35,0.65)
   place_rock(rocks,obstacles,cx,d,Vector3(size_r,size_r*0.48,size_r*1.2),rng.randf()*TAU,0.06,"%sS%d"%[key,i])
 # Ground cover grows in patches at rock/tree feet; exposed duff breaks up the carpet.
 for i in 230:
  if sliced and i%24==0 and not await generation_checkpoint(context): return
  var x := x0+rng.randf()*SIZE
  var d := d0+rng.randf()*SIZE
  var relative := absf(x-channel_x(d))
  if relative<stream_width(d)+1.0: continue
  var r := route(x,d)
  var patch := 0.5+0.5*sin(x*0.31+d*0.14+phase)*sin(d*0.22-x*0.11)
  if r==2 and patch<0.43: continue
  var pos := Vector3(x,height_at(x,d),-d)
  var s := rng.randf_range(0.45,1.12)
  var t := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*s),pos)
  if r==2: ferns.append(t)
  else: grass.append(t)
  if r==2 and i%3==0:
   var size_c := rng.randf_range(0.30,0.95)
   chips.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(size_c,size_c*0.15,size_c)),pos-Vector3(0,0.04,0)))
 for i in 3:
  if sliced and not await generation_checkpoint(context): return
  instance_batch(root,tree_variants[i].trunk,families[i])
  instance_batch(root,tree_variants[i].crown,families[i],true,0,140)
  instance_batch(root,tree_variants[i].distant,families[i],false,140,360)
 if wood_count>0:
  var wood := MeshInstance3D.new()
  wood.mesh=Geometry.finish(timber,wood_material)
  root.add_child(wood)
 instance_batch(root,rock_mesh,rocks)
 instance_batch(root,rock_mesh,chips,false,0,100)
 instance_batch(root,fern_mesh,ferns,false,0,105)
 instance_batch(root,grass_mesh,grass,false,0,110)
 # Cells store references to existing obstacle dictionaries, not duplicate hulls.
 # The expanded bounds include close-pass scoring and the maximum per-tick sweep.
 var collision_bins: Dictionary={}
 for obstacle_i in obstacles.size():
  if sliced and obstacle_i%16==0 and not await generation_checkpoint(context): return
  var obstacle: Dictionary=obstacles[obstacle_i]
  var a: Vector3=obstacle.pos
  var b: Vector3=obstacle.get("end",a)
  var padding := maxf(float(obstacle.radius),float(obstacle.get("radius_end",0)))+3.0
  var minimum := collision_cell(Vector3(minf(a.x,b.x),minf(a.y,b.y),minf(a.z,b.z))-Vector3.ONE*padding)
  var maximum := collision_cell(Vector3(maxf(a.x,b.x),maxf(a.y,b.y),maxf(a.z,b.z))+Vector3.ONE*padding)
  for cx in range(minimum.x,maximum.x+1):
   for cy in range(minimum.y,maximum.y+1):
    for cz in range(minimum.z,maximum.z+1):
     var cell := Vector3i(cx,cy,cz)
     if not collision_bins.has(cell):
      var entries: Array[Dictionary]=[]
      collision_bins[cell]=entries
     collision_bins[cell].append(obstacle)
 if key.x>=focus.x-3 and key.x<=focus.x+3 and key.y>=focus.y-2 and key.y<=focus.y+6:
  chunks[key]={"node":root,"obstacles":obstacles,"collision_bins":collision_bins}
  generated_count+=1
 else:
  root.queue_free()
 var last_work := Time.get_ticks_usec()-int(context.started)
 generation_ms=float(int(context.work)+last_work)/1000.0
 generation_slice_ms=float(maxi(int(context.maximum),last_work))/1000.0
 if sliced:
  last_generation_frame=Engine.get_process_frames()
  active_chunk=null
  building=false

func segment_clear(a: Vector3, b: Vector3, radius: float, low_volume_only := false) -> bool:
 var horizontal := Vector2(a.x-b.x,a.z-b.z).length()
 var samples := maxi(1,ceili(horizontal/1.5))
 # The extra 1.2m includes body clearance and the maximum path drift between samples.
 for i in range(samples+1):
  var p := a.lerp(b,float(i)/float(samples))
  if low_volume_only and p.y-radius>height_at(p.x,-p.z)+8.8: continue
  if clearance(p.x,-p.z)<radius+1.2: return false
 return true

func disc_clear(x: float, d: float, radius: float) -> bool:
 var samples := maxi(2,ceili(radius*2.0/1.5))
 for i in range(samples+1):
  var pd := d-radius+radius*2.0*float(i)/float(samples)
  if clearance(x,pd)<radius+1.2: return false
 return true

func add_wood(st: SurfaceTool, obstacles: Array[Dictionary], a: Vector3, b: Vector3, r0: float, r1: float, id: String, pass_id := "") -> void:
 Geometry.branch(st,a,b,r0,r1,Color.WHITE,9)
 obstacles.append({"kind":"wood","pos":a,"end":b,"radius":r0*0.92,"radius_end":r1*0.92,"id":id,"pass_id":id if pass_id.is_empty() else pass_id})

func place_rock(transforms: Array[Transform3D], obstacles: Array[Dictionary], x: float, d: float, scale_r: Vector3, angle: float, bury: float, id: String) -> bool:
 var footprint := maxf(scale_r.x,scale_r.z)*1.18
 if not disc_clear(x,d,footprint): return false
 var dx := (height_at(x+2,d)-height_at(x-2,d))/4.0
 var dd := (height_at(x,d+2)-height_at(x,d-2))/4.0
 var ground_normal := Vector3(-dx,1,dd).normalized()
 var rotation := Basis(Quaternion(Vector3.UP,ground_normal))*Basis(Vector3.UP,angle)
 var pos := Vector3(x,height_at(x,d),-d)-ground_normal*bury
 transforms.append(Transform3D(rotation*Basis.from_scale(scale_r),pos))
 var extents := Vector3(scale_r.x*0.90,scale_r.y*0.61,scale_r.z*0.90)
 obstacles.append({"kind":"rock","pos":pos+rotation*Vector3(0,scale_r.y*0.60,0),"radius":maxf(extents.x,extents.z),"extents":extents,"inverse_rotation":rotation.inverse(),"height":scale_r.y*1.2,"id":id})
 return true

func collision_cell(pos: Vector3) -> Vector3i:
 return Vector3i(floori(pos.x/COLLISION_CELL),floori(pos.y/COLLISION_CELL),floori(pos.z/COLLISION_CELL))

func obstacles_near(pos: Vector3) -> Array[Dictionary]:
 var out: Array[Dictionary]=[]
 var key := Vector2i(floori(pos.x/SIZE),floori(-pos.z/SIZE))
 var cell := collision_cell(pos)
 for dz in range(-1,2):
  for dx in range(-1,2):
   var k := key+Vector2i(dx,dz)
   if not chunks.has(k): continue
   var bins: Dictionary=chunks[k].collision_bins
   if bins.has(cell): out.append_array(bins[cell])
 # Every obstacle has one owning chunk and is inserted once per cell, so this
 # single-cell query cannot duplicate a segment at chunk or cell boundaries.
 return out
