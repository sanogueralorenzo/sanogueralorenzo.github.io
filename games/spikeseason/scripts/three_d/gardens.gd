extends "res://scripts/three_d/coast.gd"
## An orchard courtyard above the sea, enclosed by planted terraces and pergolas.

func _ready() -> void:
	rng.seed=67319
	make_foliage()
	G.box(self,Vector3(0,-.19,-17),Vector3(42,.65,17),mat("c6bea1",5,.2))
	G.box(self,Vector3(0,-2.7,-18),Vector3(44,4.7,19),mat("a2a48a",2,.22))
	# Two planted banks and a central stair lead up to the garden pavilion.
	terrace(-20,22,-29,-15.7,2.5,-1.4,1.4,-21,"a5ab8e")
	terrace(-23,25,-42,-28,5.1,-1.4,1.4,-35,"a6ac8e")
	stairs(Vector3(0,.17,-10.9),12,.20,.52,2.6)
	stairs(Vector3(0,2.5,-23),13,.20,.5,2.6)
	G.box(self,Vector3(0,2.49,-20.5),Vector3(3,.15,5.8),mat("d1c4a3",5))
	G.box(self,Vector3(0,5.08,-32),Vector3(3,.15,6),mat("d1c4a3",5))
	for row in range(3):
		for column in range(4):
			var x:float=[-14,-7,7,14][column]
			if row==0 and absf(x)<10: continue
			var y:float=[.15,2.5,5.1][row]
			var z:float=-13.2-row*12.2+rng.randf_range(-.5,.5)
			citrus_tree(Vector3(x,y,z),rng.randf_range(.7,.95))
	pergola(Vector3(-8,.15,-11.2),6.5,3.4)
	pergola(Vector3(8,.15,-11.8),6.2,3.5)
	pavilion(Vector3(6.3,5.1,-34))
	fountain(Vector3(-4.6,.15,-12.3))
	for side in [-1,1]:
		for j in range(8):
			var at:=Vector3(side*6.8,.02,-8.5+j*2.25)
			G.box(self,at+Vector3(0,.23,0),Vector3(.66,.46,1.88),mat("b8ac8b",2))
			crown(at+Vector3(0,.55,0),Vector3(.59,.45,.99),"6c8249")
			for i in range(5):
				var flower:=at+Vector3(rng.randf_range(-.26,.26),.84+rng.randf()*.13,rng.randf_range(-.7,.7))
				G.beam(self,flower-Vector3(0,.3,0),flower,.008,mat("5d7848"),.006,6)
				G.sphere(self,flower,Vector3(.045,.11,.045),mat("a398b0"))
		citrus_tree(Vector3(side*8.3,0,5.8),1.13)
		citrus_tree(Vector3(side*8.6,0,-3.3),1.03)
		bench(Vector3(side*6.05,.02,2.8),side*PI/2)
		planter(Vector3(side*5.8,.15,-10),.46,.48,true)
	# Buttresses and irregular planted bays break the long retaining faces.
	for x in [-16.8,-10.2,-3.0,3.0,10.7,18.4]:
		G.box(self,Vector3(x,1.35,-15.52),Vector3(.66,2.7,.42),mat("b9b79a",2))
		G.box(self,Vector3(x,2.74,-15.52),Vector3(.86,.16,.63),mat("d2c7a6",5))
	for row in range(2):
		var y:float=[2.5,5.1][row]; var z:float=[-15.65,-27.95][row]
		for i in range(10):
			var x:float=-17+i*3.8+rng.randf_range(-.9,.9)
			if absf(x)<2: continue
			var length:=rng.randi_range(2,6)
			for j in range(length):
				var at:=Vector3(x+sin(i*2+j*.9)*.32,y-.09-j*.30,z+.12)
				crown(at,Vector3(.34+rng.randf()*.28,.38,.20),"597b48" if i%3 else "7a8d4d")
				if i%3==0 and j<3:
					G.sphere(self,at+Vector3(.12,.05,.16),Vector3(.075,.05,.05),mat("c69d89"))
	for x in [-13.2,-6.8,5.8,15.5]:
		var at:=Vector3(x,.15,-14.9)
		G.box(self,at+Vector3(0,.27,0),Vector3(2.4,.54,.9),mat("bda481",2))
		for j in range(4):
			crown(at+Vector3((j-1.5)*.56,.70,0),Vector3(.56,.47,.54),"68884a")
			G.sphere(self,at+Vector3((j-1.5)*.56,.96,.12),Vector3(.11,.075,.085),mat("d7b274"))
	for i in range(5):
		var p:=Vector3(-20+i*11.0,5.1,-40-rng.randf()*5)
		tree(p,1.2+rng.randf()*.4)
	headland(Vector3(-59,-5,-130),1.1,"789386")
	headland(Vector3(-92,-5,-192),1.5,"99aca0")
	coastal_slope()
	batch_static()

func citrus_tree(p:Vector3,size_scale:float) -> void:
	tree(p,size_scale)
	for i in range(24):
		var angle:=i*2.39996
		var radius:=1.05+rng.randf()*.95
		var at:=p+Vector3(cos(angle)*radius,4.5+rng.randf()*1.25,sin(angle)*radius)*size_scale
		G.sphere(self,at,Vector3(.105,.118,.105)*size_scale,mat("d49d38",0,.12))
		G.beam(self,at+Vector3(0,.1,0)*size_scale,at+Vector3(.02,.18,0)*size_scale,.012,mat("657442"),.006,6)

func pergola(p:Vector3,width:float,depth:float) -> void:
	for x in [-width/2,width/2]:
		for z in [-depth/2,depth/2]:
			G.box(self,p+Vector3(x,1.6,z),Vector3(.20,3.2,.20),mat("aaa47f",6,.19))
			G.box(self,p+Vector3(x,.16,z),Vector3(.38,.32,.38),mat("c6bc9e",2))
	for z in [-depth/2,depth/2]:
		G.box(self,p+Vector3(0,3.25,z),Vector3(width+.6,.19,.20),mat("9d9972",1,.18))
	for j in range(11):
		var x:float=(float(j)/10-.5)*(width+.3)
		G.box(self,p+Vector3(x,3.4,0),Vector3(.13,.16,depth+.7),mat("b8ab80",1,.18))
		if j%2==0: crown(p+Vector3(x,3.5,0),Vector3(.62,.25,depth*.59),"648247")
	for side in [-1,1]:
		for j in range(5): crown(p+Vector3(side*width/2,1+j*.53,depth/2+.07),Vector3(.28,.44,.32),"648247")
	bench(p+Vector3(0,0,-depth*.25))
	for x in [-width*.31,width*.30]: planter(p+Vector3(x,.02,depth*.28),.34,.39,true)

func fountain(p:Vector3) -> void:
	G.beam(self,p,p+Vector3(0,.3,0),1.5,mat("b0b59b",2),1.5,40)
	var basin:=TorusMesh.new(); basin.inner_radius=1.18; basin.outer_radius=1.50; basin.rings=48; basin.ring_segments=12
	G.instance(self,basin,p+Vector3(0,.42,0),mat("cec8a7"))
	G.beam(self,p+Vector3(0,.33,0),p+Vector3(0,.39,0),1.23,mat("729e91",0,.08),1.23,40)
	G.beam(self,p+Vector3(0,.37,0),p+Vector3(0,1.4,0),.28,mat("c4bfa0"),.16,24)
	G.beam(self,p+Vector3(0,1.27,0),p+Vector3(0,1.42,0),.59,mat("d1caaa"),.70,32)
	G.sphere(self,p+Vector3(0,1.57,0),Vector3(.16,.22,.16),mat("a5ad91"))
	# Thin translucent falling arcs remain outside the court's ball silhouette.
	var water:=G.matte(Color(.57,.78,.72,.63)); water.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; water.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for j in range(8):
		var direction:=Vector3(cos(j*TAU/8),0,sin(j*TAU/8))
		for segment in range(8):
			var t:=float(segment)/8; var n:=float(segment+1)/8
			G.beam(self,p+direction*(.5+t*.46)+Vector3(0,1.4-t*t,0),p+direction*(.5+n*.46)+Vector3(0,1.4-n*n,0),.008,water,.008,6)

func pavilion(p:Vector3) -> void:
	G.box(self,p+Vector3(0,.16,0),Vector3(7,.32,5.6),mat("c8c0a0",2))
	for x in [-2.8,2.8]:
		for z in [-2.1,2.1]:
			G.box(self,p+Vector3(x,2.1,z),Vector3(.30,3.9,.30),mat("ddd0ae"))
			G.box(self,p+Vector3(x,3.92,z),Vector3(.55,.19,.55),mat("c9bb97"))
	G.box(self,p+Vector3(0,4.15,0),Vector3(6.9,.30,5.5),mat("e1d5b3"))
	roof(p+Vector3(0,4.32,0),7.3,5.9,1.45)
	G.box(self,p+Vector3(0,1.4,-2.12),Vector3(5.6,2.25,.22),mat("c4c4a4"))
	for x in [-1.5,0,1.5]: window(p+Vector3(x,1.6,-1.98),true)
	G.text(self,"GIARDINO • SOL",p+Vector3(0,3.67,2.25),42,.012,Color("526b56"),true)
	for x in [-2.35,2.35]: planter(p+Vector3(x,.33,1.55),.45,.52,true)
	bench(p+Vector3(0,.32,-1.05))
