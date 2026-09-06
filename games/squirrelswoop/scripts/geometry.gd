class_name SwoopGeometry
extends RefCounted

# One shared set of meshes; chunks contain only instance transforms.
static func material(color: Color, vertex := false) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.vertex_color_use_as_albedo = vertex
 m.vertex_color_is_srgb = true
 m.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
 m.roughness = 0.91
 return m

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
 st.set_color(color)
 st.add_vertex(a)
 st.add_vertex(b)
 st.add_vertex(c)

static func branch(st: SurfaceTool, a: Vector3, b: Vector3, r1: float, r2: float, color: Color, sides := 7) -> void:
 var axis := (b-a).normalized()
 var u := axis.cross(Vector3.FORWARD).normalized()
 if u.length() < 0.1: u = Vector3.RIGHT
 var v := axis.cross(u).normalized()
 for j in sides:
  var t := TAU*float(j)/sides
  var t2 := TAU*float(j+1)/sides
  var n1 := u*cos(t)+v*sin(t)
  var n2 := u*cos(t2)+v*sin(t2)
  var shade := color*(0.85+0.15*float(j%3)/2.0)
  shade.a = 1.0
  var length := a.distance_to(b)
  var vertices := [a+n1*r1,b+n1*r2,b+n2*r2,a+n1*r1,b+n2*r2,a+n2*r1]
  var uv := [Vector2(t*r1,0),Vector2(t*r2,length),Vector2(t2*r2,length),Vector2(t*r1,0),Vector2(t2*r2,length),Vector2(t2*r1,0)]
  for k in 6:
   st.set_color(shade)
   st.set_uv(uv[k])
   st.add_vertex(vertices[k])
  tri(st,b,b+n2*r2,b+n1*r2,shade)

static func finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
 st.generate_normals()
 st.set_material(mat)
 return st.commit()

# A tree archetype owns both the visible wood and its collision segments.
# Roots are fitted to the actual ground by the mountain, never baked into a flat star.
static func tree_variant(index: int) -> Dictionary:
 var heights := [39.0,31.0,25.0]
 var radii := [1.55,1.04,0.68]
 var height: float = heights[index]
 var radius: float = radii[index]
 var segments: Array[Dictionary]=[]
 var points: Array[Vector3]=[]
 var rng := RandomNumberGenerator.new()
 rng.seed=740+index*193
 for i in 9:
  var t := float(i)/8.0
  points.append(Vector3(sin(t*2.8+float(index))*t*1.5,height*t,sin(t*3.5)*t*0.9))
 for i in 8:
  var t := float(i)/8.0
  var t2 := float(i+1)/8.0
  var r0 := radius*pow(1.0-t,0.88)+0.045
  var r1 := radius*pow(1.0-t2,0.88)+0.045
  if i==0: r0*=1.34
  segments.append({"a":points[i],"b":points[i+1],"r0":r0,"r1":r1})
 # Irregular, articulated lateral limbs: stout elbows taper into drooping tips.
 var limb_count := 13 if index==0 else 10
 for i in limb_count:
  var t := float(i)/float(limb_count)
  var h := lerpf(7.8 if index==0 else 9.8,height-2.0,t)
  var q := h/height*8.0
  var base := points[mini(7,int(q))].lerp(points[mini(8,int(q)+1)],fposmod(q,1.0))
  var angle := float(i)*2.399+float(index)*1.7+rng.randf_range(-0.3,0.3)
  var reach := lerpf(7.0 if index==0 else 5.4,1.2,t)*rng.randf_range(0.72,1.15)
  var direction := Vector3(cos(angle),0,sin(angle))
  var elbow := base+direction*reach*0.57+Vector3(0,0.25 if i%3==0 else -0.55,0)
  var tip := base+direction*reach+Vector3(0,0.65 if i%4==0 else -0.7,0)
  var thick := lerpf(0.34 if index==0 else 0.23,0.075,t)
  segments.append({"a":base,"b":elbow,"r0":thick,"r1":thick*0.54})
  segments.append({"a":elbow,"b":tip,"r0":thick*0.54,"r1":0.022})
  if i%3!=0:
   var twig := elbow+direction.rotated(Vector3.UP,0.52)*reach*0.49+Vector3(0,0.5,0)
   segments.append({"a":elbow,"b":twig,"r0":thick*0.33,"r1":0.015})
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for segment in segments:
  branch(st,segment.a,segment.b,segment.r0,segment.r1,Color.WHITE,12 if segment.r0>0.6 else 7)
 var mat := ShaderMaterial.new()
 mat.shader=preload("res://shaders/bark.gdshader")
 return {"trunk":finish(st,mat),"crown":crown(true,index),"distant":crown(false,index),"segments":segments,"height":height,"radius":radius*1.34}

static var pine_needles: Texture2D

# Authored by seeded strokes at startup: one shared image, no downloaded textures.
static func needle_stroke(picture: Image, a: Vector2, b: Vector2, radius: float, color: Color) -> void:
 var ab := b-a
 var length_squared := maxf(ab.length_squared(),0.001)
 var minimum := Vector2i(maxi(0,floori(minf(a.x,b.x)-radius-1)),maxi(0,floori(minf(a.y,b.y)-radius-1)))
 var maximum := Vector2i(mini(511,ceili(maxf(a.x,b.x)+radius+1)),mini(511,ceili(maxf(a.y,b.y)+radius+1)))
 for y in range(minimum.y,maximum.y+1):
  for x in range(minimum.x,maximum.x+1):
   var pixel := Vector2(float(x)+0.5,float(y)+0.5)
   var t := clampf((pixel-a).dot(ab)/length_squared,0,1)
   var coverage := clampf(radius*(1.0-t*0.48)+0.65-pixel.distance_to(a+ab*t),0,1)
   if coverage<0.03: continue
   var old := picture.get_pixel(x,y)
   var mixed := Color(old.r,old.g,old.b,1).lerp(color,coverage)
   mixed.a=maxf(old.a,coverage)
   picture.set_pixel(x,y,mixed)

static func pine_texture() -> Texture2D:
 if pine_needles!=null: return pine_needles
 var picture := Image.create(512,512,false,Image.FORMAT_RGBA8)
 picture.fill(Color(0.20,0.27,0.13,0))
 var rng := RandomNumberGenerator.new()
 rng.seed=8761
 var root := Vector2(256,482)
 var tip := Vector2(251,30)
 needle_stroke(picture,root,tip,2.6,Color(0.30,0.28,0.13))
 # Alternating irregular secondary twigs with separate fine paired needles.
 for row in 19:
  var t := float(row+1)/21.0
  var stem := root.lerp(tip,t)+Vector2(rng.randf_range(-4,4),0)
  for side_sign in [-1.0,1.0]:
   var reach := sin(t*PI*0.84)*165.0*(1.0-t*0.52)
   var twig_end := stem+Vector2(side_sign*reach,-45.0-rng.randf()*33.0)
   needle_stroke(picture,stem,twig_end,1.2,Color(0.26,0.33,0.15))
   var direction := (twig_end-stem).normalized()
   var across := Vector2(-direction.y,direction.x)
   for needle in 21:
    var q := float(needle)/21.0
    var origin := stem.lerp(twig_end,q)
    for needle_side in [-1.0,1.0]:
     var length := rng.randf_range(9.0,19.0)*(0.55+sin(q*PI)*0.45)
     var point: Vector2 = origin+direction*length*0.66+across*needle_side*length*0.74
     var shade := Color(0.27,0.36,0.17).lerp(Color(0.56,0.59,0.31),rng.randf())
     needle_stroke(picture,origin,point,rng.randf_range(0.85,1.55),shade)
 # The leading tuft breaks the last twig into a fine natural point.
 for i in 45:
  var origin := tip+Vector2(0,float(i)*1.35)
  var end := origin+Vector2(rng.randf_range(-19,19),-rng.randf_range(8,24))
  needle_stroke(picture,origin,end,1.0,Color(0.44,0.51,0.25))
 picture.generate_mipmaps()
 pine_needles=ImageTexture.create_from_image(picture)
 return pine_needles

static func bough_card(st: SurfaceTool, root: Vector3, tip: Vector3, side: Vector3, width: float, shade: Color, detailed: bool) -> void:
 var rows := 2 if detailed else 1
 for row in rows:
  var t0 := float(row)/float(rows)
  var t1 := float(row+1)/float(rows)
  for band in 2:
   var u0 := float(band)*0.5
   var u1 := float(band+1)*0.5
   var uv := [Vector2(u0,1-t0),Vector2(u0,1-t1),Vector2(u1,1-t0),Vector2(u1,1-t1)]
   var points: Array[Vector3]=[]
   for pair in [Vector2(u0,t0),Vector2(u0,t1),Vector2(u1,t0),Vector2(u1,t1)]:
    var point: Vector3 = root.lerp(tip,pair.y)+side*(pair.x-0.5)*width*2.0
    point.y+=sin(pair.y*PI)*0.24-absf(pair.x-0.5)*0.70
    points.append(point)
   for index in [0,2,1,2,3,1]:
    st.set_color(shade)
    st.set_uv(uv[index])
    st.add_vertex(points[index])

static func crown(detailed := true, variant := 0) -> ArrayMesh:
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rng := RandomNumberGenerator.new()
 rng.seed=42+variant*241
 var tiers := 11 if detailed else 7
 var arms := 6 if detailed else 4
 for tier in tiers:
  var fraction := float(tier)/float(tiers-1)
  var bottom: float = [10.0,9.0,7.0][variant]
  var canopy_top: float = [39.0,31.0,25.0][variant]
  var h := bottom+fraction*(canopy_top-bottom)
  var spread: float = [7.6,5.9,4.4][variant]
  var radius := spread*pow(1.0-fraction,0.72)+0.35
  for arm in arms:
   var angle := float(arm)*TAU/float(arms)+float(tier)*2.399+rng.randf_range(-0.26,0.26)
   var outward := Vector3(cos(angle),0,sin(angle))
   var side := Vector3(-sin(angle),0,cos(angle))
   var length := radius*rng.randf_range(0.80,1.13)
   var root := Vector3(sin(h/canopy_top*2.8+float(variant))*h/canopy_top*1.5,h+rng.randf_range(-0.85,0.85),sin(h/canopy_top*3.5)*h/canopy_top*0.9)
   var tip := root+outward*length+Vector3(0,-0.30-length*0.20,0)
   var tint := Color(0.70,0.78,0.64).lerp(Color(1.04,1.02,0.87),rng.randf())
   bough_card(st,root,tip,side,length*0.52+0.10,tint,detailed)
   # A second, angled spray gives needles depth from the trailing ground-level view.
   bough_card(st,root+outward*0.20,tip+Vector3(0,-0.48,0),side.rotated(outward,0.95),length*0.44,tint.darkened(0.09),detailed)
   # A compact opaque core is hidden inside the alpha sprays, never their silhouette.
   st.set_uv(Vector2(-1,-1))
   var core := root+outward*length*0.22
   var top := core+Vector3(0,0.28,0)
   var edge := side*length*0.10
   var end := root+outward*length*0.48+Vector3(0,-0.16,0)
   var dark := Color(0.06,0.095,0.036)
   tri(st,root,core-edge,top,dark)
   tri(st,root,top,core+edge,dark)
   tri(st,core-edge,end,top,dark)
   tri(st,top,end,core+edge,dark)
 var mat := ShaderMaterial.new()
 mat.shader=preload("res://shaders/foliage.gdshader")
 mat.set_shader_parameter("bough_texture",pine_texture())
 return finish(st,mat)

static func rock() -> ArrayMesh:
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rng := RandomNumberGenerator.new()
 rng.seed=782
 var rings: Array[PackedVector3Array] = []
 for r in 7:
  var ring := PackedVector3Array()
  var h := float(r)/6.0
  var rad: float = [0.46,0.90,1.0,0.98,0.90,0.74,0.30][r]
  for j in 13:
   var a := float(j)*TAU/13.0
   var jitter := rng.randf_range(0.88,1.12)
   ring.append(Vector3(cos(a)*rad*jitter,h*1.45-0.12,sin(a)*rad*jitter))
  rings.append(ring)
 for r in 6:
  for j in 13:
   var k := (j+1)%13
   var col := Color(0.30,0.33,0.28).lerp(Color(0.51,0.51,0.38),rng.randf())
   if r>=2: col=col.lerp(Color(0.29,0.36,0.105),0.75)
   tri(st,rings[r][j],rings[r+1][k],rings[r+1][j],col)
   tri(st,rings[r][j],rings[r][k],rings[r+1][k],col.darkened(0.05))
 for j in 13:
  var k := (j+1)%13
  tri(st,Vector3(0,1.33,0),rings[6][j],rings[6][k],Color(0.34,0.40,0.23))
  tri(st,Vector3(0,-0.12,0),rings[0][k],rings[0][j],Color(0.30,0.32,0.28))
 var mat := ShaderMaterial.new()
 mat.shader=preload("res://shaders/rock.gdshader")
 return finish(st,mat)

static func fern() -> ArrayMesh:
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for k in 7:
  var a := float(k)*2.399
  var dir := Vector3(cos(a),0,sin(a))
  var side := Vector3(-sin(a),0,cos(a))
  for leaf in 7:
   var t := float(leaf+1)/8.0
   var p := dir*t*1.4+Vector3(0,sin(t*PI)*0.8+0.1,0)
   var w := sin(t*PI)*0.32
   var col := Color(0.28,0.39,0.13).lightened(float(leaf)*0.025)
   tri(st,p-dir*0.19,p+side*w-dir*0.16,p+dir*0.18,col)
   tri(st,p-dir*0.19,p+dir*0.18,p-side*w-dir*0.16,col)
 var m := ShaderMaterial.new()
 m.shader=preload("res://shaders/groundcover.gdshader")
 return finish(st,m)

static func grass() -> ArrayMesh:
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for k in 8:
  var a := float(k)*2.399
  var p := Vector3(cos(a)*0.36,0,sin(a)*0.36)
  var side := Vector3(cos(a+1.0),0,sin(a+1.0))*0.065
  tri(st,p-side,p+Vector3(0.12,0.4+float(k%3)*0.18,0.08),p+side,Color(0.49,0.50,0.23))
 var m := material(Color.WHITE,true)
 m.cull_mode=BaseMaterial3D.CULL_DISABLED
 return finish(st,m)
