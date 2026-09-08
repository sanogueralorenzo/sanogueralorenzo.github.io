extends RefCounted
## Adapted Harbor Hills facade vocabulary, composed as small Mediterranean terraces.
var map
var g
const PLOTS = [
[-43,23,10,9,7,0],[-8,23,11,9,9,1],[6,25,10,10,6,2],[21,27,10,9,8,3],
[-43,47,11,10,9,1],[-12,47,11,10,7,0],[2,48,12,10,10,2],[19,52,11,10,8,3],
[-37,78,10,9,7,2],[-25,89,9,10,8,1],[5,96,11,9,7,0],[20,99,11,9,9,3],
[-49,100,10,10,8,0],[-34,113,11,10,7,3],[-5,114,11,10,8,2],[36,109,10,10,7,1]]
const WALLS=["e4d8b9","ddb89b","e5c9a3","c3cdc0"]

func build(world,geometry) -> void:
	map=world;g=geometry
	for i in range(PLOTS.size()):house(PLOTS[i],i)
	pergola(map.point(-41,36),Vector2(10,5))
	for p in [Vector2(-43,36),Vector2(-38,36),Vector2(1,37),Vector2(6,37),Vector2(17,42)]:table(map.point(p.x,p.y))
	# A rooftop reading terrace has its own gentle side ramp from the rear garden.
	var p=map.point(-43,61)
	g.box(p+Vector3.UP*1.4,Vector3(6,2.8,5),"d1c7aa",true)
	g.box(p+Vector3.UP*2.87,Vector3(6.3,.16,5.3),"e1d5b6",true)
	g.ribbon([map.point(-48,73,.08),p+Vector3(-2,2.98,2.2)],2,"c8bea0",true,false)
	bench(p+Vector3(1,2.97,0),PI)
	# A parked neighborhood tram is a landmark, not a traffic obstacle.
	p=map.point(-5.7,40)
	g.box(p+Vector3.UP*1.1,Vector3(2.4,1.8,4.8),"b58b59",true)
	g.box(p+Vector3.UP*2.05,Vector3(2.7,.22,5.1),"e3d1a5",true)
	for side in [-1,1]:
		for z in [-1.5,-.5,.5,1.5]:g.box(p+Vector3(side*1.22,1.55,z),Vector3(.04,.85,.75),"577b7e")
	g.label("BAY LINE",p+Vector3(0,1.2,-2.43),1.9,"fff0cd",PI)
	g.box(map.point(-9,35,.9),Vector3(.8,1.8,.7),"a9b79e",true)
	g.label("STOP",map.point(-9,35,2),.65,"4c716a",PI)

func house(plot: Array,index: int) -> void:
	var x: float=plot[0];var z: float=plot[1];var w: float=plot[2];var d: float=plot[3];var h: float=plot[4]
	var base=map.terrain_height(x,z-d*.5-1)
	var p=Vector3(x,base,z)
	var color: String=WALLS[plot[5]]
	# Foundations reach into the hillside; the forecourt meets its downhill street.
	g.box(p+Vector3(0,(h-1)*.5,0),Vector3(w,h+1,d),color,true)
	g.box(p+Vector3(0,.24,-d*.5-.035),Vector3(w,.5,.14),"b3b09a",false,0,"brick")
	g.box(p+Vector3(0,h+.07,0),Vector3(w+.4,.18,d+.4),"f0e3c4",true)
	g.box(p+Vector3(0,h+.2,0),Vector3(w-.35,.12,d-.35),"b79773",true,0,"roof")
	for side in [-1,1]:g.box(p+Vector3(side*(w*.5-.09),h+.48,0),Vector3(.2,.6,d),color,true)
	g.box(p+Vector3(0,h+.48,d*.5-.09),Vector3(w,.6,.2),color,true)
	for y in range(1,int(h/3)+1):
		var wy=1.6+(y-1)*2.8
		for col in [-1,0,1]:
			var wx=col*w*.29
			window(p+Vector3(wx,wy,-d*.5-.045),1.75,1.85)
			if y>1 and (col+index)%2==0:
				g.box(p+Vector3(wx,wy-1,-d*.5-.45),Vector3(2.15,.17,1),"e9dabb",true)
				for j in range(6):g.beam(p+Vector3(wx-.94+j*.38,wy-.9,-d*.5-.88),p+Vector3(wx-.94+j*.38,wy-.1,-d*.5-.88),.018,"54786d")
				g.beam(p+Vector3(wx-1,wy-.1,-d*.5-.88),p+Vector3(wx+1,wy-.1,-d*.5-.88),.025,"54786d")
		g.box(p+Vector3(0,wy-1.25,-d*.5-.12),Vector3(w+.13,.12,.3),"efdfbe")
	# Side and rear fenestration keeps the neighborhood convincing from flight.
	for side in [-1,1]:
		for row in range(int(h/3)):
			for dz in [-d*.25,d*.25]:
				g.box(p+Vector3(side*(w*.5+.03),1.7+row*2.8,dz),Vector3(.08,1.8,1.45),"eee0be")
				g.box(p+Vector3(side*(w*.5+.08),1.7+row*2.8,dz),Vector3(.05,1.5,1.2),"658786")
				g.box(p+Vector3(side*(w*.5+.13),1.7+row*2.8,dz),Vector3(.05,.055,1.2),"e9dbb8")
				g.box(p+Vector3(side*(w*.5+.13),1.7+row*2.8,dz),Vector3(.05,1.5,.055),"e9dbb8")
			window(p+Vector3(side*w*.25,1.7+row*2.8,d*.5+.13),1.5,1.7,true)
		g.beam(p+Vector3(side*w*.46,.3,d*.5+.14),p+Vector3(side*w*.46,h,d*.5+.14),.04,"8f927b")
	if index<8:
		var names=["SALT & SUN","POSTCARDS","LEMON CAFÉ","BAY BAKERY","OLIVE HOUSE","SUMMER TABLE","THE READING ROOM","GELATO"]
		g.box(p+Vector3(0,1.25,-d*.5-.11),Vector3(w*.76,2.35,.1),"406669")
		for c in [-1,0,1]:g.box(p+Vector3(c*w*.25,1.25,-d*.5-.18),Vector3(.08,2.45,.08),"d3c9a8")
		g.add("box",p+Vector3(0,2.85,-d*.5-.9),Vector3(w*.9,.12,2.1),"355c61",Vector3(-.15,0,0))
		g.box(p+Vector3(0,2.67,-d*.5-1.94),Vector3(w*.9,.3,.1),"355c61")
		g.label(names[index],p+Vector3(0,2.68,-d*.5-2.01),w*.7,"f1e1bd",PI)
		for side in [-1,1]:pot(p+Vector3(side*(w*.5-.4),0,-d*.5-1),.8)
	else:
		g.box(p+Vector3(0,1.15,-d*.5-.12),Vector3(1.35,2.3,.15),"537b71")
	# Narrow planted roof edge and one chimney, leaving safe gull landing space.
	g.box(p+Vector3(w*.25,h+.75,d*.25),Vector3(.6,1.25,.7),"c7b692")
	if index%2==0:
		g.box(p+Vector3(0,h+.5,-d*.5+.5),Vector3(w*.75,.4,.7),"c3a583")
		for i in range(9):g.add("leaf",p+Vector3(-w*.32+i*w*.08,h+.85,-d*.5+.5),Vector3(1,.7,.8),"658956")
	# Low retaining face ends inside the plot; access is from its broad forecourt.
	var front=z-d*.5-1.5
	g.box(Vector3(x,base-.35,front),Vector3(w+.1,.8,2.8),"c3bca1",true,0,"brick")
	g.ribbon([Vector3(x,base+.07,front-1),map.point(x,front-3,.07)],w*.8,"cfc4a6",true,false)

func window(p: Vector3,w: float,h: float,back: bool=false) -> void:
	var s=1 if back else -1
	g.box(p,Vector3(w+.22,h+.2,.12),"f2e4c4")
	g.box(p+Vector3(0,0,s*.08),Vector3(w,h,.05),"60878a")
	g.box(p+Vector3(0,0,s*.13),Vector3(.055,h,.04),"e9dbb8")
	g.box(p+Vector3(0,0,s*.13),Vector3(w,.06,.04),"e9dbb8")
	for side in [-1,1]:g.box(p+Vector3(side*(w*.5+.25),0,.01),Vector3(.3,h,.1),"7c9c86")

func pot(p: Vector3,size: float=1) -> void:
	g.add("branch",p+Vector3.UP*.35*size,Vector3(.68,.7,.68)*size,"bc9473",Vector3(PI,0,0))
	g.add("leaf",p+Vector3.UP*.92*size,Vector3(1.2,1,1.2)*size,"608552")
	for i in range(4):g.add("sphere",p+Vector3(sin(i*2.4)*.3,1.1,cos(i*2.4)*.3)*size,Vector3(.13,.15,.13)*size,"d8b971")

func table(p: Vector3) -> void:
	g.add("cylinder",p+Vector3.UP*.72,Vector3(1.2,.1,1.2),"b59e74")
	g.beam(p,p+Vector3.UP*.7,.06,"426a66")
	g.box_collision(p+Vector3.UP*.5,Vector3(.85,1,.85))
	for side in [-1,1]:
		var c=p+Vector3(side*.95,0,0)
		g.box(c+Vector3.UP*.4,Vector3(.46,.08,.48),"82957c",true)
		g.box(c+Vector3(side*.2,.72,0),Vector3(.06,.55,.48),"82957c")
		for dx in [-.18,.18]:
			for dz in [-.18,.18]:g.beam(c+Vector3(dx,0,dz),c+Vector3(dx,.42,dz),.023,"426a66")
	g.add("cylinder",p+Vector3(.2,.84,.1),Vector3(.12,.15,.12),"eee0bc")

func bench(p: Vector3,yaw: float=0) -> void:
	var b=Basis(Vector3.UP,yaw)
	for z in [-.2,0,.2]:g.box(p+b*Vector3(0,.45,z),Vector3(2,.09,.16),"ac9269",false,yaw)
	for y in [.72,.94]:g.box(p+b*Vector3(0,y,.29),Vector3(2,.16,.07),"ac9269",false,yaw)
	for x in [-.75,.75]:g.box(p+b*Vector3(x,.23,0),Vector3(.09,.46,.55),"55776b",false,yaw)
	g.box_collision(p+Vector3.UP*.5,Vector3(2,1,.65),Vector3(0,yaw,0))

func pergola(p: Vector3,size: Vector2) -> void:
	for x in [-size.x*.5,size.x*.5]:
		for z in [-size.y*.5,size.y*.5]:
			g.box(p+Vector3(x,1.6,z),Vector3(.15,3.2,.15),"8c9271",true)
	for i in range(11):g.box(p+Vector3(-size.x*.5+size.x*i/10,3.15,0),Vector3(.18,.18,size.y+.6),"a39c79")
	for z in [-size.y*.5,size.y*.5]:g.box(p+Vector3(0,3.03,z),Vector3(size.x+.5,.19,.18),"a39c79")
	for i in range(20):g.add("leaf",p+Vector3(sin(i*2.4)*size.x*.5,3.28,cos(i*2.4)*size.y*.5),Vector3(1.7,.6,1.4),["65854b","7d9750"][i%2])

func lamp(p: Vector3) -> void:
	g.beam(p,p+Vector3.UP*3.6,.045,"54736b")
	g.box(p+Vector3.UP*3.65,Vector3(.3,.4,.3),"e5d5a3")
	g.box(p+Vector3.UP*3.92,Vector3(.42,.1,.42),"54736b")
