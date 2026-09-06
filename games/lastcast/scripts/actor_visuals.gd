extends Node3D
## Authored procedural sailor: shaped cloth/anatomy meshes and endpoint-driven limbs.
## Every surface is generated locally. The hand targets own rod/reel/tiller contact.
var body: Node3D
var head: Node3D
var rod: Node3D
var rod_tip: Node3D
var reel_crank: Node3D
var rod_segments: Array[MeshInstance3D] = []
var arms: Array[Dictionary] = []
var legs: Array[Dictionary] = []
var eyes: Array[Node3D] = []
var brows: Array[Node3D] = []
var mats: Dictionary = {}
var reel_angle := 0.0
var left_hand_position := Vector3.ZERO
var tiller: Node3D
var tiller_grip: Node3D

func build() -> void:
	name = "MaraSailor"
	var cloth := material("oilskin", Color("6b512b"))
	var seam := material("stitch", Color("9b7e4d"))
	var shadow := material("fold", Color("655334"))
	var navy := material("trousers", Color("344b55"))
	var skin := material("skin", Color("cb956f"))
	var dark := material("hair", Color("342d29"))
	var cream := material("shirt", Color("dcd5bd"))
	body = group(self, Vector3(0,.91,0))
	# Closed ring topology shapes hips, waist, ribcage, shoulder slope and collar.
	loft(body, [Vector4(-.07,.20,.16,0),Vector4(0,.23,.18,0),Vector4(.13,.225,.175,0),Vector4(.28,.245,.19,0),Vector4(.43,.275,.18,-.015),Vector4(.50,.23,.155,-.01),Vector4(.56,.115,.105,0)], cloth, 24, .006)
	loft(body,[Vector4(.50,.10,.095,.005),Vector4(.58,.085,.077,.015),Vector4(.65,.075,.07,.012)],skin,20)
	# Open front, storm flap, sloped pockets, sewn back yoke and rolled collar.
	panel(body,[Vector3(-.045,.44,.172),Vector3(.045,.44,.172),Vector3(.055,.525,.123),Vector3(-.055,.525,.123)],cream)
	tube(body,[Vector3(.02,-.015,.183),Vector3(.025,.24,.196),Vector3(.028,.48,.165)],.012,shadow)
	for side in [-1,1]:
		panel(body,[Vector3(side*.055,.48,.169),Vector3(side*.115,.54,.07),Vector3(side*.14,.40,.175)],seam)
		panel(body,[Vector3(side*.08,.12,.177),Vector3(side*.20,.115,.10),Vector3(side*.205,.22,.105),Vector3(side*.09,.225,.179)],cloth)
		tube(body,[Vector3(side*.082,.218,.187),Vector3(side*.2,.209,.119)],.008,seam)
		tube(body,[Vector3(side*.215,.01,.06),Vector3(side*.232,.22,.08),Vector3(side*.263,.40,.075)],.0055,seam)
		for i in 4:
			var y := .07+float(i)*.095
			bead(body,Vector3(.037,y,.193),Vector3(.009,.009,.006),material("brass",Color("baa05f")))
		tube(body,[Vector3(side*.04,.40,-.185),Vector3(side*.13,.415,-.18),Vector3(side*.22,.40,-.135)],.006,seam)
		# Creases emerge from elbows and the belt, rather than a noisy full surface.
		tube(body,[Vector3(side*.12,.02,.17),Vector3(side*.19,.065,.17),Vector3(side*.21,.10,.145)],.006,shadow)
	loft(body,[Vector4(-.08,.21,.167,0),Vector4(-.045,.224,.177,0)],shadow,24)
	head = group(body,Vector3(0,.66,.005))
	# A continuous jaw/cheek/brow/cranium, with a flatter readable face toward +Z.
	loft(head,[Vector4(-.055,.056,.075,.025),Vector4(-.025,.095,.092,.024),Vector4(.035,.127,.105,.018),Vector4(.115,.145,.123,.005),Vector4(.19,.139,.128,-.005),Vector4(.255,.118,.107,-.013),Vector4(.29,.060,.065,-.017),Vector4(.30,.005,.006,-.017)],skin,32)
	var lip := material("lip",Color("905a48"))
	var white := material("eye_white",Color("e8dbc1"))
	var iris := material("iris",Color("466764"))
	for side in [-1,1]:
		bead(head,Vector3(side*.139,.095,-.006),Vector3(.030,.047,.027),skin)
		bead(head,Vector3(side*.153,.093,.008),Vector3(.009,.026,.012),lip)
		var eye := group(head,Vector3(side*.059,.127,.110))
		bead(eye,Vector3.ZERO,Vector3(.029,.016,.012),white)
		bead(eye,Vector3(-side*.004,0,.012),Vector3(.012,.013,.005),iris)
		bead(eye,Vector3(-side*.004,0,.016),Vector3(.006,.009,.003),dark)
		bead(eye,Vector3(-side*.008,.005,.019),Vector3(.003,.003,.0015),white)
		eyes.append(eye)
		var brow := group(head,Vector3(side*.063,.165,.106))
		tube(brow,[Vector3(-.031,-side*.004,0),Vector3(0,.004,.007),Vector3(.029,side*.004,0)],.008,dark)
		brows.append(brow)
		panel(head,[Vector3(side*.028,.11,.117),Vector3(side*.036,.040,.132),Vector3(side*.014,.039,.151),Vector3(0,.075,.141)],skin)
		bead(head,Vector3(side*.015,.043,.151),Vector3(.020,.014,.018),skin)
		tube(head,[Vector3(side*.006,.019,.128),Vector3(side*.045,.018,.116),Vector3(side*.055,.024,.109)],.0045,lip)
	# Swept crown with tapered individual locks, not a cluster of spheres.
	loft(head,[Vector4(.17,.145,.133,-.022),Vector4(.24,.15,.13,-.027),Vector4(.30,.123,.111,-.025),Vector4(.34,.052,.061,-.02),Vector4(.35,.001,.002,-.02)],dark,24,.006)
	for i in 21:
		var angle := float(i)*2.399963
		var root := Vector3(sin(angle)*.11,.24+float(i%3)*.026,cos(angle)*.085-.022)
		var end := root+Vector3(sin(angle+.6)*.058,.065,cos(angle+.6)*.045)
		var lock := loft(head,[Vector4(0,.036,.025,0),Vector4(.55,.028,.020,.014),Vector4(1,.001,.001,.025)],dark,8)
		place_span(lock,root,end)
	for side in [-1,1]:
		# Shaped trouser segments have knee volume and tapered cuff, with boots below.
		var leg: Dictionary = {}
		leg.upper = loft(self,[Vector4(0,.115,.132,0),Vector4(.18,.122,.127,0),Vector4(.65,.099,.112,.005),Vector4(1,.085,.093,0)],navy,16,.003)
		leg.lower = loft(self,[Vector4(0,.09,.097,0),Vector4(.22,.096,.09,-.01),Vector4(.80,.070,.074,0),Vector4(1,.07,.075,0)],navy,16,.003)
		leg.boot = group(self,Vector3.ZERO)
		var leather := material("leather",Color("705340"))
		loft(leg.boot,[Vector4(0,.089,.157,.035),Vector4(.035,.096,.16,.035),Vector4(.08,.095,.148,.04),Vector4(.13,.079,.093,-.012),Vector4(.23,.071,.077,-.018)],leather,20)
		loft(leg.boot,[Vector4(-.008,.094,.164,.035),Vector4(.028,.098,.165,.035)],material("sole",Color("433d35")),20)
		for n in 3: tube(leg.boot,[Vector3(-.045,.14-float(n)*.014,.05+float(n)*.023),Vector3(.045,.14-float(n)*.014,.05+float(n)*.023)],.005,cream)
		legs.append(leg)
		var arm: Dictionary = {}
		arm.upper = loft(self,[Vector4(0,.112,.108,0),Vector4(.18,.117,.11,0),Vector4(.75,.086,.087,.008),Vector4(1,.084,.081,0)],cloth,16,.004)
		arm.lower = loft(self,[Vector4(0,.087,.082,0),Vector4(.25,.088,.082,0),Vector4(.83,.061,.063,0),Vector4(1,.063,.060,0)],cloth,16,.004)
		arm.cuff = loft(self,[Vector4(0,.068,.064,0),Vector4(1,.067,.063,0)],seam,16)
		arm.hand = _hand(self,skin)
		arms.append(arm)
	_batch_static(body)
	_batch_static(head)
	for arm in arms: _batch_static(arm.hand)
	_build_rod()

func _build_rod() -> void:
	rod = group(self,Vector3(.3,1.02,.32))
	var graphite := material("graphite",Color("405451"))
	var cork := material("cork",Color("a58a5e"))
	var metal := material("reel_metal",Color("6a7774"))
	for i in 18:
		var t := float(i+1)/18.0
		rod_segments.append(loft(rod,[Vector4(0,.016-t*.010,.016-t*.010,0),Vector4(1,.015-t*.010,.015-t*.010,0)],graphite,8))
	rod_tip = group(rod,Vector3.ZERO)
	loft(rod,[Vector4(-.16,.033,.033,0),Vector4(.015,.037,.037,0),Vector4(.14,.03,.03,0)],cork,16)
	tube(rod,[Vector3(-.028,.08,0),Vector3(-.095,.07,-.04)],.012,metal)
	bead(rod,Vector3(-.095,.07,-.04),Vector3(.055,.065,.065),metal)
	reel_crank = group(rod,Vector3(-.146,.07,-.04))
	tube(reel_crank,[Vector3.ZERO,Vector3(-.02,.06,0)],.009,metal)
	bead(reel_crank,Vector3(-.043,.06,0),Vector3(.027,.016,.016),cork)

func pose(dt: float, time: float, gait: float, speed: float, seated: bool, fishing: bool, waiting: bool, casting: float, tension: float, reeling: bool, landing: float, steer: float) -> void:
	var walking := clampf(speed/3.7,0,1)
	if tiller != null: tiller.rotation.y = -steer*.30
	body.position.y = .91 + sin(time*2.1)*.007 + absf(sin(gait))*.018*walking
	body.rotation = Vector3((-.035 if seated else 0.0) - tension*.10 if fishing else -speed*.012,sin(gait)*.055*walking, -sin(gait)*.035*walking)
	head.rotation = Vector3(.05+tension*.12 if fishing else -.035,sin(time*.55)*.08 if not fishing else -.04,sin(gait)*.015*walking)
	var blink := .10 if fmod(time,4.7)>.0 and fmod(time,4.7)<.12 else 1.0
	for eye in eyes: eye.scale.y = blink
	for i in brows.size(): brows[i].rotation.z = (1 if i==0 else -1)*tension*.17
	if reeling: reel_angle += dt*9.5
	reel_crank.rotation.x = reel_angle
	rod.visible = not seated
	var grip := Vector3(.31,1.10,.40) if fishing else Vector3(.32,.90,.06)
	var cast_pose := 0.0
	if waiting: cast_pose = -.70
	elif casting>=0: cast_pose = lerpf(-.70,.24,smoothstep(0.0,.35,casting))
	elif fishing: cast_pose = .12+tension*.18
	rod.position = grip + Vector3(0,sin(time*2.4)*.009,0)
	rod.rotation = Vector3(cast_pose,0,-.08 if not fishing else -.03)
	_bend_rod(tension if fishing else 0.0)
	for i in 2:
		var side := -1.0 if i==0 else 1.0
		var phase := gait+(PI if i==1 else 0.0)
		var hip := Vector3(side*.125,.91,0)
		# During stance the local foot moves back exactly at ground speed; swing lifts it.
		var step := fposmod(phase,TAU)
		var stride_blend := clampf(speed/.55,0.0,1.0)
		var stride := PI/9.6
		var foot_z := stride*(1.0-2.0*step/PI) if step<PI else stride*(-1.0+2.0*(step-PI)/PI)
		var foot := Vector3(side*.14,.01,foot_z*stride_blend)
		foot.y += (sin(step-PI)*.145 if step>=PI else 0.0)*stride_blend
		var pole := Vector3(side*.15,.4,.7)
		if seated:
			foot = Vector3(side*.20,.31,.54)
			pole = Vector3(side*.24,.72,.75)
		var knee := joint(hip,foot+Vector3.UP*.12,.405,.405,pole)
		place_span(legs[i].upper,hip,knee)
		place_span(legs[i].lower,knee,foot+Vector3.UP*.19)
		legs[i].boot.position=foot
		legs[i].boot.rotation.x = -sin(step-PI)*.25*stride_blend if step>=PI and not seated else 0.0
		legs[i].boot.rotation.y = side*.04
		var shoulder := body.transform * Vector3(side*.255,.44,-.005)
		var wrist := Vector3(side*.315,.81,.025-sin(phase)*.19*walking)
		if seated:
			wrist = Vector3(.32,1.00,-.40) if i==1 else Vector3(-.23,.82,.36)
			if i==1 and tiller_grip != null: wrist=to_local(tiller_grip.global_position)
		elif fishing or landing>=0:
			wrist = rod.transform*(Vector3(.020,.04,.005) if i==1 else reel_crank.position+Vector3(-.043,cos(reel_angle)*.06,sin(reel_angle)*.06))
			if landing>=0 and i==0:
				# Transfer from reel to a lifted jaw grip clear of coat and legs.
				wrist=wrist.lerp(Vector3(-.39,1.20,.37),smoothstep(0.0,.9,landing))
		elif i==1: wrist=rod.position+Vector3(.015,.01,0)
		var elbow_pole := Vector3(side*.40,.96,-.13) if not fishing and not seated else Vector3(side*.56,.98,.01)
		var elbow := joint(shoulder,wrist,.30,.30,elbow_pole)
		place_span(arms[i].upper,shoulder,elbow)
		place_span(arms[i].lower,elbow,wrist)
		place_span(arms[i].cuff,wrist.lerp(elbow,.10),wrist)
		arms[i].hand.position=wrist
		arms[i].hand.rotation = Vector3(.35 if fishing else -.18,side*.25,.1*side)
		if i==0: left_hand_position=wrist

func _bend_rod(tension: float) -> void:
	var previous := Vector3.ZERO
	for i in rod_segments.size():
		var t := float(i+1)/float(rod_segments.size())
		var point := Vector3(0,t*1.95-t*t*(.12+tension*.66),t*.63+t*t*(.25+tension*.83))
		place_span(rod_segments[i],previous,point)
		previous=point
	rod_tip.position=previous

func _hand(parent: Node3D, skin: Material) -> Node3D:
	var hand := group(parent,Vector3.ZERO)
	loft(hand,[Vector4(-.055,.036,.019,.003),Vector4(-.018,.043,.024,.003),Vector4(.038,.035,.025,0),Vector4(.06,.025,.02,0)],skin,16)
	for finger in 4:
		var x := -.027+float(finger)*.018
		var length := .051-absf(float(finger)-1.5)*.006
		tube(hand,[Vector3(x,-.03,.005),Vector3(x,-.03-length,.014),Vector3(x,-.04-length,.04),Vector3(x,-.027-length,.053)],.010,skin)
	tube(hand,[Vector3(.035,.018,.008),Vector3(.051,-.006,.036),Vector3(.030,-.024,.052)],.013,skin)
	return hand

static func joint(start: Vector3, end: Vector3, upper: float, lower: float, pole: Vector3) -> Vector3:
	var direction := (end-start).normalized()
	var length := clampf(start.distance_to(end),.01,upper+lower-.001)
	var along := (upper*upper-lower*lower+length*length)/(2*length)
	var outward := pole-start
	outward=(outward-direction*outward.dot(direction)).normalized()
	return start+direction*along+outward*sqrt(maxf(.001,upper*upper-along*along))

static func place_span(node: Node3D, a: Vector3, b: Vector3) -> void:
	var direction := (b-a).normalized()
	var ref := Vector3.FORWARD if absf(direction.dot(Vector3.UP))>.95 else Vector3.UP
	var x := ref.cross(direction).normalized()
	node.transform=Transform3D(Basis(x,direction*a.distance_to(b),x.cross(direction).normalized()),a)

static func group(parent: Node, at: Vector3) -> Node3D:
	var node := Node3D.new(); parent.add_child(node); node.position=at; return node

func material(key: String, color: Color) -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color; mat.roughness=.85; mat.metallic_specular=.20
	if key in ["oilskin","stitch","fold","hull","hull_inside"]:
		mat.roughness=.96;mat.metallic_specular=.06
	mat.vertex_color_use_as_albedo=true
	mats[key]=mat
	return mat

static func mesh(parent: Node3D, resource: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new();result.mesh=resource;result.material_override=mat
	parent.add_child(result);result.position=at;return result

static func loft(parent: Node3D, rings: Array, mat: Material, sides:=20, irregular:=0.0) -> MeshInstance3D:
	# Catmull profile sections soften authored shoulders, cheeks, cuffs and boat seats.
	var curved: Array=[]
	for i in rings.size()-1:
		var a: Vector4=rings[i];var b: Vector4=rings[i+1]
		var pre: Vector4=rings[maxi(0,i-1)];var post: Vector4=rings[mini(rings.size()-1,i+2)]
		for j in 3:
			var sample:=a.cubic_interpolate(b,pre,post,float(j)/3.0)
			sample.y=maxf(.0001,sample.y);sample.z=maxf(.0001,sample.z)
			curved.append(sample)
	curved.append(rings[-1]);rings=curved
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rings.size():
		var r: Vector4=rings[row]
		for j in sides+1:
			var angle:=float(j)/sides*TAU
			var wrinkle:=sin(angle*5.0+float(row)*1.4)*irregular
			st.set_uv(Vector2(float(j)/sides,float(row)/maxi(1,rings.size()-1)))
			st.set_color(Color.WHITE*(1.0+sin(angle*3.0+float(row))*.018))
			st.add_vertex(Vector3(cos(angle)*(r.y+wrinkle),r.x,sin(angle)*(r.z+wrinkle)+r.w))
	# Godot front faces wind clockwise when viewed from the outside.
	for row in rings.size()-1:
		for j in sides:
			var a:=row*(sides+1)+j;var b:=a+sides+1
			for index in [a,a+1,b,a+1,b+1,b]:st.add_index(index)
	for end in [0,rings.size()-1]:
		for j in range(1,sides-1):
			var offset: int=int(end)*(sides+1)
			for index in ([offset,offset+j+1,offset+j] if end==0 else [offset,offset+j,offset+j+1]):st.add_index(index)
	st.generate_normals()
	return mesh(parent,st.commit(),Vector3.ZERO,mat)

static func tube(parent: Node3D, points: Array, radius: float, mat: Material, sides:=8) -> MeshInstance3D:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size():
		var point: Vector3=points[i]
		var tangent: Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
		var ref:=Vector3.UP if absf(tangent.y)<.9 else Vector3.FORWARD
		var x:=ref.cross(tangent).normalized();var y:=tangent.cross(x).normalized()
		for j in sides+1:
			var angle:=float(j)/sides*TAU
			st.set_uv(Vector2(float(j)/sides,float(i)))
			st.set_color(Color.WHITE)
			st.add_vertex(point+(x*cos(angle)+y*sin(angle))*radius)
	for i in points.size()-1:
		for j in sides:
			var a:=i*(sides+1)+j;var b:=a+sides+1
			for index in [a,b,a+1,a+1,b,b+1]:st.add_index(index)
	st.generate_normals()
	return mesh(parent,st.commit(),Vector3.ZERO,mat)

static func panel(parent: Node3D, points: Array, mat: Material) -> MeshInstance3D:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in range(1,points.size()-1):
		for p in [points[0],points[i],points[i+1],points[0],points[i+1],points[i]]:
			st.set_color(Color.WHITE);st.set_uv(Vector2(p.x,p.y+p.z));st.add_vertex(p)
	st.generate_normals()
	return mesh(parent,st.commit(),Vector3.ZERO,mat)

static func bead(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var rows: Array=[]
	for i in 13:
		var angle:=float(i)/12*PI
		rows.append(Vector4(-cos(angle)*size.y,maxf(.0001,sin(angle)*size.x),maxf(.0001,sin(angle)*size.z),0))
	var result:=loft(parent,rows,mat,16);result.position=at;return result

func build_skiff(parent: Node3D) -> Node3D:
	var vessel:=group(parent,Vector3(3,.35,7));vessel.name="SunwardSkiff"
	var cream:=material("hull",Color("afa68a"))
	var inside:=material("hull_inside",Color("978e73"))
	var green:=material("rail",Color("52766c"))
	var wood:=material("cedar",Color("8b7150"))
	var dark:=material("timber",Color("665740"))
	var metal:=material("outboard",Color("4a535b"))
	# Smooth swept clinker shell: 33 stations, keel, belly, flared topsides and sheer.
	for inner in [false,true]:
		for side in [-1,1]:
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in 33:
				var u:=float(i)/32
				var z:=lerpf(-1.90,2.15,u)
				var width:=_hull_width(u)
				var sheer:=.47+pow(maxf(0,u-.55)/.45,2)*.19
				for j in 17:
					var v:=float(j)/16
					var flare:=sin(v*PI*.5)
					var x:=width*flare-(.055*flare if inner else 0.0)
					var y:=lerpf(-.33,sheer,pow(v,2.3))+(.045 if inner else 0.0)
					var strake:=.013*sin(v*PI*8.0)
					st.set_uv(Vector2(u*4,v*2))
					var shade:=1.0-(.04 if int(v*8)%2==0 else 0.0)+sin(u*19)*.013
					st.set_color(Color(shade,shade,shade))
					st.add_vertex(Vector3(side*(x+strake),y,z))
			for i in 32:
				for j in 16:
					var a:=i*17+j;var b:=a+17
					var indices: Array=[a,a+1,b,a+1,b+1,b]
					if (side==1)!=inner: indices.reverse()
					for index in indices:st.add_index(index)
			st.generate_normals();mesh(vessel,st.commit(),Vector3.ZERO,inside if inner else cream)
		for side in [-1,1]:
			var rail: Array=[]
			for i in 41:
				var u:=float(i)/40
				rail.append(Vector3(side*(_hull_width(u)-(.055 if inner else 0.0)),.49+pow(maxf(0,u-.55)/.45,2)*.19,lerpf(-1.90,2.15,u)))
			tube(vessel,rail,.038 if inner else .051,wood if inner else green,10)
	# A genuine fitted transom closes both shell faces beneath the motor.
	panel(vessel,[Vector3(-.72,.49,-1.9),Vector3(.72,.49,-1.9),Vector3(.47,-.24,-1.9),Vector3(-.47,-.24,-1.9)],cream)
	tube(vessel,[Vector3(-.72,.49,-1.91),Vector3(0,.49,-1.91),Vector3(.72,.49,-1.91)],.053,green)
	# Individual floorboards are clipped to the hull's curved plan, not square ends.
	for plank in 9:
		var x0:=float(plank-4)*.158-.071
		var x1:=x0+.143
		var points: Array=[]
		for i in 26:
			var u:=.065+float(i)/25*.87
			var w:=_hull_width(u)*.79
			if absf(x0)<w and absf(x1)<w:points.append(Vector3(0,-.10,lerpf(-1.9,2.15,u)))
		if points.size()<2:continue
		var z0:float=points[0].z;var z1:float=points[-1].z
		panel(vessel,[Vector3(x0,-.085,z0),Vector3(x1,-.085,z0),Vector3(x1,-.085,z1),Vector3(x0,-.085,z1)],wood)
	for rib in 8:
		var u:=.10+float(rib)*.10;var z:=lerpf(-1.9,2.15,u)
		var w:=_hull_width(u)-.09
		tube(vessel,[Vector3(-w,.43,z),Vector3(-w*.89,.12,z),Vector3(-w*.65,-.06,z),Vector3(0,-.10,z),Vector3(w*.65,-.06,z),Vector3(w*.89,.12,z),Vector3(w,.43,z)],.021,dark)
	for z in [-1.04,.68,1.35]:
		var w:=_hull_width((z+1.90)/4.05)-.12
		for slat in 3:
			var slab:=loft(vessel,[Vector4(0,w,.050,0),Vector4(.065,w,.050,0)],wood,24)
			slab.position=Vector3(0,.28,z+float(slat-1)*.095)
		# Underseat knees and two brass fixing heads.
		for side in [-1,1]:
			tube(vessel,[Vector3(side*w,.28,z),Vector3(side*w*.78,-.02,z)],.03,dark)
			bead(vessel,Vector3(side*w*.88,.35,z),Vector3(.015,.006,.015),metal)
	# Softly radiused outboard cowling, lower gearcase, mount and connected tiller.
	var motor:=group(vessel,Vector3(0,.29,-2.00));motor.name="Outboard"
	loft(motor,[Vector4(0,.18,.20,0),Vector4(.04,.215,.24,-.01),Vector4(.29,.20,.23,-.018),Vector4(.36,.16,.18,-.015)],metal,24)
	loft(motor,[Vector4(.07,.217,.242,-.01),Vector4(.092,.217,.242,-.01)],material("motor_band",Color("70797e")),24)
	panel(motor,[Vector3(-.115,.12,-.239),Vector3(.115,.12,-.239),Vector3(.115,.245,-.245),Vector3(-.115,.245,-.245)],material("motor_badge",Color("b9bdb6")))
	for i in 4:tube(motor,[Vector3(-.10+float(i)*.061,.30,-.194),Vector3(-.10+float(i)*.061,.34,-.175)],.006,dark)
	loft(motor,[Vector4(-.72,.065,.09,-.04),Vector4(-.32,.08,.12,0),Vector4(0,.075,.11,0)],metal,14)
	bead(motor,Vector3(0,-.66,-.09),Vector3(.10,.10,.17),metal)
	for side in [-1,1]:panel(motor,[Vector3(0,-.66,-.245),Vector3(side*.18,-.71,-.245),Vector3(side*.10,-.60,-.245)],metal)
	tiller=group(vessel,Vector3(.08,.55,-1.94))
	tube(tiller,[Vector3.ZERO,Vector3(.22,.05,.32),Vector3(.24,.05,.70)],.023,metal)
	tube(tiller,[Vector3(.24,.05,.56),Vector3(.24,.05,.76)],.037,dark)
	tiller_grip=group(tiller,Vector3(.24,.05,.64))
	# Working interior: slatted catch crate, leather handle, oars and bow painter.
	for layer in 4:
		var y:= -.035+float(layer)*.080
		for side in [-1,1]:
			tube(vessel,[Vector3(.32+side*.20,y,-.23),Vector3(.32+side*.20,y,.21)],.023,dark,4)
			tube(vessel,[Vector3(.12,y,-.01+side*.22),Vector3(.52,y,-.01+side*.22)],.023,wood,4)
	for side in [-1,1]:
		var oar: Array=[Vector3(side*.79,.52,-1.10),Vector3(side*.88,.55,.20),Vector3(side*.68,.64,1.32)]
		tube(vessel,oar,.027,wood)
		panel(vessel,[Vector3(side*.68-.065,.64,1.14),Vector3(side*.68+.065,.64,1.14),Vector3(side*.56+.095,.68,1.66),Vector3(side*.56-.095,.68,1.66)],wood)
		bead(vessel,Vector3(side*1.015,.20,-.61),Vector3(.10,.21,.10),cream)
		tube(vessel,[Vector3(side*.98,.45,-.61),Vector3(side*1.015,.31,-.61)],.012,dark)
	var rope: Array=[]
	for i in 150:
		var t:=float(i)/149;var angle:=t*TAU*4.2;var radius:=.075+t*.12
		rope.append(Vector3(-.32+sin(angle)*radius,-.03,1.12+cos(angle)*radius))
	tube(vessel,rope,.012,material("rope",Color("c0b48e")),6)
	_batch_static(vessel)
	_batch_static(motor)
	_batch_static(tiller)
	return vessel

static func _hull_width(u: float) -> float:
	# Cubic sections retain the broad transom and round belly, tapering into a stem.
	if u<.50:return .72+sin(u/.50*PI*.5)*.235
	var t:=(u-.50)/.50
	return .955*pow(maxf(0,1.0-t*t),.70)+.013

static func _batch_static(parent: Node3D) -> void:
	# Keep joints/contact targets separate; combine only immobile sibling geometry.
	var batches: Dictionary={}
	for child in parent.get_children():
		if child is not MeshInstance3D: continue
		var mat: Material=child.material_override
		if not batches.has(mat): batches[mat]=[]
		batches[mat].append(child)
	for mat: Material in batches:
		var nodes: Array=batches[mat]
		if nodes.size()<2: continue
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node: MeshInstance3D in nodes:
			st.append_from(node.mesh,0,node.transform)
			parent.remove_child(node);node.queue_free()
		mesh(parent,st.commit(),Vector3.ZERO,mat)
