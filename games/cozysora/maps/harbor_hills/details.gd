extends RefCounted
## Pedestrian-scale places and planted transitions, owned only by Harbor Hills.
var map
var g
var rng=RandomNumberGenerator.new()

func build(world,geometry) -> void:
	map=world;g=geometry;rng.seed=57329
	_street_gardens()
	_shops_and_homes()
	_hillside_borders()
	_harbor_places()

func _street_gardens() -> void:
	# The outer edge leaves the two-metre pavement route and every crossing open.
	for x in [-.7,17.3]:
		for z in [-91.0,-80.0,-51.0,-20.0,25.0,65.0,120.0]:
			_bed(map.point(x,z,.08),Vector2(1.05,3.8),int(z),true)
	for z in [-74.,-57.,-12.,24.,70.]:_bed(map.point(12.65,z,.03),Vector2(.95,3.4),int(z),true)
	for x in [-83.8,98.1]:
		for z in [-76.0,-54.0,-9.0,24.0,69.0,119.0]:
			_bed(map.point(x,z,.15),Vector2(.8,3.1),int(z+10),true)
	# Frontages receive distinct low gardens rather than a continuous hedge wall.
	for z in [-95.7,-37.3,39.0]:
		for x in [-63.0,-47.0,-19.0,32.0,60.0,75.0]:
			_bed(map.point(x,z,.12),Vector2(3.0,.8),int(x+z),true)
	for x in [-65.0,-32.0,38.0,67.0,113.0]:
		_bed(map.point(x,-110.0),Vector2(4.3,1.15),int(x),true)
	# An irregular groundcover ribbon occupies formerly naked strips beside homes.
	for z in [-93.0,-38.0,39.0]:
		for i in range(150):
			var x=rng.randf_range(-66,79)
			if x>-5 and x<21:continue
			var at=map.point(x,z+rng.randf_range(-.45,.45),.1)
			g.add("leaf",at+Vector3.UP*.18,Vector3(.75,.38,.65),["668748","78934d","47754a"][i%3])
	for z in [-78.0,-1.0,78.0]:
		_bicycle(map.point(17.1,z,.15),PI*.5,"ba8e65")
		g.box(map.point(-.8,z,1.0),Vector3(.38,1.6,.48),"486b62")
		g.label("BAY\nWALK",map.point(-.8,z,1.02)+Vector3(0,0,.25),.31,"e9d9ad",0,36)

func _bed(at:Vector3,size:Vector2,index:int,raised:bool=false) -> void:
	var lift=.24 if raised else .0
	if raised:
		g.box(at+Vector3(0,.16,0),Vector3(size.x,.32,size.y),"8f8c72",false,0,"brick")
		g.box(at+Vector3(0,.33,0),Vector3(size.x+.08,.08,size.y+.08),"c1b69b")
		g.box(at+Vector3(0,.38,0),Vector3(size.x-.1,.025,size.y-.1),"685f43")
	var count=maxi(7,int(size.x*size.y*3))
	for i in range(count):
		var p=at+Vector3(rng.randf_range(-.43,.43)*size.x,lift+.24,rng.randf_range(-.43,.43)*size.y)
		g.add("leaf",p,Vector3(.65,.7,.65),["5f8446","8b984d","42774e"][i%3])
		if i%2==0:_flower(p+Vector3.UP*rng.randf_range(.15,.35),["dea34b","dccdc1","b08ca6"][posmod(index,3)])

func _flower(p:Vector3,color:String) -> void:
	g.beam(p-Vector3.UP*.35,p,.011,"668046")
	for i in range(5):
		var angle=i*TAU/5
		g.add("sphere",p+Vector3(cos(angle)*.08,0,sin(angle)*.08),Vector3(.13,.05,.13),color)
	g.add("sphere",p+Vector3.UP*.024,Vector3(.065,.047,.065),"d4ae48")

func _shops_and_homes() -> void:
	# The café arrival: glazed pastry case, baskets and a legible sidewalk menu.
	var p=map.point(19.8,-77.0)
	g.box(p+Vector3(0,.43,0),Vector3(.8,.86,1.6),"9c7955")
	for j in range(3):
		g.box(p+Vector3(0,.98,j*.46-.46),Vector3(.76,.1,.4),"ccb486")
		for i in range(4):g.add("sphere",p+Vector3(-.25+i*.17,1.1,j*.46-.46),Vector3(.17,.14,.23),["c6a46d","d8b679","a77e4f"][j])
	for z in [-83.0,-52.0,-14.0,30.0]:
		var at=map.point(19.1,z,.25)
		g.box(at+Vector3(0,.6,0),Vector3(.17,1.2,.78),"a18a67")
		g.box(at+Vector3(-.1,.66,0),Vector3(.04,.95,.61),"365d50")
		g.label("TODAY\nCOFFEE\n& WARM\nBREAD",at+Vector3(-.13,.66,0),.51,"eadbb8",-PI*.5,48)
	# Wall-mounted projecting signs, each with a different painted emblem.
	for z in [-68.0,7.0]:
		for side in [-1,1]:
			var at=map.point(19.8 if side==1 else -3.8,z-4,3.1)
			g.beam(at,at+Vector3(-side*1.1,0,0),.035,"4a6258")
			g.box(at+Vector3(-side*.7,-.38,0),Vector3(.75,.65,.09),["a96b4c","668470"][0 if z<0 else 1])
			g.label("BAKE" if z<0 else "BOOKS",at+Vector3(-side*.7,-.35,.06),.62,"f0ddb1",0,48)
	# Richer residential stoops: door handles, lamps, potted plants and letter boxes.
	for row in range(4):
		var z=[-87.0,-49.0,-14.0,28.0][row]
		var yaw=PI if row%2==0 else 0.;var turn=Basis(Vector3.UP,yaw)
		for side in range(2):
			for col in range(4):
				var x=(-59 if side==0 else 28)+col*14
				var front=Vector3(x,0,z)+turn*Vector3(0,0,8)
				var o=Vector3(x,map.terrain_height(front.x,front.z)+.2,z)
				var door=o+turn*Vector3(3.2,1.4,6.26)
				g.add("sphere",door+turn*Vector3(.46,0,0),Vector3(.07,.07,.07),"d3b478")
				g.box(o+turn*Vector3(4.4,1.05,6.18),Vector3(.44,.55,.21),"546f65",false,yaw)
				g.box(o+turn*Vector3(4.4,1.16,6.31),Vector3(.31,.035,.015),"293e3a",false,yaw)
				var pot=o+turn*Vector3(3.9,.23,7.1)
				g.add("cylinder",pot,Vector3(.46,.48,.46),"bb8764")
				g.add("leaf",pot+Vector3.UP*.47,Vector3(.8,.9,.8),"719147")
				for f in range(4):_flower(pot+Vector3(rng.randf_range(-.2,.2),.8,rng.randf_range(-.2,.2)),"c99f7e")
				if (col+row)%3==0:
					var at=o+turn*Vector3(-4.2,0,7.1)
					_bicycle(at,yaw,"70919a")
				# Recessed roof lanterns and asymmetrical terracotta herb tubs.
				var floors=3 if row==0 or (row*8+side*4+col)%4==0 else 2
				var roof=o+Vector3.UP*(floors*3+.95)
				if col%2==0:
					g.box(roof+turn*Vector3(-2,.0,-1),Vector3(2.2,.26,2.8),"b5aa90",false,yaw)
					g.box(roof+turn*Vector3(-2,.17,-1),Vector3(1.9,.12,2.5),"6e9699",false,yaw)
					for j in range(4):g.box(roof+turn*Vector3(-2,.25,-2+j*.66),Vector3(1.94,.035,.035),"d0c8ab",false,yaw)
	# Courts are lush enclosed gardens with stepping stones and climbing trellises.
	for x in [-40.0,52.0]:
		for z in [-68.0,7.0]:
			for side in [-1,1]:
				var at=map.point(x+side*8.4,z+1)
				_bed(at,Vector2(1.8,8),int(x+z),false)
				for j in range(3):
					var p1=map.point(x+side*8.0,z-3+j*3)
					g.add("leaf",p1+Vector3.UP*.65,Vector3(1.4,1.65,1.4),"527c46")
			for i in range(7):
				var at=map.point(x-3.5+i*.6,z-3.5,.07)
				g.add("cylinder",at,Vector3(.45,.09,.63),"b5af94")

func _bicycle(p:Vector3,yaw:float,color:String) -> void:
	var turn=Basis(Vector3.UP,yaw)
	for x in [-.55,.55]:
		for i in range(24):
			var a=i*TAU/24;var b=(i+1)*TAU/24
			g.beam(p+turn*Vector3(x+cos(a)*.34,.37+sin(a)*.34,0),p+turn*Vector3(x+cos(b)*.34,.37+sin(b)*.34,0),.025,"374d48")
		for i in range(8):
			var a=i*TAU/8;g.beam(p+turn*Vector3(x,.37,0),p+turn*Vector3(x+cos(a)*.32,.37+sin(a)*.32,0),.005,"b2b9a5")
	var vertices=[Vector3(-.55,.37,0),Vector3(-.18,.8,0),Vector3(.05,.36,0),Vector3(.39,.82,0),Vector3(.55,.37,0)]
	for edge in [[0,1],[1,2],[2,0],[1,3],[3,2],[3,4]]:g.beam(p+turn*vertices[edge[0]],p+turn*vertices[edge[1]],.023,color)
	g.beam(p+turn*Vector3(.38,.8,0),p+turn*Vector3(.32,1.08,0),.02,"a5afa2")
	g.beam(p+turn*Vector3(.32,1.08,-.18),p+turn*Vector3(.32,1.08,.18),.02,"52685c")
	g.box(p+turn*Vector3(-.18,.89,0),Vector3(.28,.055,.19),"635e4c",false,yaw)
	g.box(p+turn*Vector3(.56,.93,0),Vector3(.27,.28,.34),"b4a27b",false,yaw)

func _hillside_borders() -> void:
	for x in [-38.0,-104.0]:
		for z in range(48,92,2):
			for side in [-1,1]:
				var y=map.height_at(x,z)
				var bank=map.terrain_height(x+side*2.6,z)
				var height=maxf(.45,bank-y+.15)
				g.box(Vector3(x+side*2.13,y+height*.5-.2,z),Vector3(.72,height,2.04),"8c957a",false,0,"brick")
				var p=map.point(x+side*2.95,z)
				g.add("leaf",p+Vector3.UP*.35,Vector3(1.6,.9,2.3),["547944","769044","929b50"][posmod(z,3)])
				if z%4==0:_flower(p+Vector3.UP*.85,"d6a456")
	# Meadow edges get a continuous transition of shrubs, flowers and rocks.
	for route in [[Vector2(-112,101),Vector2(-54,110)],[Vector2(-104,74),Vector2(-22,111)],[Vector2(-55,110),Vector2(-16,133)]]:
		var a:Vector2=route[0];var b:Vector2=route[1];var side=(b-a).normalized().orthogonal()
		for i in range(int(a.distance_to(b)*1.4)):
			var p=a.lerp(b,i/(a.distance_to(b)*1.4))
			for sign_value in [-1,1]:
				var at=p+side*sign_value*rng.randf_range(2,3.5)
				if (absf(at.x+38)<3 or absf(at.x+104)<3) and at.y<96:continue
				var position=map.point(at.x,at.y)
				g.add("leaf",position+Vector3.UP*.33,Vector3(1.35,.8,1.4),["748d42","528044","8d9747"][i%3])
				if i%2==0:_flower(position+Vector3.UP*.75,["dcbb67","d0c5b9","be97b0"][i%3])
	for x in [-27.0,-10.0,39.0,61.0,79.0,123.0]:
		for z in [124.0,148.0,164.0]:
			_bed(map.point(x,z),Vector2(8,5),int(x+z),false)
	# Pavillion fascia, climbing trellis and planted lower edges make its ramp inviting.
	var p=map.point(-56,62)
	g.box(p+Vector3(0,1.95,-3.04),Vector3(3.9,.44,.09),"4a705b")
	g.label("THE GARDEN ROOM",p+Vector3(0,1.95,-3.1),3.5,"ead9b1",PI)
	for side in [-1,1]:
		_bed(p+Vector3(side*4.4,0,.5),Vector2(1.4,5.5),side,false)
		for j in range(8):g.box(p+Vector3(side*3.58,.25+j*.3,0),Vector3(.08,.035,4.8),"a6a584")
		for j in range(5):g.box(p+Vector3(side*3.59,1.3,-2+j),Vector3(.06,2.5,.05),"a6a584")
		for j in range(12):g.add("leaf",p+Vector3(side*3.7,rng.randf_range(.3,2.5),rng.randf_range(-2.4,2.4)),Vector3(.6,.9,.75),"638645")

func _harbor_places() -> void:
	# Two shade sails shelter tables without closing the central promenade.
	for x in [-28.0,67.0]:
		var p=map.point(x,-114,.14)
		for dx in [-3.3,3.3]:
			for dz in [-1.9,1.9]:g.beam(p+Vector3(dx,0,dz),p+Vector3(dx,3.2,dz),.055,"8c8e70")
		for i in range(10):g.box(p+Vector3(-3.4+i*.75,3.18,0),Vector3(.12,.13,4.4),"b5ab84")
		for i in range(6):g.cloth(p+Vector3(-2.85+i*1.14,3.12,-2),Vector2(1.1,.32),"d7c69e")
		for side in [-1,1]:_bed(p+Vector3(side*4.2,0,0),Vector2(1,3.6),int(x),true)
	# Rope coils, dock fenders, pier planking and clearly shaped crates.
	for z in range(-160,-120):
		g.box(Vector3(-114,2.68,z+.45),Vector3(11.5,.045,.035),"747d6a")
	for z in [-127.0,-140.0,-153.0]:
		for side in [-1,1]:
			var p=Vector3(-114+side*5.7,2.75,z)
			g.add("cylinder",p+Vector3.UP*.25,Vector3(.3,.5,.3),"65796b")
			g.beam(p+Vector3(-.3,.36,0),p+Vector3(.3,.36,0),.08,"65796b")
			for ring in range(4):
				for i in range(20):
					var a=i*TAU/20;var b=(i+1)*TAU/20;var r=.22+ring*.042
					g.beam(p+Vector3(cos(a)*r,.045,sin(a)*r+.7),p+Vector3(cos(b)*r,.045,sin(b)*r+.7),.018,"b6a078")
			g.add("sphere",p+Vector3(side*.28,-1.05,0),Vector3(.42,1,.42),"567167")
	var previous=Vector3(-119.6,3.05,-142)
	for i in range(1,17):
		var t=i/16.;var next=Vector3(-119.6,3.05,-142).lerp(Vector3(-123,.45,-145),t)-Vector3.UP*sin(t*PI)*.4
		g.beam(previous,next,.02,"bdab85");previous=next
	for i in range(6):
		var p=Vector3(-111.6,2.95+(i/3)*.48,-145+i%3*1.05)
		g.box(p,Vector3(.9,.44,.85),"a58c65")
		for j in range(4):g.box(p+Vector3(-.34+j*.22,.24,0),Vector3(.15,.04,.85),"c0a77c")
