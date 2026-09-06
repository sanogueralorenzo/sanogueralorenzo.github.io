extends Node3D
## Articulated, dimensional original athlete. All geometry is generated here.
const G=preload("res://scripts/three_d/geometry.gd")
var identity:=0
var team:=0
var torso:Node3D
var head:Node3D
var upper_arms:Array[MeshInstance3D]=[]
var forearms:Array[MeshInstance3D]=[]
var thighs:Array[MeshInstance3D]=[]
var calves:Array[MeshInstance3D]=[]
var shorts:Array[MeshInstance3D]=[]
var pads:Array[MeshInstance3D]=[]
var hands:Array[Node3D]=[]
var shoes:Array[Node3D]=[]
var brows:Array[Node3D]=[]
var eyes:Array[Node3D]=[]
var expression_time:=0.0
var elbow_joints:Array[MeshInstance3D]=[]
var feet_yaw:=[0.0,0.0]
var swing_yaw:=[0.0,0.0]
var turn_step:=[0.0,0.0]
var airborne:=false
var jump_phase:=0.0
var jump_amplitude:=0.0
var takeoff_feet:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var mouth:MeshInstance3D
var skin:Material
var cloth:Material
var dark:Material
var teeth:MeshInstance3D
var phase:=0.0
var feet_world:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var swing_start:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var swinging:=[false,false]
var initialized:=false
var contact_error:=0.0
var contact_anchor:=Vector3.ZERO
var missed_dig:=false
var hand_world:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO]
var previous_position:=Vector3.ZERO

func ink_pass() -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=preload("res://shaders/three_d/ink.gdshader")
	return material

func inked(color:Color) -> StandardMaterial3D:
	var material:=G.matte(color)
	material.next_pass=ink_pass()
	return material

func build(number:int,side:int) -> void:
	identity=number%3
	team=side
	skin=ShaderMaterial.new()
	skin.shader=preload("res://shaders/three_d/skin.gdshader")
	skin.set_shader_parameter("skin_color",[Color("c17f6b"),Color("9e5846"),Color("d48f78")][identity])
	skin.next_pass=ink_pass()
	cloth=ShaderMaterial.new()
	cloth.shader=preload("res://shaders/three_d/uniform.gdshader")
	cloth.set_shader_parameter("base_color",Color("f6e8c4") if team==0 else Color("176773"))
	cloth.set_shader_parameter("panel_color",Color("dba93a") if team==0 else Color("114d5a"))
	cloth.next_pass=ink_pass()
	var gold:=ShaderMaterial.new()
	gold.shader=preload("res://shaders/three_d/uniform.gdshader")
	gold.set_shader_parameter("base_color",Color("d29b2c") if team==0 else Color("174b59"))
	gold.set_shader_parameter("panel_color",Color("eddaaa") if team==0 else Color("b9cdc4"))
	gold.set_shader_parameter("shorts",true)
	gold.next_pass=ink_pass()
	var trim:=G.matte(Color("cf9c2e") if team==0 else Color("ceddd4"))
	dark=G.matte(Color("24383b"))
	torso=Node3D.new()
	add_child(torso)
	var shirt_sections:=[Vector3(-0.025,0.175,0.118),Vector3(0.05,0.177,0.123),Vector3(0.18,0.158,0.108),Vector3(0.29,0.185,0.126),Vector3(0.35,0.205,0.129),Vector3(0.44,0.202,0.118),Vector3(0.48,0.191,0.110),Vector3(0.505,0.165,0.098),Vector3(0.54,0.093,0.08)]
	# Skin beneath the sleeveless opening joins chest, deltoid and upper arm.
	G.instance(torso,G.profile([Vector3(0.27,0.177,0.105),Vector3(0.40,0.208,0.118),Vector3(0.47,0.210,0.085),Vector3(0.51,0.130,0.080)],32),Vector3.ZERO,skin)
	G.instance(torso,jersey_mesh(shirt_sections),Vector3.ZERO,cloth)
	# Sewn trim follows the actual cutout on the garment, not a moving arm band.
	for side_sign in [-1,1]:
		for depth_sign in [-1,1]:
			for k in range(3,7):
				var a:Vector3=shirt_sections[k]
				var b:Vector3=shirt_sections[k+1]
				G.beam(torso,Vector3(side_sign*a.y*0.809,a.x,depth_sign*a.z*0.588),Vector3(side_sign*b.y*0.809,b.x,depth_sign*b.z*0.588),0.0035,trim,0.0035,8)
		for row in [3,7]:
			var section:Vector3=shirt_sections[row]
			for j in range(8):
				var angle_a:=deg_to_rad(54+j*9)
				var angle_b:=deg_to_rad(54+(j+1)*9)
				G.beam(torso,Vector3(side_sign*sin(angle_a)*section.y,section.x,cos(angle_a)*section.z),Vector3(side_sign*sin(angle_b)*section.y,section.x,cos(angle_b)*section.z),0.0035,trim,0.0035,8)
	# The collar is a thin closed cloth edge following the neck opening.
	G.instance(torso,G.profile([Vector3(0.531,0.101,0.086),Vector3(0.545,0.101,0.086),Vector3(0.547,0.089,0.075),Vector3(0.531,0.089,0.075)],32),Vector3.ZERO,trim)
	G.instance(torso,G.profile([Vector3(-0.055,0.177,0.121),Vector3(0.008,0.174,0.120)]),Vector3.ZERO,gold)
	var ink:=Color("425048") if team==0 else Color("f5e8c8")
	for back in [false,true]:
		var z:=0.135 if back else -0.143
		G.text(torso,str([7,3,11][identity]),Vector3(0,0.25,z),88,0.0027,ink,back)
		G.text(torso,["REN","KAI","JUN"][identity] if back else "SOL" if team==0 else "TIDE",Vector3(0,0.405,z-0.003 if not back else z),28,0.0019,ink,back)
	G.beam(torso,Vector3(0,0.51,0),Vector3(0,0.625,0),0.067,skin,0.060,16)
	head=Node3D.new()
	torso.add_child(head)
	head.position=Vector3(0,0.68,-0.012)
	head.scale=Vector3([0.97,1.04,0.94][identity],[1.0,0.98,1.035][identity],1.0)
	build_face()
	for side_sign in [-1,1]:
		elbow_joints.append(G.sphere(self,Vector3.ZERO,Vector3(0.041,0.043,0.041),skin))
		upper_arms.append(G.instance(self,G.profile([Vector3(-0.12,0.001,0.001),Vector3(-0.06,0.047,0.049),Vector3(0,0.060,0.062),Vector3(0.15,0.066,0.063),Vector3(0.38,0.061,0.057),Vector3(0.66,0.051,0.047),Vector3(1,0.038,0.04)],16),Vector3.ZERO,skin))
		forearms.append(G.instance(self,G.profile([Vector3(0,0.039,0.041),Vector3(0.30,0.046,0.042),Vector3(0.75,0.032,0.029),Vector3(1,0.024,0.025)],16),Vector3.ZERO,skin))
		thighs.append(G.instance(self,G.profile([Vector3(0,0.080,0.089),Vector3(0.27,0.091,0.093),Vector3(0.70,0.068,0.074),Vector3(1,0.051,0.053)],18),Vector3.ZERO,skin))
		calves.append(G.instance(self,G.profile([Vector3(0,0.052,0.054),Vector3(0.25,0.061,0.065),Vector3(0.61,0.047,0.054),Vector3(1,0.029,0.036)],18),Vector3.ZERO,skin))
		shorts.append(G.instance(self,G.profile([Vector3(0,0.107,0.120),Vector3(0.55,0.118,0.125),Vector3(1,0.110,0.108)],18),Vector3.ZERO,gold))
		pads.append(G.instance(self,G.profile([Vector3(0,0.060,0.064),Vector3(0.35,0.067,0.072),Vector3(0.75,0.065,0.067),Vector3(1,0.057,0.061)],18),Vector3.ZERO,dark))
		var hand:=Node3D.new()
		add_child(hand)
		hands.append(hand)
		G.sphere(hand,Vector3(0,0.043,0),Vector3(0.039,0.058,0.022),skin)
		for finger in range(4):
			var x:float=(finger-1.5)*0.018
			var length:float=[0.071,0.086,0.079,0.059][finger]
			G.beam(hand,Vector3(x,0.071,0),Vector3(x*1.18,0.071+length,-0.010),0.009,skin,0.006,7)
		G.beam(hand,Vector3(-side_sign*0.034,0.025,0),Vector3(-side_sign*0.061,0.075,-0.006),0.012,skin,0.007,7)
		var shoe:=Node3D.new()
		add_child(shoe)
		shoes.append(shoe)
		var rubber:=G.matte(Color("d6d5c4"))
		G.sphere(shoe,Vector3(0,-0.022,-0.048),Vector3(0.067,0.025,0.144),rubber)
		G.sphere(shoe,Vector3(0,0.018,-0.043),Vector3(0.062,0.057,0.132),G.matte(Color("eee7d5")))
		G.beam(shoe,Vector3(0,0.035,0.023),Vector3(0,0.115,0.023),0.038,G.matte(Color("efeadc")),0.037,16)
		for lace in range(4):
			G.beam(shoe,Vector3(-0.026,0.066,-0.035-lace*0.018),Vector3(0.026,0.067,-0.047-lace*0.018),0.003,dark,0.003,6)
		G.beam(shoe,Vector3(side_sign*0.058,0.025,-0.067),Vector3(side_sign*0.058,0.047,0.008),0.006,trim,0.005,6)

	# Merge geometry only within rigid articulated parts; joints remain independent.
	G.merge_static(torso)
	G.merge_static(head,[mouth,teeth])
	for eye in eyes: G.merge_static(eye)
	for hand in hands: G.merge_static(hand)
	for shoe in shoes: G.merge_static(shoe)

func build_face() -> void:
	# Shaped jaw, cheek, temple, brow and skull sections; no spherical mannequin head.
	G.instance(head,sculpt_head(),Vector3.ZERO,skin)
	var white:=G.matte(Color("fff7e5"))
	var iris:=G.matte([Color("47523b"),Color("774b2d"),Color("3f5960")][identity])
	for side_sign in [-1,1]:
		G.sphere(head,Vector3(side_sign*0.115,-0.012,0),Vector3(0.014,0.028,0.015),skin)
		var eye_x:float=side_sign*0.055
		var eye:=Node3D.new()
		head.add_child(eye)
		eyes.append(eye)
		G.instance(eye,eye_patch(eye_x),Vector3.ZERO,white)
		var eye_z:=face_surface(eye_x)-0.003
		var eyeball:=G.sphere(eye,Vector3(eye_x,0.021,eye_z),Vector3(0.009,0.011,0.002),iris)
		eyeball.rotation.y=-side_sign*0.42
		var pupil:=G.sphere(eye,Vector3(eye_x,0.021,eye_z-0.002),Vector3(0.004,0.008,0.001),dark)
		pupil.rotation.y=-side_sign*0.42
		G.sphere(eye,Vector3(eye_x-0.003,0.025,eye_z-0.003),Vector3(0.002,0.003,0.001),white)
		# Thin curved lids seal the sclera into the shaped cheek and brow plane.
		var lid_points:Array=[]
		for point in [Vector2(-0.029,0.018),Vector2(-0.013,0.030),Vector2(0.010,0.030),Vector2(0.028,0.021)]:
			lid_points.append(Vector3(eye_x+point.x,0.018+(point.y-0.018)*[0.95,1.22,1.03][identity],face_surface(eye_x+point.x)-0.002))
		for k in range(3): G.beam(eye,lid_points[k],lid_points[k+1],0.0028,dark,0.002,7)
		var brow:=Node3D.new()
		head.add_child(brow)
		brow.position=Vector3(eye_x,[0.048,0.056,0.050][identity],face_surface(eye_x)-0.003)
		brow.rotation.y=-side_sign*0.42
		G.beam(brow,Vector3(-0.027,0.002,0),Vector3(0.027,-side_sign*0.006,0),0.0045,dark,0.0025,8)
		brows.append(brow)
	# The nose bridge and tip are sculpted into the facial mesh, not attached balls.
	var lip:=G.matte(Color("8f5747"))
	mouth=G.instance(head,lip_curve(),Vector3(0,-0.078,-0.083),lip)
	mouth.scale=Vector3(1,0.007,1)
	teeth=G.sphere(head,Vector3(0,-0.077,-0.087),Vector3(0.018,0.0025,0.0015),white)
	teeth.visible=false
	var hair_color:Color=[Color("362f27"),Color("775036"),Color("26373d")][identity]
	var hair:=inked(hair_color)
	var hair_shades:=[hair,inked(hair_color.lightened(0.03)),inked(hair_color.lightened(0.06))]
	G.instance(head,G.profile([Vector3(0.070,0.119,0.102),Vector3(0.103,0.118,0.104),Vector3(0.155,0.091,0.081),Vector3(0.186,0.025,0.026),Vector3(0.190,0.001,0.001)],32,0.008),Vector3.ZERO,hair)
	var rng:=RandomNumberGenerator.new()
	rng.seed=901+identity*101
	# Authored asymmetric groups, rather than a radial crown of equal spikes.
	var tips:=[Vector3(-0.145,0.140,-0.045),Vector3(-0.115,0.210,0.018),Vector3(-0.043,0.242,-0.018),Vector3(0.030,0.225,-0.060),Vector3(0.130,0.205,-0.015),Vector3(0.177,0.125,0.010),Vector3(0.120,0.090,0.100),Vector3(0.040,0.182,0.147),Vector3(-0.052,0.205,0.140),Vector3(-0.149,0.120,0.086),Vector3(0.082,0.180,0.070),Vector3(-0.071,0.190,-0.093)]
	for i in range(tips.size()):
		var tip:Vector3=tips[i]
		if identity==1: tip.y=0.075+(tip.y-0.075)*0.73; tip.x*=0.92
		if identity==2: tip.x+=0.030; tip.y=0.075+(tip.y-0.075)*0.65
		var root:=Vector3(tip.x*0.48,0.108,tip.z*0.48)
		var middle:=root.lerp(tip,0.58)+Vector3(-0.008,0.024,0)
		G.instance(head,G.lock_mesh([root,middle,tip],0.041+(i%3)*0.004,0.025),Vector3.ZERO,hair_shades[rng.randi_range(0,2)])
	for i in range(7):
		var x:float=(i-3)*0.033
		var root:=Vector3(x,0.112-absf(x)*0.14,-0.070)
		var tip:=Vector3(x+(-0.022 if identity==2 else 0.014*sin(i)),[[0.030,0.067,0.081,0.052,0.098,0.070,0.038],[0.070,0.088,0.090,0.083,0.070,0.089,0.050],[0.022,0.035,0.060,0.085,0.108,0.084,0.049]][identity][i],-0.113)
		G.instance(head,G.lock_mesh([root,root.lerp(tip,0.45)+Vector3(0,0.016,-0.015),tip],0.027,0.020),Vector3.ZERO,hair)

func jersey_mesh(sections:Array) -> ArrayMesh:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for row in range(sections.size()-1):
		for j in range(40):
			if row>=3 and row<7 and absf(sin(TAU*(j+0.5)/40))>0.82: continue
			for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				var ring:Vector3=sections[row+corner.y]
				var angle:=TAU*float(j+corner.x)/40
				st.set_uv(Vector2(float(j+corner.x)/40,float(row+corner.y)/(sections.size()-1)))
				var rumple:float=(sin(angle*9+.7)*.004+sin(angle*5+ring.x*12)*.002)*exp(-pow((ring.x-.07)/.11,2))
				st.add_vertex(Vector3(sin(angle)*(ring.y+rumple),ring.x,cos(angle)*(ring.z+rumple)))
	st.generate_normals()
	return st.commit()

func sculpt_head() -> ArrayMesh:
	var sections:=[Vector3(-0.116,0.038,0.046),Vector3(-0.102,0.068,0.065),Vector3(-0.073,0.092,0.084),Vector3(-0.055,0.103,0.090),Vector3(-0.035,0.112,0.094),Vector3(-0.015,0.115,0.096),Vector3(0.006,0.116,0.099),Vector3(0.030,0.117,0.102),Vector3(0.055,0.116,0.101),Vector3(0.085,0.106,0.095),Vector3(0.118,0.090,0.080),Vector3(0.146,0.055,0.049),Vector3(0.160,0.001,0.001)]
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for row in range(sections.size()-1):
		for column in range(64):
			for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
				var ring:Vector3=sections[row+corner.y]
				var angle:=TAU*float(column+corner.x)/64
				var x:=sin(angle)*ring.y
				var y:=ring.x
				var z:=cos(angle)*ring.z
				if cos(angle)<-0.6:
					var nose:=0.027*exp(-x*x/0.00024)*exp(-pow(y+0.036,2)/0.00036)+0.008*exp(-x*x/0.00018)*exp(-pow(y-0.010,2)/0.001)
					var cheek:=0.004*exp(-pow(absf(x)-0.062,2)/0.00035)*exp(-pow(y+0.033,2)/0.0006)
					z-=nose+cheek
				st.add_vertex(Vector3(x,y,z))
	st.generate_normals()
	return st.commit()

func lip_curve() -> ArrayMesh:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var a:=TAU*float(i)/24
		var b:=TAU*float(i+1)/24
		for point in [Vector2.ZERO,Vector2(cos(a),sin(a)),Vector2(cos(b),sin(b))]:
			st.set_normal(Vector3(0,0,-1))
			var smile:float=0.30*point.x*point.x if identity!=2 else 0.10*point.x
			st.add_vertex(Vector3(point.x*0.024,point.y+smile,-0.002*sqrt(maxf(0,1-point.x*point.x))+absf(point.y)*0.005+absf(point.x)*0.003))
	return st.commit()

func face_surface(x:float) -> float:
	return -0.101*sqrt(maxf(0.01,1.0-pow(x/0.117,2)))

func eye_patch(center_x:float) -> ArrayMesh:
	var outline:=[Vector2(-0.029,0),Vector2(-0.014,-0.009),Vector2(0.012,-0.008),Vector2(0.028,0.003),Vector2(0.010,0.012),Vector2(-0.013,0.012)]
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outline.size()):
		for point in [Vector2.ZERO,outline[i],outline[(i+1)%outline.size()]]:
			var x:float=center_x+point.x
			st.set_normal(Vector3(x*3,0,-1).normalized())
			st.add_vertex(Vector3(x,0.018+point.y*[0.95,1.22,1.03][identity],face_surface(x)-0.0015))
	return st.commit()

func update_pose(data:Dictionary,world_position:Vector3,ball_position:Vector3,delta:float,playing:bool,facing_target:Vector3,real_ball:Vector3=Vector3.INF) -> void:
	contact_anchor=ball_position
	missed_dig=data.get("miss_attempt",false)
	var teleport:=not initialized or previous_position.distance_to(world_position)>2.8
	position=world_position
	previous_position=world_position
	var velocity:=Vector3(data.velocity.x,0,data.velocity.y)
	var toward:Vector3=facing_target-world_position
	toward.y=0
	if toward.length()<0.25 or not playing: toward=Vector3(0,0,-1 if team==0 else 1)
	var yaw:=atan2(-toward.x,-toward.z)
	var action:float=clampf(data.action,0,1)
	var animation:String=data.anim
	var windup:=sin(action*PI)
	if animation in ["spike","set","block"]:
		jump_phase=action
		jump_amplitude=0.53 if animation=="spike" else 0.42 if animation=="set" else 0.78
	else:
		# A rebound may ask for a dig while the hitter is still landing.
		# Upper-body action can change; the airborne trajectory remains continuous.
		jump_phase=maxf(0,jump_phase-delta*1.6)
	if teleport: jump_phase=0
	var jump:=sin(jump_phase*PI)*jump_amplitude
	rotation.y=yaw if teleport else lerp_angle(rotation.y,yaw,minf(1,delta*(4 if jump>0.05 else 9)))
	var contact:float=data.get("contact_blend",0.0)
	var ball_local:=to_local(ball_position)
	var horizontal:=Vector3(ball_local.x,0,ball_local.z)
	var extension:=maxf(0,horizontal.length()-0.62)
	var dive:=clampf(extension/0.7,0,1)*windup*(1.0-smoothstep(0.0,0.3,jump)) if animation=="receive" else 0.0
	var crouch:=0.07+windup*0.17 if animation=="receive" else 0.055+minf(velocity.length()/4.15,1.0)*0.08
	var shift:=horizontal.normalized()*minf(extension,1.12)*windup+Vector3(0,0,0.38*windup) if animation=="receive" else Vector3.ZERO
	if animation=="block": shift=Vector3(0,0,-0.38*windup)
	var pelvis_target:=Vector3(shift.x,0.99-crouch-dive*0.32,shift.z)
	var grounded_pelvis:Vector3=torso.position-Vector3.UP*float(get_meta("last_jump",0.0))
	torso.position=(pelvis_target if teleport else grounded_pelvis.lerp(pelvis_target,minf(1,delta*28)))+Vector3.UP*jump
	set_meta("last_jump",jump)
	torso.rotation=Vector3(-0.13-dive*0.77 if animation=="receive" else (lerpf(-0.15,0.22,smoothstep(0.36,0.64,action))*windup if animation=="spike" else -0.22*windup if animation=="block" else -0.08*windup),0.28*windup*lerpf(-1,1,smoothstep(0.36,0.64,action)) if animation=="spike" else 0,-clampf(velocity.x*0.025,-0.10,0.10))
	head.rotation.x=clampf(atan2(ball_position.y-(world_position.y+1.7),maxf(0.4,(ball_position-world_position).length()))*0.55,-0.25,0.55)
	mouth.scale.y=0.0154 if animation in ["spike","block","celebrate"] else 0.0028
	teeth.visible=animation in ["spike","block","celebrate"]
	mouth.material_override.albedo_color=Color("55342d") if teeth.visible else Color("956451")
	expression_time+=delta
	var blink_phase:=fposmod(expression_time+identity*1.3,5.1)
	var openness:=1.0
	if blink_phase>4.90 and animation=="ready": openness=1.0-sin((blink_phase-4.90)/0.20*PI)*0.94
	for eye in eyes:
		eye.scale.y=openness
		eye.position.y=0.018*(1.0-openness)
	for i in range(2): brows[i].rotation.z=(-1 if i==0 else 1)*(0.15 if animation in ["spike","receive","block"] else 0.0)
	phase+=velocity.length()*delta*6.5
	var jumping:=jump>0.015
	for i in range(2):
		var side_sign:float=-1 if i==0 else 1
		var home:=Vector3(side_sign*0.16,0.06,0.015)
		if teleport:
			feet_world[i]=to_global(home)
			feet_yaw[i]=rotation.y
			swinging[i]=false
			turn_step[i]=0
		if jumping and not airborne: takeoff_feet[i]=feet_world[i]
		var phase_side:=fposmod(phase+i*PI,TAU)
		if jumping:
			var air_pose:=to_global(home+Vector3(side_sign*0.035,jump*0.83,0.14*windup))
			feet_world[i]=takeoff_feet[i].lerp(air_pose,smoothstep(0,0.18,jump))
			feet_yaw[i]=lerp_angle(feet_yaw[i],rotation.y,minf(1,delta*5))
			swinging[i]=false
		elif airborne:
			# Land from the actual airborne location, then step into the ready stance.
			feet_world[i].y=0.06
		elif velocity.length()>0.2:
			turn_step[i]=0
			var swing:=phase_side>PI
			if swing and not swinging[i]:
				swing_start[i]=feet_world[i]
				swing_yaw[i]=feet_yaw[i]
			if swing:
				var t:float=(phase_side-PI)/PI
				var landing:=to_global(home)+velocity*0.045
				feet_world[i]=swing_start[i].lerp(landing,smoothstep(0,1,t))+Vector3.UP*sin(t*PI)*0.13
				feet_yaw[i]=lerp_angle(swing_yaw[i],rotation.y,smoothstep(0,1,t))
			if not swing and swinging[i]: feet_world[i].y=0.06
			swinging[i]=swing
		else:
			var needs_step:=absf(angle_difference(feet_yaw[i],rotation.y))>0.40 or feet_world[i].distance_to(to_global(home))>0.10
			if turn_step[i]==0 and turn_step[1-i]==0 and needs_step:
				turn_step[i]=0.001
				swing_start[i]=feet_world[i]
				swing_yaw[i]=feet_yaw[i]
			if turn_step[i]>0:
				turn_step[i]=minf(1,turn_step[i]+delta*4)
				var t:float=turn_step[i]
				feet_world[i]=swing_start[i].lerp(to_global(home),smoothstep(0,1,t))+Vector3.UP*sin(t*PI)*0.075
				feet_yaw[i]=lerp_angle(swing_yaw[i],rotation.y,smoothstep(0,1,t))
				if t>=1: turn_step[i]=0
		var foot:=to_local(feet_world[i])
		var hip:Vector3=torso.position+Vector3(side_sign*0.105,-0.02,0)
		# A full dive releases the trailing leg instead of stretching its bones.
		if (dive>0.2 or jumping) and hip.distance_to(foot)>0.913:
			foot=hip+(foot-hip).limit_length(0.913)
			feet_world[i]=to_global(foot)
		var knee:=joint(hip,foot,0.47,0.45,Vector3(side_sign*0.20,0,-1))
		G.pose_bone(thighs[i],hip,knee)
		G.pose_bone(calves[i],knee,foot)
		G.pose_bone(shorts[i],hip,knee.lerp(hip,0.46))
		G.pose_bone(pads[i],knee.lerp(hip,0.13),knee.lerp(foot,0.16))
		shoes[i].position=foot
		shoes[i].rotation=Vector3(-0.30*windup if jumping else 0.0,feet_yaw[i]-rotation.y,0)
		var shoulder:Vector3=torso.transform*Vector3(side_sign*0.185,0.443,0)
		var wrist:=torso.position+Vector3(side_sign*0.245,0.075,-0.25)
		var elbow_hint:=Vector3(side_sign*0.25,-0.8,0.15)
		if velocity.length()>0.2: wrist.z+=sin(phase+i*PI)*0.14
		if animation=="receive": wrist=torso.position+Vector3(side_sign*0.048,-0.10,-0.43)
		elif animation=="set":
			var gather:=shoulder+Vector3(-side_sign*0.11,0.26,-0.18)
			var release:=shoulder+Vector3(-side_sign*0.04,0.55,-0.12)
			wrist=gather.lerp(release,smoothstep(0.0,0.23,0.73-action))
		elif animation in ["block","celebrate"]: wrist=shoulder+Vector3(side_sign*0.01,0.55,-0.10)
		elif animation=="spike":
			if i==1:
				# Elbow leads behind the head; hand whips through, then across the body.
				wrist=shoulder+Vector3(0.02,0.29,0.27)
				elbow_hint=Vector3(1,0.45,0.85)
				if action<0.5:
					wrist=(shoulder+Vector3(-0.05,0.51,-0.15)).lerp(torso.position+Vector3(-0.28,0.16,-0.30),smoothstep(0,0.24,0.5-action))
					elbow_hint=Vector3(0.7,0.1,-0.8)
			else:
				wrist=(torso.position+Vector3(-0.38,0.02,0.13)).lerp(shoulder+Vector3(-0.14,0.35,-0.34),smoothstep(0.32,0.62,action))
		if contact>0 and (animation!="spike" or i==1):
			var offset:=Vector3(side_sign*(0.075 if animation=="set" else 0.048),-0.115,0)
			if animation=="receive": offset=Vector3(side_sign*0.033,-0.065,-0.09)
			wrist=wrist.lerp(ball_local+offset,contact if action>=0.49 else contact*maxf(0,(action-0.36)/0.13))
		if animation in ["receive","set","block","spike"] and action<0.25:
			wrist=wrist.lerp(torso.position+Vector3(side_sign*0.245,0.075,-0.25),1-smoothstep(0,0.25,action))
		wrist=shoulder+(wrist-shoulder).limit_length(0.615)
		var elbow:=joint(shoulder,wrist,0.32,0.30,elbow_hint)
		G.pose_bone(upper_arms[i],shoulder,elbow)
		G.pose_bone(forearms[i],elbow,wrist)
		elbow_joints[i].position=elbow
		hands[i].position=wrist
		var finger_direction:=Vector3(0,0,-1) if animation=="receive" else Vector3(-side_sign*0.24,0.96,0).normalized() if animation=="set" else Vector3.UP if animation in ["block","spike","celebrate"] else (wrist-elbow).normalized()
		hands[i].quaternion=Quaternion(Vector3.UP,finger_direction)
		hand_world[i]=to_global(wrist+finger_direction*0.095)
	var actual_ball:=real_ball if real_ball.is_finite() else ball_position
	contact_error=minf(hand_world[0].distance_to(actual_ball),hand_world[1].distance_to(actual_ball))-0.11
	if animation=="receive":
		# Dig contact is the joined distal forearm platform, proximal to the wrists.
		var left_platform:=to_global(forearms[0].position.lerp(hands[0].position,0.75))
		var right_platform:=to_global(forearms[1].position.lerp(hands[1].position,0.75))
		contact_error=minf(left_platform.distance_to(actual_ball),right_platform.distance_to(actual_ball))-0.145
	airborne=jumping
	initialized=true

func joint(start:Vector3,end:Vector3,upper:float,lower:float,hint:Vector3) -> Vector3:
	var delta:=end-start
	var distance:=clampf(delta.length(),0.001,upper+lower-0.001)
	var direction:=delta.normalized()
	var along:float=(distance*distance+upper*upper-lower*lower)/(2*distance)
	var bend:Vector3=(hint-direction*hint.dot(direction)).normalized()
	return start+direction*along+bend*sqrt(maxf(0,upper*upper-along*along))
