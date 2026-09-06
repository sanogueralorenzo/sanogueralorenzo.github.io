extends Node2D
## Deterministic layered coastal illustration, generated with canvas geometry.
var map_index := 0
var variant := 0
var rng := RandomNumberGenerator.new()
var foliage: Texture2D
var grain: Texture2D
const LeafPainter = preload("res://scripts/leaf_painter.gd")

func _ready() -> void:
	var leaf_image:=Image.create(256,256,false,Image.FORMAT_RGBA8)
	leaf_image.fill(Color.TRANSPARENT)
	var seeded:=RandomNumberGenerator.new()
	seeded.seed=73421
	for layer in range(3):
		for i in range(110):
			var angle:=seeded.randf()*TAU
			var radius:=sqrt(seeded.randf())*93
			var center:=Vector2(128,128)+Vector2(cos(angle),sin(angle)*0.82)*radius
			var length:=seeded.randf_range(7,19)
			LeafPainter.paint(leaf_image,center,length,length*seeded.randf_range(0.3,0.55),angle+seeded.randf_range(-1.1,1.1),seeded.randf_range(0.48,0.75) if layer==0 else seeded.randf_range(0.7,1.0),LeafPainter.Profile.POINTED)
	leaf_image.generate_mipmaps()
	foliage=ImageTexture.create_from_image(leaf_image)
	var paper:=Image.create(256,256,false,Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var v:=seeded.randf_range(0.4,0.85)
			paper.set_pixel(x,y,Color(v,v,v,0.11))
	grain=ImageTexture.create_from_image(paper)
	queue_redraw()

const INK := Color("234c51")
const CREAM := Color("fff2d1")

func court(p: Vector2) -> Vector2:
	return Vector2(750.0 + p.x * (66.0 + (p.y + 8.0) * 3.2), 397.0 + (p.y + 8.0) * 24.0)

func poly(points: Array, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func line(a: Vector2, b: Vector2, color: Color, width: float = 2.0) -> void:
	draw_line(a, b, color, width, true)

func _draw() -> void:
	rng.seed = 891 + map_index * 143
	var skies := [Color("83c8dd"), Color("9acecc"), Color("ecb896")]
	var sky: Color = skies[variant]
	for y in range(0, 460, 4):
		draw_rect(Rect2(0, y, 1440, 4), sky.lerp(Color("edf0d8"), float(y) / 610.0))
	# Broad cumulus silhouettes with quiet, cool undersides and irregular brush edges.
	for ci in range(5):
		var base:=Vector2(85+ci*285,172+sin(ci*1.9)*59)
		var points:Array=[]
		for j in range(35):
			var t:=float(j)/34.0
			var dome:=pow(maxf(0,sin(t*PI)),0.45)
			var y:=-dome*(68+12*sin(t*17+ci)+8*sin(t*39+ci*2))
			points.append(base+Vector2(t*270,y))
		for j in range(16,-1,-1):
			var t:=float(j)/16.0
			points.append(base+Vector2(t*270,12+sin(t*PI)*15+sin(t*29+ci)*3))
		poly(points,Color("e0e8df"))
		var lit:Array=[]
		for p in points: lit.append(p+Vector2(-3,-8))
		poly(lit,Color("fbf4de"))
		for j in range(17):
			var at:=base+Vector2(17+j*14,-8+sin(j*.77+ci)*5)
			line(at,at+Vector2(22,2),Color(0.76,0.84,0.82,0.10),4)
	# Ocean and distant headland.
	draw_rect(Rect2(0, 302, 1440, 598), Color("54a5bd"))
	poly([Vector2(0, 343),Vector2(84, 312),Vector2(146, 314),Vector2(218, 293),Vector2(304, 308),Vector2(407, 286),Vector2(523, 334)], Color("8eaead"))
	for i in range(190):
		var p := Vector2(rng.randf_range(0, 1440), rng.randf_range(326, 597))
		line(p, p + Vector2(rng.randf_range(4, 45), 0), Color(0.88, 0.95, 0.84, rng.randf_range(0.12, 0.5)), 1.5)
	for boat in [Vector2(121,365),Vector2(287,342),Vector2(42,448)]:
		poly([boat,boat+Vector2(0,-29),boat+Vector2(-16,0)], CREAM)
		line(boat+Vector2(-20,3),boat+Vector2(8,3),INK,2)
	# Rock facets and broken foam lines carry the cliff down into the water.
	for i in range(11):
		var rock:=Vector2(253-i*22,416+i*31)
		var size:=18.0+i*1.7
		poly([rock+Vector2(-size,7),rock+Vector2(-size*0.8,-12),rock+Vector2(0,-size*0.7),rock+Vector2(size,-6),rock+Vector2(size*0.8,14)],Color("8d9b8e"))
		poly([rock+Vector2(-size*0.8,-12),rock+Vector2(0,-size*0.7),rock+Vector2(size,-6),rock+Vector2(2,3)],Color("b7baa1"))
		for j in range(4):
			var foam:=rock+Vector2(-size-10-j*5,6+j*3)
			line(foam,foam+Vector2(12+j*4,2),Color(0.88,0.96,0.87,0.6-j*0.1),2)
	if map_index == 0: village()
	elif map_index == 1: harbor()
	else: garden()
	# Promenade retaining wall, separate from playable clay.
	poly([Vector2(350, 368), Vector2(1350, 366),Vector2(1440,620),Vector2(60,620)],Color("c2b699"))
	for y in range(397,550,24):
		line(Vector2(250,y),Vector2(1390,y),Color("968f76"),2)
		for x in range(290,1400,55): line(Vector2(x+(y%3)*10,y),Vector2(x+(y%3)*10,y+21),Color("a39a7e"),1)
	# Ground and court.
	poly([Vector2(270,390),Vector2(1240,390),Vector2(1620,900),Vector2(-90,900)],Color("ba956e"))
	poly([court(Vector2(-4.5,-8)),court(Vector2(4.5,-8)),court(Vector2(4.5,8)),court(Vector2(-4.5,8))], Color("cfa276") if map_index != 1 else Color("c6af80"))
	for i in range(5500):
		var p := Vector2(rng.randf_range(0,1440),rng.randf_range(398,900))
		var left := 270.0-(p.y-390)*0.7
		var right := 1240.0+(p.y-390)*0.75
		if p.x > left and p.x < right:
			line(p,p+Vector2(rng.randf_range(1,6),rng.randf_range(-1,1)), Color(0.98,0.85,0.62,rng.randf_range(0.07,0.25)),rng.randf_range(1,3))
	for x in [-4.5,4.5]: line(court(Vector2(x,-8)),court(Vector2(x,8)),CREAM,4)
	for y in [-8.0,-3.0,3.0,8.0]: line(court(Vector2(-4.5,y)),court(Vector2(4.5,y)),Color("f6e4c3"),3)
	# Rail follows the cliff; colorful flowers soften the perimeter.
	for i in range(10):
		var p := Vector2(310-i*31,414+i*44)
		line(p,p+Vector2(0,-48),CREAM,9)
		if i<9: line(p+Vector2(0,-38),p+Vector2(-31,6),CREAM,7)
	for i in range(36):
		var p := Vector2(rng.randf_range(0,240),rng.randf_range(580,890))
		leaf_cluster(p,18,Color("547955"))
		if i%3==0: draw_circle(p+Vector2(0,-12),4,Color("e8aa71"))
	# Benches and planters.
	bench(Vector2(1233,470),1.0)
	bench(Vector2(416,393),0.65)
	for i in range(7):
		var p:=Vector2(1180+i*35,508+i*37)
		poly([p+Vector2(-25,0),p+Vector2(20,0),p+Vector2(15,30),p+Vector2(-20,30)],Color("a78264"))
		leaf_cluster(p,35,Color("537451"))
	# Framing trees and dappled shade.
	tree(Vector2(38,680),3.4)
	tree(Vector2(1394,673),3.55)
	for i in range(220):
		var p := Vector2(rng.randf_range(0,510),rng.randf_range(590,900))
		draw_set_transform(p, -0.5, Vector2(1,0.32))
		draw_circle(Vector2.ZERO,rng.randf_range(5,17),Color(0.18,0.29,0.23,0.17))
		draw_set_transform(Vector2.ZERO)
	# Illustrated foreground tufts.
	for i in range(34):
		var p:=Vector2(rng.randf_range(1230,1440),rng.randf_range(620,900))
		for j in range(4): line(p,p+Vector2(rng.randf_range(-20,20),rng.randf_range(-42,-12)),Color("647b45"),4)
	if grain:
		for gy in range(4):
			for gx in range(6): draw_texture_rect(grain,Rect2(gx*256,gy*256,256,256),false)
	if variant == 2: draw_rect(Rect2(0,0,1440,900),Color(0.96,0.57,0.26,0.07))

func building(p: Vector2, size: Vector2, col: Color, floors: int = 4) -> void:
	poly([p,p+Vector2(size.x,0),p+size,p+Vector2(0,size.y)],col)
	poly([p+Vector2(size.x,0),p+Vector2(size.x+17,-12),p+size+Vector2(17,-12),p+size],col.darkened(0.15))
	draw_rect(Rect2(p+Vector2(0,6),Vector2(size.x,8)),col.darkened(0.17))
	draw_rect(Rect2(p-Vector2(6,8),Vector2(size.x+12,9)),Color("eee0bc"))
	poly([p+Vector2(-7,-8),p+Vector2(size.x*0.48,-27),p+Vector2(size.x+9,-8)],Color("ab9275"))
	line(p+Vector2(-7,-8),p+Vector2(size.x+9,-8),Color("dccba9"),3)
	line(p+Vector2(3,5),p+Vector2(3,size.y),col.lightened(0.18),3)
	for f in range(floors):
		for c in range(int(size.x/31)):
			var w:=p+Vector2(12+c*31,20+f*(size.y-24)/floors)
			draw_rect(Rect2(w+Vector2(2,1),Vector2(22,32)),col.darkened(0.25))
			draw_rect(Rect2(w-Vector2(3,3),Vector2(19,29)),Color("ede0bf"))
			draw_rect(Rect2(w,Vector2(13,23)),Color("49656a"))
			line(w+Vector2(6,0),w+Vector2(6,23),Color("aeb8a8"),1)
			line(w+Vector2(0,12),w+Vector2(13,12),Color("aeb8a8"),1)
			if f%2==0:
				line(w+Vector2(-6,22),w+Vector2(20,22),Color("55676a"),1.2)
				for rail in range(5): line(w+Vector2(-5+rail*6,20),w+Vector2(-5+rail*6,30),Color("4f6465"),0.8)
				line(w+Vector2(-6,31),w+Vector2(21,31),Color("e8d9b6"),3)
			if (f+c)%3==0:
				draw_rect(Rect2(w+Vector2(-6,24),Vector2(26,5)),Color("8f7e63"))
				leaf_cluster(w+Vector2(8,24),9,Color("557b54"))
	for i in range(80):
		var q:=p+Vector2(rng.randf_range(1,size.x-2),rng.randf_range(1,size.y-2))
		line(q,q+Vector2(rng.randf_range(2,9),0),Color(1,0.94,0.73,0.12),2)

func village() -> void:
	poly([Vector2(360,376),Vector2(750,116),Vector2(1200,75),Vector2(1440,380)],Color("a1b291"))
	for i in range(7):
		building(Vector2(699+i*91,126-i*10),Vector2(76,90+(i%3)*12),Color("c8bd9f"),2)
	for i in range(10):
		var p:=Vector2(527+i*87,205-i*13+(i%3)*35)
		building(p,Vector2(82,205+(i%3)*15),[Color("d8c39b"),Color("dfc4a6"),Color("c9bc99")][i%3],4)
	# Central stair street climbing the town.
	poly([Vector2(885,374),Vector2(992,182),Vector2(1021,185),Vector2(956,374)],Color("a79d81"))
	for i in range(16): line(Vector2(889+i*6,369-i*11),Vector2(952+i*4,369-i*11),Color("ded4b4"),2)
	building(Vector2(1048,271),Vector2(260,118),Color("d9cba7"),2)
	poly([Vector2(1040,322),Vector2(1320,322),Vector2(1340,344),Vector2(1025,344)],Color("24484f"))
	draw_string(ThemeDB.fallback_font,Vector2(1125,337),"CAFÉ   •   MAREA",HORIZONTAL_ALIGNMENT_LEFT,-1,12,CREAM)
	for i in [0,1,2,5,6,10,12,13]: tree(Vector2(390+i*66,385+(i%3)*10),0.35+float(i%3)*0.07)
	for i in range(9):
		var p:=Vector2(630+i*73,272-i*7)
		line(p,p-Vector2(0,60),Color("6f795b"),4)
		for j in range(5): leaf_cluster(p-Vector2(0,15+j*11),16-j*2,Color("426953"))

func harbor() -> void:
	poly([Vector2(220,340),Vector2(420,285),Vector2(687,324),Vector2(900,294),Vector2(1110,366)],Color("9aaea0"))
	# Lighthouse, striped fishing houses and masts.
	poly([Vector2(350,337),Vector2(367,194),Vector2(402,194),Vector2(419,337)],Color("eee6cd"))
	poly([Vector2(358,279),Vector2(365,245),Vector2(409,245),Vector2(413,279)],Color("d68e73"))
	draw_rect(Rect2(362,174,45,24),Color("345e63"))
	poly([Vector2(351,175),Vector2(385,150),Vector2(418,175)],Color("bd7965"))
	for i in range(5):
		building(Vector2(820+i*102,268+(i%2)*25),Vector2(93,122),[Color("cf9e85"),Color("d8bd78"),Color("aabca6")][i%3],2)
	for i in range(7):
		var p:=Vector2(480+i*42,371)
		line(p,p-Vector2(0,94+i%3*19),Color("e5ddc1"),2)
		poly([p+Vector2(-20,-4),p+Vector2(21,-4),p+Vector2(12,7),p+Vector2(-13,7)],Color("4d7474"))
	for i in range(12):
		var p:=Vector2(456+i*61,238+sin(i*0.32)*24)
		poly([p,p+Vector2(27,3),p+Vector2(12,24)],Color("e6af6c") if i%2==0 else Color("629391"))

func garden() -> void:
	poly([Vector2(0,340),Vector2(235,263),Vector2(410,286),Vector2(790,178),Vector2(1440,283),Vector2(1440,400)],Color("8aab8c"))
	for i in range(20): tree(Vector2(380+i*55,352+(i%3)*13),0.6+float(i%4)*0.12)
	# Pale stone pergola with a sea view.
	for i in range(7):
		draw_rect(Rect2(633+i*101,250,13,134),Color("dbd4ad"))
		draw_rect(Rect2(627+i*101,249,26,12),CREAM)
	line(Vector2(615,248),Vector2(1295,248),Color("dfd9b6"),12)
	for i in range(20):
		var p:=Vector2(629+i*34,242)
		leaf_cluster(p,26,Color("587b50"))
		if i%3==0:
			for j in range(5): draw_circle(p+Vector2(rng.randf_range(-20,20),rng.randf_range(4,31)),5,Color("c998a5"))
	building(Vector2(1140,137),Vector2(119,112),Color("d8c49e"),3)

func leaf_cluster(p: Vector2, radius: float, col: Color) -> void:
	if foliage==null: return
	# Layered leaf sprays preserve gaps, varied edges and warm light-facing tips.
	for i in range(5):
		var at:=p+Vector2(rng.randf_range(-radius*0.65,radius*0.65),rng.randf_range(-radius*0.45,radius*0.25))
		var size:=radius*rng.randf_range(1.3,1.9)
		draw_texture_rect(foliage,Rect2(at-Vector2.ONE*size*0.5,Vector2.ONE*size),false,col.lightened(rng.randf_range(-0.15,0.18)))

func tree(p: Vector2, s: float) -> void:
	line(p,p+Vector2(17,-156)*s,Color("626657"),14*s)
	line(p+Vector2(-3,0)*s,p+Vector2(14,-156)*s,Color("85806a"),5*s)
	line(p+Vector2(5,0)*s,p+Vector2(22,-156)*s,Color("4c594e"),3*s)
	for bark in range(23):
		var t:=float(bark)/23
		var at:=p+Vector2(17*t+rng.randf_range(-5,4),-156*t)*s
		line(at,at+Vector2(rng.randf_range(-1,2),-rng.randf_range(3,12))*s,Color("4f5c4e"),0.7*s)
	for i in range(5):
		var end:=p+Vector2(-65+i*34,-160-abs(i-2)*13)*s
		line(p+Vector2(6,-70)*s,end,Color("74775a"),6*s)
		leaf_cluster(end,54*s,Color("436e53"))
		leaf_cluster(end+Vector2(-12,-16)*s,36*s,Color("718952"))

func bench(p: Vector2,s:float) -> void:
	for y in [0,7,14]: line(p+Vector2(-34,y)*s,p+Vector2(34,y)*s,Color("977957"),5*s)
	for x in [-26,26]: line(p+Vector2(x,4)*s,p+Vector2(x,29)*s,INK,4*s)
	for y in [-23,-15]: line(p+Vector2(-34,y)*s,p+Vector2(34,y)*s,Color("a98a61"),5*s)
