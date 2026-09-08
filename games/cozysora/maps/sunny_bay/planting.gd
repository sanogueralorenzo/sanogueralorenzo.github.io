extends RefCounted
## Daan's shaded neighborhood garden and Seabreeze's informal coastal planting.
var map
var g
var rng=RandomNumberGenerator.new()
func build(world,geometry) -> void:
	map=world;g=geometry;rng.seed=90271
	for p in [Vector2(-48,6),Vector2(-29,9),Vector2(12,13),Vector2(35,14),Vector2(-33,35),Vector2(12,39),Vector2(-32,62),Vector2(-10,76),Vector2(21,71),Vector2(2,85),Vector2(33,88),Vector2(-17,92),Vector2(-47,87),Vector2(43,65)]:tree(map.point(p.x,p.y),rng.randf_range(6,8),false)
	for p in [Vector2(-31,18),Vector2(32,34),Vector2(-29,51),Vector2(-37,91),Vector2(28,92),Vector2(51,43),Vector2(-54,57)]:tree(map.point(p.x,p.y),rng.randf_range(7,10),true)
	for i in range(90):
		var p=Vector2(rng.randf_range(-61,61),rng.randf_range(6,132))
		if map.coast_distance(p.x,p.y)<3 or map.on_path(p,3) or _in_plot(p,3) or p.distance_to(Vector2(3,68))<13:continue
		if absf(p.x)<43 and p.y<100:continue
		tree(map.point(p.x,p.y),rng.randf_range(4.5,7),i%3==0)
	for i in range(1250):
		var p=Vector2(rng.randf_range(-66,66),rng.randf_range(3,138))
		if map.coast_distance(p.x,p.y)<1.3 or map.on_path(p,.8) or _in_plot(p,1.8) or Vector2((p.x-3)/9,(p.y-68)/7).length()<1:continue
		var at=map.point(p.x,p.y)
		g.add("leaf",at+Vector3.UP*.35,Vector3(rng.randf_range(.7,1.8),rng.randf_range(.6,1.3),1.2),["70874e","8b9758","587d53"][i%3])
		if i%4==0:
			for j in range(3):g.add("sphere",at+Vector3(rng.randf_range(-.3,.3),.6,rng.randf_range(-.3,.3)),Vector3(.13,.16,.13),["e4cf8b","d9bba8","e5d9b4"][i%3])
	# Reeds are clustered at the shallow bank, clear of the walking loop.
	for i in range(60):
		var a=rng.randf_range(0,TAU)
		var p=map.point(3+cos(a)*7.5,68+sin(a)*5.1)
		g.beam(p,p+Vector3(.1,rng.randf_range(.45,.85),.1),.015,"7f9559")

func _in_plot(p: Vector2,margin: float) -> bool:
	for plot in map.architecture.PLOTS:
		if absf(p.x-plot[0])<plot[2]*.5+margin and absf(p.y-plot[1])<plot[3]*.5+margin+1:return true
	return false

func tree(p: Vector3,h: float,cypress: bool) -> void:
	var lean=Vector3(.24,0,-.12)
	g.branch(p,p+Vector3.UP*h*.65+lean,h*.035,"8c8263")
	for i in range(6):
		var angle=i*2.4
		var spread=h*(.1 if cypress else .31)
		var tip=p+Vector3(cos(angle)*spread,h*(.48+i*.067),sin(angle)*spread)+lean
		g.branch(p+Vector3.UP*h*(.38+i*.055),tip,h*.015,"8c8263")
		for j in range(13):
			var a=rng.randf()*TAU
			var r=sqrt(rng.randf())*h*(.1 if cypress else .21)
			var at=tip+Vector3(cos(a)*r,rng.randf_range(-.3,.3),sin(a)*r)
			var size=h*rng.randf_range(.16,.25)
			g.add("leaf",at,Vector3(size,size*(1.5 if cypress else .75),size),["456e40","5b7d43","718944"][j%3],Vector3(0,a,0))
