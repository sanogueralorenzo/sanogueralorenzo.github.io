extends RefCounted
## Original articulated athletes. Coordinates are bones in a hand-drawn local rig.
const INK := Color("293e40")
var canvas: CanvasItem
var skin := Color("dca77b")
var kit := Color("f2cd60")
var trim := Color("fff1cb")
var torso_turn := 0.0

func polygon(points: Array, color: Color, outline: float = 1.8) -> void:
	var ps:=PackedVector2Array(points)
	canvas.draw_colored_polygon(ps,color)
	if outline > 0:
		ps.append(ps[0])
		canvas.draw_polyline(ps,INK,outline,true)

func stroke(a:Vector2,b:Vector2,col:Color,w:float) -> void:
	canvas.draw_line(a,b,INK,w+3,true)
	canvas.draw_line(a,b,col,w,true)
	canvas.draw_circle(a,w*0.5,col)
	canvas.draw_circle(b,w*0.5,col)

func limb(a:Vector2,b:Vector2,c:Vector2,w:float,col:Color) -> void:
	# Tapered muscle masses with a shaded underside, rather than uniform sticks.
	for segment in [[a,b,w,w*0.83],[b,c,w*0.83,w*0.56]]:
		var start:Vector2=segment[0]
		var end:Vector2=segment[1]
		var normal:Vector2=(end-start).normalized().orthogonal()
		var broad:float=segment[2]*0.62
		var narrow:float=segment[3]*0.55
		polygon([start-normal*broad,start+normal*broad,end+normal*narrow,end-normal*narrow],col,1.2)
		polygon([start-normal*broad,start-normal*broad*0.3,end-normal*narrow*0.25,end-normal*narrow],col.darkened(0.18),0)
		canvas.draw_line(start+normal*broad*0.35,end+normal*narrow*0.4,col.lightened(0.16),1.5,true)
	canvas.draw_circle(b,w*0.37,col)

func body_point(p:Vector2) -> Vector2:
	return Vector2(p.x*(1.0-absf(torso_turn)*0.14)+torso_turn*(p.y+60)*0.18,p.y+p.x*torso_turn*0.11)

func body_polygon(points:Array,col:Color,outline:float=1.5) -> void:
	var turned:Array=[]
	for p in points: turned.append(body_point(p))
	polygon(turned,col,outline)

func draw_player(target:CanvasItem,at:Vector2,scale_value:float,data:Dictionary,time:float,selected:bool) -> void:
	canvas=target
	var team:int=data.team
	var id:int=data.id
	skin=[Color("e7b887"),Color("c58d65"),Color("f0c599")][id%3]
	kit=Color("e9b847") if team==0 else Color("1c646c")
	trim=Color("fff1ca") if team==0 else Color("d3eee0")
	var motion:float=data.motion
	var anim:String=data.anim
	var action:float=data.action
	var gaze:Vector2=data.get("gaze",Vector2(0,-1))
	torso_turn=clampf(gaze.x*0.7+(-0.42 if id%3==0 else 0.42),-0.9,0.9)
	if anim=="spike": torso_turn+=sin(action*PI)*0.25
	var jump:=sin(clampf(action,0,1)*PI)*34 if anim in ["spike","block","set"] else 0.0
	var walk:=sin(time*12+id)*minf(motion*0.3,1.0)
	var lean:=clampf(data.velocity.x*0.06,-0.16,0.16)
	if anim=="receive": lean+=sin(action*PI)*0.18
	if anim=="spike": lean-=sin(action*PI)*0.14
	if anim=="set": lean+=sin(action*PI)*0.045
	canvas.draw_set_transform(at-Vector2(0,jump*scale_value),lean,Vector2.ONE*scale_value)
	# Staggered lower body, compression shorts and planted or trailing feet.
	var crouch:=9.0+(sin(action*PI)*14.0 if anim=="receive" else 0.0)
	var hip:=Vector2(-torso_turn*5,-68+crouch)
	var left_knee:=Vector2(-16-walk*10,-36+abs(walk)*8)
	var right_knee:=Vector2(18+walk*9,-39-abs(walk)*4)
	var left_foot:=Vector2(-23-walk*18,-3)
	var right_foot:=Vector2(25+walk*17,-3)
	left_foot.y-=maxf(0,walk)*9
	right_foot.y-=maxf(0,-walk)*9
	if jump>0:
		left_knee+=Vector2(-7,1)
		left_foot+=Vector2(-18,-14)
		right_knee+=Vector2(-3,-1)
		right_foot+=Vector2(-4,-7)
	limb(hip+Vector2(-9,0),left_knee,left_foot,10,skin.darkened(0.08))
	limb(hip+Vector2(10,0),right_knee,right_foot,10,skin)
	stroke(left_knee-Vector2(0,4),left_knee+Vector2(0,4),Color("354b4d"),11)
	stroke(right_knee-Vector2(0,4),right_knee+Vector2(0,4),Color("354b4d"),11)
	for foot in [left_foot,right_foot]:
		stroke(foot+Vector2(0,-5),foot+Vector2(0,1),Color("eee4c8"),9)
		polygon([foot+Vector2(-6,-2),foot+Vector2(5,-2),foot+Vector2(12,4),foot+Vector2(10,8),foot+Vector2(-7,7)],Color("e8e2cc"))
		canvas.draw_line(foot+Vector2(-5,5),foot+Vector2(9,6),Color("546567"),2,true)
		for k in range(3): canvas.draw_line(foot+Vector2(-1+k*2,0),foot+Vector2(-3+k*2,3),INK,0.8,true)
	canvas.draw_set_transform(at-Vector2(0,(jump+22-crouch)*scale_value),lean,Vector2.ONE*scale_value)
	polygon([Vector2(-18,-53),Vector2(18,-53),Vector2(22,-35),Vector2(4,-34),Vector2(0,-44),Vector2(-4,-33),Vector2(-23,-35)],kit.darkened(0.04))
	canvas.draw_line(Vector2(-17,-49),Vector2(-20,-36),trim,3,true)
	canvas.draw_line(Vector2(17,-49),Vector2(20,-36),trim,3,true)
	# Arms lead the gesture. Attack has a cocked elbow then a whip forward.
	var ls:=body_point(Vector2(-17,-84))
	var rs:=body_point(Vector2(17,-84))
	var le:=Vector2(-29,-69)
	var re:=Vector2(30,-70)
	var lh:=Vector2(-33,-56)
	var rh:=Vector2(36,-58)
	if anim=="receive":
		le=Vector2(-23,-65); re=Vector2(25,-65); lh=Vector2(1,-52); rh=Vector2(6,-52)
	elif anim in ["set","block"]:
		le=Vector2(-32,-108); re=Vector2(32,-108); lh=Vector2(-18,-127); rh=Vector2(17,-127)
	elif anim=="spike":
		le=Vector2(-29,-105); lh=Vector2(-36,-121)
		re=Vector2(31,-110); rh=Vector2(15,-129)
		var whip:=smoothstep(0.36,0.72,action)
		re=Vector2(28,-112).lerp(Vector2(38,-99),whip)
		rh=Vector2(12,-135).lerp(Vector2(36,-115),whip)
		if action<0.4:
			rh=rh.lerp(Vector2(-15,-75),1.0-action/0.4)
			re=re.lerp(Vector2(21,-81),1.0-action/0.4)
	elif anim=="celebrate":
		le=Vector2(-32,-105); lh=Vector2(-23,-130); re=Vector2(32,-105); rh=Vector2(26,-129)
	else:
		lh.x+=walk*7; rh.x-=walk*7
	var contact_blend:float=data.get("contact_blend",0.0)
	if contact_blend>0.0 and data.has("contact_target"):
		var local_ball:Vector2=(data.contact_target-(at-Vector2(0,(jump+22-crouch)*scale_value))).rotated(-lean)/scale_value
		if anim=="receive":
			lh=lh.lerp(local_ball+Vector2(-3,8),contact_blend)
			rh=rh.lerp(local_ball+Vector2(3,8),contact_blend)
			le=le.lerp((ls+lh)*0.5+Vector2(-5,6),contact_blend)
			re=re.lerp((rs+rh)*0.5+Vector2(5,6),contact_blend)
		elif anim in ["set","block"]:
			lh=lh.lerp(local_ball+Vector2(-8,10),contact_blend)
			rh=rh.lerp(local_ball+Vector2(8,10),contact_blend)
			le=le.lerp((ls+lh)*0.5+Vector2(-8,0),contact_blend)
			re=re.lerp((rs+rh)*0.5+Vector2(8,0),contact_blend)
		elif anim=="spike":
			rh=rh.lerp(local_ball+Vector2(0,5),contact_blend)
			re=re.lerp((rs+rh)*0.5+Vector2(12,0),contact_blend)
	if contact_blend>0.0:
		# Two bounded bones; a missed ball must remain beyond the hands.
		lh=ls+(lh-ls).limit_length(52.0)
		rh=rs+(rh-rs).limit_length(52.0)
		le=le.lerp(solve_elbow(ls,lh),contact_blend)
		re=re.lerp(solve_elbow(rs,rh),contact_blend)
	# Complete each gesture smoothly before the simulation returns to ready.
	if anim in ["receive","set","block","spike"] and action<0.3:
		var settle:=1.0-smoothstep(0.0,0.3,action)
		le=le.lerp(Vector2(-29,-69),settle)
		re=re.lerp(Vector2(30,-70),settle)
		lh=lh.lerp(Vector2(-33+walk*7,-56),settle)
		rh=rh.lerp(Vector2(36-walk*7,-58),settle)
	limb(ls,le,lh,8,skin.darkened(0.03))
	limb(rs,re,rh,8,skin)
	# Sleeveless jersey, side panels, folds and chest lettering.
	body_polygon([Vector2(-10,-94),Vector2(-22,-86),Vector2(-15,-70),Vector2(-17,-51),Vector2(18,-51),Vector2(15,-73),Vector2(23,-86),Vector2(10,-94),Vector2(0,-89)],trim if team==0 else kit)
	body_polygon([Vector2(-21,-86),Vector2(-15,-69),Vector2(-17,-51),Vector2(-9,-51),Vector2(-10,-86)],kit,0)
	body_polygon([Vector2(21,-86),Vector2(15,-72),Vector2(18,-51),Vector2(10,-51),Vector2(11,-86)],kit,0)
	canvas.draw_line(Vector2(-11,-91),Vector2(0,-87),kit,2,true)
	canvas.draw_line(Vector2(0,-87),Vector2(10,-92),kit,2,true)
	canvas.draw_line(Vector2(-5,-56),Vector2(6,-59),kit.darkened(0.1),1,true)
	body_polygon([Vector2(9,-87),Vector2(13,-72),Vector2(15,-52),Vector2(4,-53),Vector2(8,-66),Vector2(3,-77)],kit.darkened(0.17) if team==1 else Color("d1c8a0"),0)
	for crease in [[Vector2(-12,-65),Vector2(-3,-68)],[Vector2(3,-74),Vector2(11,-69)],[Vector2(-7,-55),Vector2(4,-57)]]:
		canvas.draw_line(body_point(crease[0]),body_point(crease[1]),kit.darkened(0.18),1.1,true)
	canvas.draw_string(ThemeDB.fallback_font,body_point(Vector2(-12,-77)),"SOL" if team==0 else "TIDE",HORIZONTAL_ALIGNMENT_LEFT,-1,6,INK if team==0 else trim)
	canvas.draw_string(ThemeDB.fallback_font,body_point(Vector2(-6,-59)),str([7,3,11][id%3]),HORIZONTAL_ALIGNMENT_LEFT,-1,18,INK if team==0 else trim)
	draw_face(id,team,anim,data.get("gaze",Vector2(0,-1)))
	# Fingers keep raised hands legible at gameplay scale.
	for hand in [lh,rh]:
		canvas.draw_circle(hand,4,skin)
		if anim in ["set","block","spike","celebrate"]:
			for f in range(4):
				var finger:Vector2=hand+Vector2(-4+f*2,-2)
				stroke(finger,finger+Vector2((f-1.5)*1.2,-6+absf(f-1.5)),skin,1.8)
	canvas.draw_set_transform(Vector2.ZERO)
	if selected:
		var top:=at+Vector2(0,-(172+jump-crouch)*scale_value)
		canvas.draw_colored_polygon(PackedVector2Array([top+Vector2(-8,-6),top+Vector2(8,-6),top+Vector2(0,7)]),Color("ffe28a"))

func draw_face(id:int,team:int,anim:String,gaze:Vector2) -> void:
	# Neck, angular cheek and ear silhouettes.
	stroke(Vector2(0,-91),Vector2(0,-101),skin,9)
	var face_turn:=clampf(gaze.x*0.8+torso_turn*0.35,-1,1)
	var head:=Vector2(face_turn*5+(1 if team==0 else -1),-111)

	canvas.draw_circle(head+Vector2(-12,1),4,skin.darkened(0.1))
	canvas.draw_circle(head+Vector2(12,1),4,skin)
	polygon([head+Vector2(-12,-9),head+Vector2(-8,-15),head+Vector2(8,-15),head+Vector2(13,-7),head+Vector2(10,8),head+Vector2(3,14),head+Vector2(-5,12),head+Vector2(-11,5)],skin)
	polygon([head+Vector2(-11,-4),head+Vector2(-6,9),head+Vector2(2,13),head+Vector2(-5,12),head+Vector2(-11,5)],skin.darkened(0.12),0)
	# Eyes are white shapes with dark iris; brows change with action.
	for side in [-1,1]:
		var eye:=head+Vector2(side*5+face_turn*2,-1+side*face_turn)
		polygon([eye+Vector2(-3,-2),eye+Vector2(3,-2),eye+Vector2(2,2),eye+Vector2(-2,2)],Color("fff8df"),0.6)
		canvas.draw_circle(eye+Vector2(clampf(gaze.x,-1,1)*1.1,clampf(gaze.y,-1,1)*0.8),1.5,Color("354f43"))
		canvas.draw_circle(eye+Vector2(-0.4,-0.8),0.5,Color.WHITE)
		canvas.draw_line(eye+Vector2(-3,-5-side),eye+Vector2(3,-5+side),INK,1.7,true)
	canvas.draw_line(head+Vector2(1+gaze.x*2,1),head+Vector2(2+gaze.x*3,5),skin.darkened(0.35),1,true)
	if anim in ["spike","celebrate","block"]:
		polygon([head+Vector2(-3,8),head+Vector2(4,7),head+Vector2(2,11),head+Vector2(-1,11)],Color("854d3e"),0.7)
	elif id==1:
		canvas.draw_polyline(PackedVector2Array([head+Vector2(-3,7),head+Vector2(0,9),head+Vector2(4,7)]),INK,0.9,true)
	else: canvas.draw_line(head+Vector2(-2,8),head+Vector2(3,8),INK,0.9,true)
	# Asymmetric anime hair silhouette, unique for each teammate.
	var hair:Color=[Color("343e38"),Color("754d34"),Color("3d4853")][id%3]
	var hp:Array=[Vector2(-13,-3),Vector2(-16,-11),Vector2(-11,-13),Vector2(-17,-18),Vector2(-7,-17),Vector2(-9,-23),Vector2(-1,-19),Vector2(5,-25),Vector2(7,-19),Vector2(17,-21),Vector2(13,-13),Vector2(19,-10),Vector2(13,-6),Vector2(10,0),Vector2(7,-9),Vector2(2,-5),Vector2(0,-12),Vector2(-5,-6),Vector2(-6,-12),Vector2(-11,-4)]
	if id%3==1:
		hp=[Vector2(-13,-3),Vector2(-15,-10),Vector2(-11,-13),Vector2(-14,-19),Vector2(-6,-16),Vector2(-3,-25),Vector2(3,-19),Vector2(10,-22),Vector2(10,-15),Vector2(18,-13),Vector2(13,-8),Vector2(12,-2),Vector2(8,-8),Vector2(4,-5),Vector2(1,-11),Vector2(-3,-4),Vector2(-6,-9),Vector2(-10,-3)]
	elif id%3==2:
		hp=[Vector2(-13,0),Vector2(-15,-10),Vector2(-10,-17),Vector2(-3,-19),Vector2(4,-20),Vector2(12,-17),Vector2(16,-10),Vector2(12,-2),Vector2(8,-7),Vector2(4,-5),Vector2(6,-12),Vector2(-1,-6),Vector2(-4,-2),Vector2(-4,-10),Vector2(-10,-4)]
	for j in range(hp.size()):
		if id==1: hp[j]=Vector2(hp[j].x*1.07,hp[j].y*0.88)
		if id==2: hp[j]=Vector2(hp[j].x*0.95,hp[j].y*0.72+2)
		hp[j]+=head
	polygon(hp,hair)
	canvas.draw_line(head+Vector2(-7,-16),head+Vector2(-2,-12),hair.lightened(0.18),2,true)
	canvas.draw_line(head+Vector2(5,-18),head+Vector2(8,-13),hair.lightened(0.2),2,true)

func draw_portrait(target:CanvasItem,p:Vector2,id:int,chosen:bool) -> void:
	canvas=target
	torso_turn=0.0
	skin=[Color("e7b887"),Color("c58d65"),Color("f0c599")][id]
	kit=Color("e9b847")
	trim=Color("fff1ca")
	canvas.draw_set_transform(p+Vector2(0,111*1.45),0,Vector2.ONE*1.45)
	polygon([Vector2(-21,-68),Vector2(-20,-87),Vector2(-8,-94),Vector2(8,-94),Vector2(21,-87),Vector2(22,-68)],trim)
	polygon([Vector2(-20,-87),Vector2(-14,-83),Vector2(-12,-68),Vector2(-21,-68)],kit,0)
	polygon([Vector2(20,-87),Vector2(14,-83),Vector2(12,-68),Vector2(22,-68)],kit,0)
	draw_face(id,0,"celebrate" if chosen else "ready",Vector2(0.4,-0.1))
	canvas.draw_set_transform(Vector2.ZERO)

func solve_elbow(shoulder:Vector2,wrist:Vector2) -> Vector2:
	var distance:=maxf(0.01,shoulder.distance_to(wrist))
	var direction:Vector2=(wrist-shoulder)/distance
	var along:=clampf((distance*distance+28.0*28.0-26.0*26.0)/(2.0*distance),0,28)
	var perpendicular:=Vector2(-direction.y,direction.x)
	if perpendicular.x*signf(shoulder.x)<0: perpendicular=-perpendicular
	return shoulder+direction*along+perpendicular*sqrt(maxf(0,28.0*28.0-along*along))

func draw_shadow(target:CanvasItem,at:Vector2,scale_value:float,data:Dictionary,time:float,clay:Color) -> void:
	var action:float=data.action
	var anim:String=data.anim
	var jump:=sin(clampf(action,0,1)*PI)*34 if anim in ["spike","block","set"] else 0.0
	var walk:=sin(time*12+data.id)*minf(data.motion*0.3,1.0)
	var hip:=Vector2(0,-62-jump)
	var chest:=Vector2(0,-102-jump)
	var left_hand:=Vector2(-33,-76-jump)
	var right_hand:=Vector2(36,-78-jump)
	if anim in ["set","block","spike","celebrate"]:
		var lift:=smoothstep(0.0,0.3,action)
		left_hand=left_hand.lerp(Vector2(-23,-150-jump),lift)
		right_hand=right_hand.lerp(Vector2(23,-151-jump),lift)
	elif anim=="receive":
		left_hand=Vector2(1,-75); right_hand=Vector2(6,-75)
	var col:=clay.lerp(Color(0.17,0.25,0.23),0.23)
	for bone in [[hip,Vector2(-23-walk*18,-jump),12.0],[hip,Vector2(25+walk*17,-jump),12.0],[hip,chest,26.0],[chest,Vector2(0,-137-jump),12.0],[chest,left_hand,8.0],[chest,right_hand,8.0]]:
		target.draw_line(shadow_point(at,bone[0],scale_value),shadow_point(at,bone[1],scale_value),col,bone[2]*scale_value,true)
		target.draw_circle(shadow_point(at,bone[0],scale_value),bone[2]*scale_value*0.5,col)
		target.draw_circle(shadow_point(at,bone[1],scale_value),bone[2]*scale_value*0.5,col)
	target.draw_circle(shadow_point(at,Vector2(0,-137-jump),scale_value),10*scale_value,col)

func shadow_point(at:Vector2,bone:Vector2,scale_value:float) -> Vector2:
	return at+Vector2(bone.x*0.63-bone.y*0.49,-bone.y*0.27+bone.x*0.07)*scale_value
