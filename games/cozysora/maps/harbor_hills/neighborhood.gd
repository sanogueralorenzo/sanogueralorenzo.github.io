extends RefCounted
## Original fictional houses, shopfronts, pocket gardens and street furniture.
var map
var g
var rng=RandomNumberGenerator.new()
var house_index=0
const WALLS=["c5bba0","bf8e77","8faca1","bcb4a8","acb5c2","d4bf8b","b8969b","90a4b1"]
const TRIMS=["ece0c6","dbd9c8","f0e7d3"]

func build(world,geometry) -> void:
	map=world;g=geometry;rng.seed=98213
	for block in range(2):
		for row in range(2):
			var z=[-87.0,-46.0,-17.0,31.0][block*2+row]
			for side in range(2):
				for col in range(4):
					var x=(-59 if side==0 else 28)+col*14
					_house(x,z,11.8,12.0,PI if row==0 else 0,block==0 and row==0,house_index)
					house_index+=1
		map.load_progress.emit("Opening neighborhood windows…",.34+block*.12)
		await map.get_tree().process_frame
	# Main-street corner stores and apartments bind all four blocks together.
	for z in [-68.0,7.0]:
		for side in [-1,1]:
			_house(-10 if side==-1 else 26,z,15,12,PI*.5 if side==-1 else -PI*.5,true,house_index);house_index+=1
	# Upper terraces overlook the gardens and connect into the turning plaza.
	for x in [30.0,44.0,58.0,72.0]:
		_house(x,80,11.6,13,PI,true if x==30 else false,house_index);house_index+=1
	for z in [61.0,78.0,95.0,115.0]:
		_house(116,z,12,12,-PI*.5,false,house_index);house_index+=1
	_courtyard_infill()
	_gardens_and_routes()
	_street_furniture()
	_waterfront()

func _local(origin:Vector3,yaw:float,p:Vector3) -> Vector3:
	return origin+Basis(Vector3.UP,yaw)*p

func _box(origin:Vector3,yaw:float,p:Vector3,size:Vector3,color:String,solid:bool=false,finish:String="plaster") -> void:
	g.box(_local(origin,yaw,p),size,color,solid,yaw,finish)

func _house(x:float,z:float,w:float,d:float,yaw:float,shop:bool,index:int) -> void:
	var front=Vector3(x,0,z)+Basis(Vector3.UP,yaw)*Vector3(0,0,d*.5+2.0)
	var y=map.height_at(front.x,front.z)+.2
	var origin=Vector3(x,y,z)
	var floors=3 if shop or index%4==0 else 2
	var h=floors*3.0+.5
	var wall=WALLS[index%WALLS.size()];var trim=TRIMS[index%3]
	# Foundations reach the lowest corner even when the front faces uphill.
	var foundation=2.4
	for dx in [-w*.5,w*.5]:
		for dz in [-d*.5,d*.5]:
			var corner=_local(origin,yaw,Vector3(dx,0,dz))
			foundation=maxf(foundation,y-map.height_at(corner.x,corner.z)+.2)
	_box(origin,yaw,Vector3(0,(h-foundation)*.5,0),Vector3(w,h+foundation,d),wall,true,"siding" if not shop else "plaster")
	_box(origin,yaw,Vector3(0,.0,d*.5+.015),Vector3(w,.65,.15),"807e71",false,"brick")
	_box(origin,yaw,Vector3(0,h+.13,0),Vector3(w+.38,.26,d+.38),trim)
	_box(origin,yaw,Vector3(0,h+.31,0),Vector3(w-.2,.14,d-.2),"565e61",false,"roof")
	# Walkable flat roofs, parapets, skylights, chimneys and a few rooftop terraces.
	_box(origin,yaw,Vector3(0,h+.26,0),Vector3(w,.18,d),"5f6260",true)
	for side in [-1,1]:_box(origin,yaw,Vector3(side*(w*.5-.1),h+.58,0),Vector3(.22,.65,d),wall,true)
	_box(origin,yaw,Vector3(0,h+.58,-d*.5+.1),Vector3(w,.65,.22),wall,true)
	_box(origin,yaw,Vector3(w*.23,h+.72,-d*.23),Vector3(1.5,.85,1.3),"768987")
	_box(origin,yaw,Vector3(w*.23,h+1.16,-d*.23),Vector3(1.65,.08,1.45),"aaa99a")
	_box(origin,yaw,Vector3(-w*.32,h+1.0,-d*.28),Vector3(.65,1.8,.72),"a07e69",false,"brick")
	_box(origin,yaw,Vector3(-w*.32,h+1.94,-d*.28),Vector3(.85,.18,.94),trim)
	# Different roof silhouettes and occupied terraces break the repeated row-house mass.
	if index%3==1:
		for side in [-1,1]:
			var rotation=(Basis(Vector3.UP,yaw)*Basis(Vector3.BACK,side*.27)).get_euler()
			g.add("box",_local(origin,yaw,Vector3(side*1.14,h+.72,d*.5-.7)),Vector3(2.5,.2,2.2),trim,rotation)
		_box(origin,yaw,Vector3(0,h+.57,d*.5-.7),Vector3(4.6,.8,1.9),wall)
	elif index%3==2:
		_box(origin,yaw,Vector3(-1,h+.46,1),Vector3(5,.14,4),"9c8c6c",false,"siding")
		_bench(_local(origin,yaw,Vector3(-1,h+.55,1)),yaw)
		for dx in [-3.2,1.2]:
			_box(origin,yaw,Vector3(dx,h+1.1,1),Vector3(.16,1.4,4.2),"879780")
		for j in range(3):_box(origin,yaw,Vector3(-1,h+2.45,-.5+j*1.5),Vector3(5,.13,.13),"b3b094")
		for dx in [-3.2,1.2]:
			for dz in [-1.1,3.1]:g.beam(_local(origin,yaw,Vector3(dx,h+.5,dz)),_local(origin,yaw,Vector3(dx,h+2.5,dz)),.055,"8f9277")
	for floor in range(1,floors):
		var wy=floor*3+1.45
		for col in [-1,0,1]:
			var wx=col*w*.29
			var bay=.6 if not shop and col!=0 else .12
			_box(origin,yaw,Vector3(wx,wy,d*.5+bay*.5),Vector3(2.65,2.25,bay+.15),trim)
			_box(origin,yaw,Vector3(wx,wy+.03,d*.5+bay+.09),Vector3(2.16,1.9,.07),"486269",false,"metal")
			for split in [-.7,0,.7]:_box(origin,yaw,Vector3(wx+split,wy+.04,d*.5+bay+.15),Vector3(.07,1.98,.06),trim)
			_box(origin,yaw,Vector3(wx,wy+.0,d*.5+bay+.16),Vector3(2.25,.07,.08),trim)
			_box(origin,yaw,Vector3(wx,wy-1.22,d*.5+bay*.5),Vector3(2.95,.18,bay+.5),trim)
			_box(origin,yaw,Vector3(wx,wy+1.23,d*.5+bay*.5),Vector3(2.95,.16,bay+.5),trim)
			# Warm curtains, unevenly opened shutters, and planted window ledges.
			if (index+col+floor)%3==0:
				_box(origin,yaw,Vector3(wx-.7,wy,d*.5+bay+.18),Vector3(.55,1.75,.025),"c9bb99")
			if (index+col)%3==0:
				_box(origin,yaw,Vector3(wx,wy-1.05,d*.5+bay+.28),Vector3(2,.27,.4),"867763")
				for leaf in range(5):g.add("leaf",_local(origin,yaw,Vector3(wx-.8+leaf*.4,wy-.83,d*.5+bay+.35)),Vector3(.47,.34,.48),"527653")
		# Continuous cornice and thin belt course prevent flat box façades.
		_box(origin,yaw,Vector3(0,floor*3-.07,d*.5+.13),Vector3(w+.16,.13,.32),trim)
	for side in [-1,1]:
		_box(origin,yaw,Vector3(side*(w*.5-.16),h*.5,d*.5+.05),Vector3(.22,h,.16),trim)
		for floor in range(floors):
			for rear in [-.28,.24]:
				_box(origin,yaw,Vector3(side*(w*.5+.025),floor*3+1.65,d*rear),Vector3(.08,1.55,1.18),"4d6266")
				for edge in [-.65,.65]:_box(origin,yaw,Vector3(side*(w*.5+.09),floor*3+1.65,d*rear+edge),Vector3(.08,1.75,.1),trim)
				for edge in [-.85,.85]:_box(origin,yaw,Vector3(side*(w*.5+.1),floor*3+1.65+edge,d*rear),Vector3(.12,.12,1.4),trim)
	_approach(origin,yaw,w,d,index)
	if shop:_shop(origin,yaw,w,d,index,trim)
	else:
		_box(origin,yaw,Vector3(-w*.23,1.15,d*.5+.1),Vector3(w*.43,2.2,.12),"7c8b88")
		for slat in range(8):_box(origin,yaw,Vector3(-w*.23,.28+slat*.25,d*.5+.19),Vector3(w*.43,.035,.04),trim)
		_box(origin,yaw,Vector3(w*.27,1.5,d*.5+.12),Vector3(1.4,2.8,.14),"425f5b")
		_box(origin,yaw,Vector3(w*.27,2.1,d*.5+.21),Vector3(.83,1.15,.05),"9caeaa")
		_box(origin,yaw,Vector3(w*.27,.16,d*.5+.52),Vector3(2.1,.3,.9),"a7a496",true)
		g.label(str(140+index*3),_local(origin,yaw,Vector3(w*.27,3.0,d*.5+.2)),.8,"4d5753",yaw,40)
	if shop and index%2==0:_fire_escape(origin,yaw,w,d,h)
	# Downpipes and rear service doors reward alley exploration.
	g.beam(_local(origin,yaw,Vector3(w*.45,.2,-d*.5-.12)),_local(origin,yaw,Vector3(w*.45,h,-d*.5-.12)),.055,"606b64")
	_box(origin,yaw,Vector3(0,1.25,-d*.5-.035),Vector3(1.3,2.5,.1),"6d8177")
	for floor in range(floors):
		for side in [-1,1]:
			var rear=Vector3(side*w*.28,floor*3+1.65,-d*.5-.07)
			_box(origin,yaw,rear,Vector3(1.7,1.8,.1),trim)
			_box(origin,yaw,rear+Vector3(0,0,-.08),Vector3(1.42,1.52,.07),"617e7c")
			_box(origin,yaw,rear+Vector3(0,0,-.14),Vector3(.07,1.52,.06),trim)
			_box(origin,yaw,rear+Vector3(0,0,-.14),Vector3(1.42,.07,.06),trim)
			if (index+floor)%3==0:
				_box(origin,yaw,rear+Vector3(0,-.88,-.15),Vector3(1.9,.28,.35),"9b8265")
				for j in range(3):g.add("leaf",_local(origin,yaw,rear+Vector3(-.6+j*.6,-.6,-.22)),Vector3(.6,.5,.5),"6f875e")
	for side in [-1,1]:
		for by in [1.5,4.6]:
			_box(origin,yaw,Vector3(side*(w*.5+.025),by,-d*.15),Vector3(.12,1.75,1.8),trim)
			_box(origin,yaw,Vector3(side*(w*.5+.1),by,-d*.15),Vector3(.04,1.48,1.5),"607e80")
			_box(origin,yaw,Vector3(side*(w*.5+.15),by,-d*.15),Vector3(.05,.06,1.5),trim)
			_box(origin,yaw,Vector3(side*(w*.5+.15),by,-d*.15),Vector3(.05,1.48,.07),trim)
	if index%4==1:
		for col in [-1,1]:_box(origin,yaw,Vector3(col*2,h+.47,1.8),Vector3(2.7,.5,1.1),"aa8064")
		for col in range(9):g.add("leaf",_local(origin,yaw,Vector3(-3.2+col*.8,h+.96,1.8)),Vector3(.8,.8,.8),"5f825b")

func _approach(o:Vector3,yaw:float,w:float,d:float,index:int) -> void:
	# Level forecourt with masonry retaining walls, then a short accessible street ramp.
	var depth=2.4 if absf(cos(yaw))>.5 else 3.8
	_box(o,yaw,Vector3(0,-1.4,d*.5+depth*.5),Vector3(w+.15,2.85,depth),"959783",true,"brick")
	_box(o,yaw,Vector3(0,.075,d*.5+depth*.5),Vector3(w+.25,.12,depth+.1),"b8b59c")
	var a=_local(o,yaw,Vector3(0,.17,d*.5+depth-.2))
	var b=_local(o,yaw,Vector3(0,0,d*.5+depth+1.0));b.y=map.height_at(b.x,b.z)+.19
	g.ribbon([a,b],2.2,"b8b59c",true,false)
	for side in [-1,1]:
		_box(o,yaw,Vector3(side*(w*.5-.35),.36,d*.5+2.1),Vector3(.48,.6,2.7),"778b72",true)
		for i in range(5):g.add("leaf",_local(o,yaw,Vector3(side*(w*.5-.35),.8,d*.5+.95+i*.48)),Vector3(.7,.55,.7),["638166","829363"][i%2])
		if index%3==0:
			var post=_local(o,yaw,Vector3(side*(w*.5-.35),.8,d*.5+3.1))
			for f in range(4):g.add("sphere",post+Vector3(rng.randf_range(-.25,.25),rng.randf_range(.05,.3),rng.randf_range(-.25,.25)),Vector3(.14,.13,.14),"c7a079")
	# Deepened doorway, wall lamp and a small hand-painted neighborhood tile.
	_box(o,yaw,Vector3(w*.44,2.15,d*.5+.26),Vector3(.23,.36,.2),"526963")
	_box(o,yaw,Vector3(w*.44,2.17,d*.5+.38),Vector3(.18,.25,.04),"e1cdaa")

func _courtyard_infill() -> void:
	for side in [-1,1]:
		var x=-40.0 if side==-1 else 52.0
		for z in [-68.0,7.0]:
			# Inhabited pocket courts, with separate potting and reading spaces.
			for dx in [-14,14]:
				var p=map.point(x+dx,z)
				g.box(p+Vector3(0,-.17,0),Vector3(8,.36,12),"aaa38a",true)
				for j in range(4):g.box(p+Vector3(-2.8+j*1.85,.51,0),Vector3(1.3,.55,4.3),"94795e")
				for j in range(18):g.add("leaf",p+Vector3(-3+rng.randf()*6,1.0,-2+rng.randf()*4),Vector3(.65,.85,.65),["6e8960","537c64","889466"][j%3])
				# Low workshop roofs and exterior ramps create additional cat-height routes.
				var shed=p+Vector3(0,0,5)
				g.box(shed+Vector3(0,1.45,0),Vector3(4.8,2.9,3.5),"9eab98",true,0,"siding")
				g.box(shed+Vector3(0,2.97,0),Vector3(5.3,.22,4),"6d7e73",true)
				g.box(shed+Vector3(.7,1.7,1.8),Vector3(1.2,1.0,.09),"d7d2b7")
				g.box(shed+Vector3(-1.1,1.2,1.8),Vector3(1.1,2.4,.1),"547367")
				g.ribbon([shed+Vector3(-3.3,.03,-7),shed+Vector3(-3.3,3.1,-.7)],1.4,"a3a78e",true,false)
				g.ribbon([shed+Vector3(-3.3,3.1,0),shed+Vector3(-1.6,3.1,0)],1.4,"a3a78e",true,false)
			var patio=map.point(x,z+1)
			g.add("cylinder",patio,Vector3(6.2,.12,6.2),"b1ad93")
			_cafe_table(patio+Vector3(0,.07,0))
			for dz in [-2.5,2.5]:
				for dx in [-2.5,2.5]:g.beam(patio+Vector3(dx,0,dz),patio+Vector3(dx,2.8,dz),.075,"8b8f72")
			for i in range(9):g.box(patio+Vector3(-2.6+i*.65,2.85,0),Vector3(.12,.14,5.5),"9c9b7b")
			for i in range(18):g.add("leaf",patio+Vector3(rng.randf_range(-2.5,2.5),2.9,rng.randf_range(-2.5,2.5)),Vector3(1.2,.45,1.1),"718d63")
			g.label("A LITTLE QUIET",patio+Vector3(0,2.32,2.57),2,"e0d3ac",0,48)
	# Gravel driveway ribbons and garden walls connect every court to its block.
	for x in [-52.0,-24.0,40.0,68.0]:
		for bounds in [[-77,-58],[-7,24]]:
			var path=[]
			for z in range(bounds[0],bounds[1]):path.append(map.point(x,z,.055))
			g.ribbon(path,2.2,"b3b197",true)
	# Hand-laid sidewalk joints, drain grates, road repairs, hydrants and bicycle stands.
	for x in [-76.0,8.0,90.0]:
		for z in range(-109,131,2):
			for side in [-1,1]:g.ribbon([map.point(x+side*5.5,z,.187),map.point(x+side*8.1,z,.187)],.022,"919b8d")
		for z in range(-89,119,23):
			g.add("cylinder",map.point(x+1.8,z,.049),Vector3(.68,.025,.68),"626f69")
			g.ribbon([map.point(x-3.7,z+1,.046),map.point(x-3.7,z+4,.046)],1.4,"536166")
			for side in [-1,1]:
				var p=map.point(x+side*5.15,z,.052)
				g.box(p,Vector3(.35,.026,.65),"596b64")
				for stripe in range(6):g.box(p+Vector3(0,.016,-.26+stripe*.105),Vector3(.33,.015,.028),"a6aa96")
		for z in [-83,12,76]:
			var p=map.point(x+7.7,z)
			g.add("cylinder",p+Vector3(0,.38,0),Vector3(.28,.76,.28),"bd9871")
			g.add("sphere",p+Vector3(0,.81,0),Vector3(.31,.21,.31),"b08a66")
			g.beam(p+Vector3(-.22,.53,0),p+Vector3(.22,.53,0),.08,"b08a66")

func _shop(o:Vector3,yaw:float,w:float,d:float,index:int,trim:String) -> void:
	var names=["BAY LEAF","SLOW MORNING","PAPER & PINE","LITTLE CURRENT","SUNROOM","THE READING ROOM","SALT & STEM","WARM LOAF"]
	var colors=["557b70","a56855","c2a46c","5d7987"]
	var color=colors[index%4]
	for x in [-w*.27,w*.27]:
		_box(o,yaw,Vector3(x,1.5,d*.5+.07),Vector3(w*.43,2.25,.1),"526d70")
		for dx in [-w*.2,w*.2]:_box(o,yaw,Vector3(x+dx,1.4,d*.5+.15),Vector3(.12,2.7,.16),trim)
		_box(o,yaw,Vector3(x,.3,d*.5+.15),Vector3(w*.44,.45,.2),color)
		for pane in [-1,0,1]:
			var pane_x=x+pane*w*.135
			_box(o,yaw,Vector3(pane_x,1.6,d*.5+.135),Vector3(w*.125,1.89,.024),["567678","648081","4a686f"][(pane+index+1)%3])
			_box(o,yaw,Vector3(pane_x-w*.066,1.6,d*.5+.22),Vector3(.05,1.95,.06),trim)
			_box(o,yaw,Vector3(pane_x-.2,2.09,d*.5+.19),Vector3(.16,.68,.018),"9fb6ad")
			# Pendant lamps and readable display objects form a shallow shop interior.
			g.beam(_local(o,yaw,Vector3(pane_x,2.6,d*.5+.22)),_local(o,yaw,Vector3(pane_x,2.3,d*.5+.22)),.012,"847c65")
			g.add("sphere",_local(o,yaw,Vector3(pane_x,2.28,d*.5+.23)),Vector3(.32,.16,.08),"d9c495")
			_box(o,yaw,Vector3(pane_x,1.02,d*.5+.23),Vector3(w*.11,.22,.035),"bca477")
			for item in range(3):
				if index%2==0:
					g.add("sphere",_local(o,yaw,Vector3(pane_x-.32+item*.32,1.21,d*.5+.27)),Vector3(.25,.14,.08),["d3b581","b99264","d8bf92"][item])
				else:_box(o,yaw,Vector3(pane_x-.32+item*.32,1.32,d*.5+.27),Vector3(.2,.48+item*.07,.08),["b3986c","779894","bf9b85"][item])
		_box(o,yaw,Vector3(x,1.92,d*.5+.24),Vector3(w*.4,.055,.08),trim)
		# Display shelves, jars and a low counter behind the glass plane.
		_box(o,yaw,Vector3(x,.84,d*.5+.18),Vector3(w*.39,.1,.04),"d9c29c")
		for j in range(5):_box(o,yaw,Vector3(x-w*.16+j*w*.08,1.12,d*.5+.2),Vector3(.35,.38,.06),["b9a371","cca67e","8aaba4"][j%3])
	_box(o,yaw,Vector3(0,1.4,d*.5+.13),Vector3(1.2,2.65,.15),color)
	_box(o,yaw,Vector3(0,1.85,d*.5+.23),Vector3(.9,1.35,.04),"98b5b2")
	_box(o,yaw,Vector3(0,3.32,d*.5+.22),Vector3(w-.25,.65,.27),color)
	_box(o,yaw,Vector3(0,2.55,d*.5+1.77),Vector3(w*.7,.6,.1),color)
	g.label(names[index%names.size()],_local(o,yaw,Vector3(0,2.55,d*.5+1.835)),w*.63,"f6e8c9",yaw)
	# Broad fabric canopy with original striped pattern made from narrow primitives.
	g.box_collision(_local(o,yaw,Vector3(0,2.75,d*.5+.88)),Vector3(w,.13,1.7),Vector3(.18,yaw,0))
	for stripe in range(16):
		var x=-w*.5+(stripe+.5)*w/16
		g.add("box",_local(o,yaw,Vector3(x,2.75,d*.5+.88)),Vector3(w/16,.1,1.7),color if stripe%2==0 else "e8d9ba",Vector3(.18,yaw,0))
		_box(o,yaw,Vector3(x,2.5,d*.5+1.7),Vector3(w/16,.35,.08),color if stripe%2==0 else "e8d9ba")
	for side in [-1,1]:
		var at=_local(o,yaw,Vector3(side*w*.35,0,d*.5+2.7))
		if index%3!=2:_cafe_table(at,yaw)
		else:_planter(at,1.1)
	var board=_local(o,yaw,Vector3(w*.44,.75,d*.5+2.35))
	g.box(board,Vector3(.75,1.1,.13),"3f625a",false,yaw)
	g.label("TAKE IT\nSLOW",board+Basis(Vector3.UP,yaw)*Vector3(0,0,.075),.55,"e9dcc0",yaw,48)

func _fire_escape(o:Vector3,yaw:float,w:float,d:float,h:float) -> void:
	for floor in range(1,int(h/3)):
		var y=floor*3+.27;var z=d*.5+1.05
		_box(o,yaw,Vector3(0,y,z),Vector3(4.2,.11,1.5),"495b59",true)
		for x in [-2.0,2.0]:g.beam(_local(o,yaw,Vector3(x,y,z-.65)),_local(o,yaw,Vector3(x,y+.9,z-.65)),.04,"495b59")
		for j in range(11):g.beam(_local(o,yaw,Vector3(-2+j*.4,y,z+.7)),_local(o,yaw,Vector3(-2+j*.4,y+.9,z+.7)),.025,"495b59")
		g.beam(_local(o,yaw,Vector3(-2,y+.9,z+.7)),_local(o,yaw,Vector3(2,y+.9,z+.7)),.035,"495b59")
		for j in range(12):_box(o,yaw,Vector3(-1.5+j*.24,y+.12+j*.23,z),Vector3(.45,.08,1.1),"495b59")

func _cafe_table(at:Vector3,yaw:float=0) -> void:
	g.add("cylinder",at+Vector3(0,.72,0),Vector3(.82,.08,.82),"bba37b")
	g.beam(at,at+Vector3(0,.69,0),.06,"536462")
	for side in [-1,1]:
		var p=at+Basis(Vector3.UP,yaw)*Vector3(side*.75,0,0)
		g.box(p+Vector3(0,.42,0),Vector3(.46,.08,.43),"788e80")
		g.box(p+Vector3(0,.73,-.2),Vector3(.46,.55,.05),"788e80")
		for dx in [-.16,.16]:
			for dz in [-.15,.15]:g.beam(p+Vector3(dx,0,dz),p+Vector3(dx,.42,dz),.018,"536462")
	g.add("cylinder",at+Vector3(0,.83,0),Vector3(.13,.18,.13),"e6dcc6")

func _planter(at:Vector3,size:float) -> void:
	g.box(at+Vector3(0,.25,0),Vector3(size,.5,size),"a98568",true)
	for i in range(4):g.add("leaf",at+Vector3(rng.randf_range(-.3,.3),.75,rng.randf_range(-.3,.3)),Vector3(.6,.7,.6),"688360")

func _gardens_and_routes() -> void:
	# Long internal alleys connect the cross streets and reveal occupied back gardens.
	for x in [-38.0,53.0]:
		for z0 in [-76.0,-8.0]:
			var path=[]
			for z in range(int(z0),int(z0+30)):path.append(map.point(x,z,.07))
			g.ribbon(path,3.0,"b6a786",true)
			for side in [-1,1]:
				for z in range(int(z0),int(z0+30),4):
					var p=map.point(x+side*3,z)
					g.box(p+Vector3(0,.65,0),Vector3(.12,1.3,.12),"9b9f8b")
					g.box(p+Vector3(0,.6,0),Vector3(.06,.07,4),"b2af96")
			for i in range(6):_planter(map.point(x+(-1 if i%2 else 1)*5,z0+3+i*4),1.4)
			# Laundry lines, a garden potting bench and a reading nook.
			var a=map.point(x-4,z0+12,2.7);var b=map.point(x+4,z0+12,2.7);g.beam(a,b,.018,"78847d")
			for i in range(6):g.box(a.lerp(b,(i+1)/7.0)-Vector3(0,.37,0),Vector3(.65,.74,.04),["eee2c6","c3cfc4","afbac7"][i%3])
			_bench(map.point(x+4,z0+21),PI*.5)
	# A real stair street on a smooth collider reaches the wooded hilltop.
	for x in [-38.0,-104.0]:
		var z0=47.0;var z1=91.0;var a=map.point(x,z0,.1);var b=map.point(x,z1,.1)
		var rise=b.y-a.y;var count=ceili(rise/.16);var run=(z1-z0)/count
		for i in range(count):
			var y=a.y+(i+1)*rise/count
			g.box(Vector3(x,y-.1,z0+(i+.5)*run),Vector3(3.4,.2,run+.02),"b9b9a7")
		g.ribbon([map.point(x,z0-1,.015),a,b,map.point(x,z1+1,.015)],3.45,"b9b9a7",true,false)
		for side in [-1,1]:
			g.beam(a+Vector3(side*1.6,.95,0),b+Vector3(side*1.6,.95,0),.045,"586c64")
			for i in range(12):
				var p=a.lerp(b,i/11.0)+Vector3(side*1.6,0,0);g.beam(p,p+Vector3.UP*.95,.035,"586c64")
		g.label("CYPRESS STEPS",a+Vector3(-2.6,1.2,0),1.6,"586c64",0)
	# A planted retaining edge gives the park-facing residential lane an owned boundary.
	for x in range(-18,78,3):
		var at=map.point(x,54)
		g.box(at+Vector3(0,.34,0),Vector3(2.95,.68,.5),"8f9985",true,0,"brick")
		for j in range(3):g.add("leaf",at+Vector3(-.9+j*.9,.9,0),Vector3(1.1,.75,.95),["6d865f","8b9665"][j%2])
	# Upper plaza: shelter, tiled turning circle, neighborhood noticeboard.
	var p=map.point(8,96)
	for x in [-7,7]:_bench(p+Vector3(x,0,1),-PI*.5 if x<0 else PI*.5)
	g.box(map.point(-5,84,1.1),Vector3(1.8,1.4,.15),"5c7465",true)
	g.label("HARBOR HILLS\nGARDEN WALK\nSUNDAYS",map.point(-5,84,1.1)+Vector3(0,0,.09),1.5,"ecdfbe",0,56)
	# A short ramp onto a low garden pavilion gives the cat a roof route.
	var pavilion=map.point(-56,62)
	g.box(pavilion+Vector3(0,1.25,0),Vector3(7,2.5,6),"b6a58b",true)
	g.box(pavilion+Vector3(0,2.6,0),Vector3(7.6,.2,6.6),"738b7c",true)
	g.ribbon([map.point(-56,52,.02),pavilion+Vector3(0,2.72,-3.3)],2.4,"abac91",true,false)
	_bench(pavilion+Vector3(0,2.73,0),PI)

func _bench(at:Vector3,yaw:float) -> void:
	for i in range(4):g.box(at+Basis(Vector3.UP,yaw)*Vector3(0,.45,-.24+i*.15),Vector3(1.75,.08,.12),"a29573",false,yaw)
	for i in range(3):g.box(at+Basis(Vector3.UP,yaw)*Vector3(0,.75+i*.13,-.35),Vector3(1.75,.1,.07),"a29573",false,yaw)
	for x in [-.65,.65]:g.beam(at+Basis(Vector3.UP,yaw)*Vector3(x,0,0),at+Basis(Vector3.UP,yaw)*Vector3(x,.5,0),.04,"566961")

func _street_furniture() -> void:
	for x in [-76.0,8.0,90.0]:
		for z in range(-94,130,22):
			var p=map.point(x-7.7,z)
			g.beam(p,p+Vector3.UP*5.3,.08,"4c6562")
			g.beam(p+Vector3.UP*5.2,p+Vector3(1,5.5,0),.055,"4c6562")
			g.add("sphere",p+Vector3(1,5.35,0),Vector3(.55,.35,.55),"dfd2ad")
			if z%3==0:_bench(map.point(x+7.5,z),PI*.5)
			# Utility poles and sagging service wires.
			var pole=map.point(x+8.3,z)
			g.beam(pole,pole+Vector3.UP*8,.12,"8c7960")
			g.box(pole+Vector3(0,7.45,0),Vector3(2.8,.14,.16),"8c7960")
			if z<126:
				for dx in [-1,0,1]:
					var a=pole+Vector3(dx,7.6,0);var b=map.point(x+8.3,z+22,7.6)+Vector3(dx,0,0)
					var prev=a
					for i in range(1,13):
						var t=i/12.0;var next=a.lerp(b,t)-Vector3.UP*sin(t*PI)*.65;g.beam(prev,next,.014,"58645f");prev=next
			if x!=8 and z%2==0:_car(map.point(x+3.6,z+7,.04),0,["879f9e","b09d82","b78270","d1c6ab"][posmod(z,4)])
	for z in [-101.0,-32.0,46.0,91.0]:
		var p=map.point(14.5,z)
		g.beam(p,p+Vector3.UP*2.9,.055,"576c65")
		g.box(p+Vector3(0,2.4,0),Vector3(.9,.75,.1),"718a7c")
		g.label("CABLE\nLINE",p+Vector3(0,2.42,.06),.7,"f3e2b8",0,52)
		_bench(map.point(17.5,z),PI)
		g.box(map.point(17.4,z,2.55),Vector3(3.8,.12,1.8),"a2b4a8")
		for dx in [-1.65,1.65]:g.beam(map.point(17.4+dx,z-.7),map.point(17.4+dx,z-.7,2.5),.06,"576c65")
	for p in [map.point(-69,-34),map.point(16,-30),map.point(84,42)]:
		g.add("cylinder",p+Vector3(0,.48,0),Vector3(.65,.96,.65),"5d796a")
		g.add("cylinder",p+Vector3(1.1,.25,0),Vector3(.26,.5,.26),"b08c68")
		g.beam(p+Vector3(-.5,0,.4),p+Vector3(-.5,3.1,.4),.045,"506a62")
		g.box(p+Vector3(-.5,2.95,.4),Vector3(1.95,.33,.1),"506a62")
		g.label("CYPRESS WAY",p+Vector3(-.5,2.95,.46),1.7,"e8ddbf",0,64)

func _car(at:Vector3,yaw:float,color:String) -> void:
	# Compact fictional neighborhood cars, parked clear of crossings.
	g.box(at+Vector3(0,.62,0),Vector3(1.7,.65,3.8),color,true,yaw)
	g.box(at+Vector3(0,1.13,.15),Vector3(1.5,.7,1.9),color,false,yaw)
	g.box(at+Vector3(0,1.2,1.13),Vector3(1.35,.48,.035),"6b9095",false,yaw)
	g.box(at+Vector3(0,1.2,-.83),Vector3(1.35,.48,.035),"6b9095",false,yaw)
	for side in [-1,1]:
		g.box(at+Vector3(side*.76,1.22,.15),Vector3(.03,.43,1.58),"6b9095",false,yaw)
		for z in [-1.18,1.15]:g.add("cylinder",at+Vector3(side*.84,.38,z),Vector3(.57,.19,.57),"3d4749",Vector3(0,0,PI*.5))
		g.box(at+Vector3(side*.58,.72,-1.91),Vector3(.35,.2,.05),"d8cfa5")

func _waterfront() -> void:
	for x in range(-160,171,7):
		var p=Vector3(x,3.25,-119)
		g.beam(p,p+Vector3.UP*1.02,.045,"617a72")
		if x<166:
			for h in [.48,.97]:g.beam(p+Vector3.UP*h,p+Vector3(7,h,0),.025,"617a72")
	for x in [-149,-114,-53,-9,39,88,141]:
		_bench(map.point(x,-112),0)
		if x%3==0:_planter(map.point(x+3,-112),1.2)
	# Small waterfront gathering places interrupt the promenade's long rhythm.
	for x in range(-170,173,2):g.ribbon([map.point(x,-117,.102),map.point(x,-108.8,.102)],.018,"a0aa9c")
	for z in [-116.0,-110.0]:
		var joints=[]
		for x in range(-170,173,2):joints.append(map.point(x,z,.102))
		g.ribbon(joints,.025,"a0aa9c")
	var deck=Vector3(-25,3.22,-113.5)
	for i in range(55):g.box(deck+Vector3(-6.6+i*.245,0,0),Vector3(.23,.18,7.6),["a49b7e","aca38a","9c967b"][i%3])
	_cafe_table(deck+Vector3(-3,.1,0));_cafe_table(deck+Vector3(3,.1,0))
	_bench(deck+Vector3(0,.1,-2.2),0)
	g.box(deck+Vector3(0,.64,-2.05),Vector3(.4,.09,.3),"bc9a76")
	g.box(deck+Vector3(.03,.7,-2.05),Vector3(.36,.04,.27),"e0d5b3")
	var kiosk=map.point(47,-110)
	g.box(kiosk+Vector3(0,1.35,0),Vector3(3.8,2.7,2.5),"78968a",true,0,"siding")
	g.box(kiosk+Vector3(0,2.83,0),Vector3(4.4,.25,3.1),"b7baa0")
	g.box(kiosk+Vector3(0,1.48,-1.28),Vector3(2.5,1.35,.08),"456b70")
	g.box(kiosk+Vector3(0,.87,-1.47),Vector3(3.0,.14,.5),"b3aa8c")
	g.box(kiosk+Vector3(0,2.47,-1.29),Vector3(3.3,.38,.08),"496c60")
	g.label("BAY POST",kiosk+Vector3(0,2.47,-1.35),2.3,"e9d6ae",PI)
	for i in range(6):g.box(kiosk+Vector3(-1+i*.4,1.16,-1.38),Vector3(.31,.35,.07),["c1b497","a4b7ab","bd9a7c"][i%3])
	for side in [-1,1]:
		_planter(kiosk+Vector3(side*2.5,0,0),1.2)
		g.box(kiosk+Vector3(side*1.35,1.48,-1.32),Vector3(.12,1.45,.1),"dfd6b7")
	# A sheltered bicycle rack and a few rope bollards frame the boat-house approach.
	for x in [-103,-101.8,-100.6,-99.4]:
		var p=map.point(x,-112)
		g.beam(p+Vector3(-.3,0,0),p+Vector3(-.3,.75,0),.03,"586f64")
		g.beam(p+Vector3(.3,0,0),p+Vector3(.3,.75,0),.03,"586f64")
		g.beam(p+Vector3(-.3,.75,0),p+Vector3(.3,.75,0),.03,"586f64")
	for x in [-116,-111,-105,-100]:
		var p=Vector3(x,3.2,-118)
		g.add("cylinder",p+Vector3(0,.3,0),Vector3(.32,.6,.32),"738578")
		g.add("sphere",p+Vector3(0,.62,0),Vector3(.43,.17,.43),"738578")
		if x!=-100:
			var previous=p+Vector3.UP*.5
			for i in range(1,9):
				var next=p+Vector3(i*.625,.5-sin(i/8.0*PI)*.27,0);g.beam(previous,next,.025,"ad9c76");previous=next
	# Quiet working pier, rope bollards, weathered shed and stacked lobster pots.
	g.box(Vector3(-114,2.3,-141),Vector3(12,.7,45),"989d8e",true,0,"siding")
	for z in range(-161,-119,5):
		for x in [-119,-109]:g.add("cylinder",Vector3(x,.1,z),Vector3(.6,5,.6),"727e72")
	g.box(Vector3(-114,4.1,-134),Vector3(5.5,3,6),"8baba1",true,0,"siding")
	g.box(Vector3(-114,5.8,-134),Vector3(6.2,.3,6.6),"75837e")
	for i in range(6):g.box(Vector3(-117+i%2*1.2,2.95+floori(i/2)*.5,-147),Vector3(1,.45,.8),"8a8064")
	g.label("TIDELINE\nBOAT HOUSE",Vector3(-114,4.25,-130.94),3.3,"eee0bc",0)
