extends Node3D
## The match director owns all outcomes. This layer owns world-space presentation.
const G=preload("res://scripts/three_d/geometry.gd")
const Athlete=preload("res://scripts/three_d/athlete.gd")
var game:Node
var camera:Camera3D
var actors:Array[Node3D]=[]
var volleyball:MeshInstance3D
var ball_effects:Node3D
var selected_ring:MeshInstance3D
var aim_ring:MeshInstance3D
var floor_ring:MeshInstance3D
var scouting_ring:MeshInstance3D
var scouting_outline:MeshInstance3D
var sun:DirectionalLight3D
var environment:Environment
var sky_material:ShaderMaterial
var ocean_material:ShaderMaterial
var scenery_root:Node3D
var venue:Node3D
var map_index:=0
var variant:=0
var built_map:=-1
var built_variant:=-1
var x_scale:=1.10
var z_scale:=0.8
var inspection_camera:=false
var portraits:Array[Texture2D]=[]

func _ready() -> void:
	name="VolleyballWorld3D"
	camera=Camera3D.new()
	camera.name="RallyCamera"
	camera.fov=42
	camera.near=0.08
	camera.far=900
	add_child(camera)
	camera.position=Vector3(1.2,3.4,11.7)
	camera.look_at(Vector3(0,1.63,-0.2))
	camera.current=true
	install_light()
	scenery_root=Node3D.new()
	add_child(scenery_root)
	build_court()
	for team in range(2):
		for i in range(3):
			var actor:=Athlete.new()
			add_child(actor)
			actor.build(i,team)
			actors.append(actor)
	ball_effects=preload("res://scripts/three_d/ball_effects.gd").new()
	add_child(ball_effects)
	volleyball=ball_effects.ball
	selected_ring=ring(0.46,Color("f3cc70"),0.018)
	aim_ring=ring(0.38,Color("fff0c3"),0.012)
	floor_ring=ring(0.17,Color("d8c591"),0.009)
	scouting_ring=ring(0.40,Color("d87950"),0.033)
	scouting_outline=ring(0.445,Color("fff3d7"),0.014)
	refresh()
	build_portraits()
	install_paint()

func install_paint() -> void:
	# The world receives a restrained brush finish; text and controls remain crisp.
	var layer:=CanvasLayer.new()
	layer.layer=-1
	var rectangle:=ColorRect.new()
	rectangle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rectangle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var paint:=ShaderMaterial.new()
	paint.shader=preload("res://shaders/three_d/paint.gdshader")
	rectangle.material=paint
	layer.add_child(rectangle)
	add_child(layer)

func build_portraits() -> void:
	for i in range(3):
		var viewport:=SubViewport.new()
		viewport.size=Vector2i(213,309)
		viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		viewport.msaa_3d=Viewport.MSAA_2X
		add_child(viewport)
		var portrait:=Athlete.new()
		viewport.add_child(portrait)
		portrait.build(i,0)
		portrait.update_pose({"velocity":Vector2.ZERO,"action":0.0,"anim":"ready"},Vector3.ZERO,Vector3(0,1.65,-2),0,false,Vector3(0,0,-1))
		var portrait_camera:=Camera3D.new()
		viewport.add_child(portrait_camera)
		portrait_camera.position=Vector3(0.12,1.64,-1.03)
		portrait_camera.fov=28
		portrait_camera.look_at(Vector3(0,1.70,0))
		portrait.head.rotation.y=[-0.10,0.08,-0.16][i]
		portrait.head.rotation.z=[-0.04,0.025,0.04][i]
		portrait.mouth.scale.y=[0.004,0.020,0.006][i]
		portrait.mouth.scale.x=1.20 if i==1 else 1.0
		portrait.mouth.material_override.albedo_color=Color("61382d") if i==1 else Color("87513f")
		portrait.teeth.visible=i==1
		portrait.teeth.position.y=-0.067
		portrait.teeth.scale=Vector3(0.020,0.0035,0.0015)
		for side_index in range(2):
			portrait.brows[side_index].rotation.z=[[-0.22,0.19],[0.15,-0.15],[-0.06,0.11]][i][side_index]
			if i==1: portrait.brows[side_index].position.y+=0.004
		var light:=DirectionalLight3D.new()
		viewport.add_child(light)
		light.position=Vector3(-2,3,-4)
		light.look_at(Vector3(0,1.5,0))
		light.light_color=Color("ffe3b6")
		light.light_energy=1.1
		var backdrop:=WorldEnvironment.new()
		backdrop.environment=Environment.new()
		backdrop.environment.background_mode=Environment.BG_COLOR
		backdrop.environment.background_color=Color("2d6770")
		backdrop.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		backdrop.environment.ambient_light_color=Color("c4d0c5")
		backdrop.environment.ambient_light_energy=0.65
		viewport.add_child(backdrop)
		portraits.append(viewport.get_texture())

func install_light() -> void:
	var holder:=WorldEnvironment.new()
	environment=Environment.new()
	holder.environment=environment
	add_child(holder)
	environment.background_mode=Environment.BG_SKY
	var sky:=Sky.new()
	sky_material=ShaderMaterial.new()
	sky_material.shader=preload("res://shaders/three_d/sky.gdshader")
	sky.sky_material=sky_material
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("bdc6c7")
	environment.ambient_light_energy=0.56
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure=0.94
	environment.ssao_enabled=true
	environment.ssao_radius=0.65
	environment.ssao_intensity=1.0
	environment.ssao_power=1.3
	environment.fog_enabled=true
	environment.fog_mode=Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin=45
	environment.fog_depth_end=260
	environment.fog_light_color=Color("beced1")
	environment.fog_sky_affect=0.05
	sun=DirectionalLight3D.new()
	sun.light_color=Color("ffe1ad")
	sun.light_energy=1.28
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=90
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias=0.035
	sun.shadow_normal_bias=0.12
	sun.shadow_blur=1.3
	add_child(sun)
	sun.position=Vector3(-16,24,-13)
	sun.look_at(Vector3.ZERO)
	var fill:=DirectionalLight3D.new()
	fill.light_color=Color("e9dbc1")
	fill.light_energy=0.23
	add_child(fill)
	fill.position=Vector3(14,10,20)
	fill.look_at(Vector3.ZERO)

func build_court() -> void:
	G.box(self,Vector3(0,-0.20,0),Vector3(16,0.40,25*z_scale),G.surface(Color("bfa985"),5,0.15))
	G.box(self,Vector3(0,0.009,0),Vector3(9*x_scale,0.025,16*z_scale),G.surface(Color("b67d5c"),7,0.28))
	var line_mat:=G.matte(Color("f6e9ce"))
	for x in [-4.5,4.5]: G.box(self,Vector3(x*x_scale,0.026,0),Vector3(0.055,0.006,16.04*z_scale),line_mat)
	for z in [-8.0,-3.0,0.0,3.0,8.0]: G.box(self,Vector3(0,0.026,z*z_scale),Vector3(9*x_scale,0.006,0.055),line_mat)
	var pole:=G.matte(Color("536f72"))
	var pad:=G.surface(Color("27677a"),0,0.07)
	for x in [-4.85,4.85]:
		G.beam(self,Vector3(x*x_scale,0,0),Vector3(x*x_scale,2.73,0),0.035,pole,0.031,16)
		G.beam(self,Vector3(x*x_scale,0.1,0),Vector3(x*x_scale,1.22,0),0.090,pad,0.090,16)
		for y in [0.2,0.55,0.90]: G.beam(self,Vector3(x*x_scale-0.085,y,0),Vector3(x*x_scale+0.085,y,0),0.008,line_mat)
		for y in range(7): G.beam(self,Vector3(x*x_scale,2.5+y*0.05,0),Vector3(x*x_scale,2.55+y*0.05,0),0.016,G.matte(Color("b6523e") if y%2==0 else Color("fff5d8")),0.016,8)
	# Actual dark strands stay continuous under perspective and multisampling.
	var net_parent:=Node3D.new()
	add_child(net_parent)
	var thread_material:=G.matte(Color("35453e"))
	thread_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for column in range(97):
		var x:float=(-4.8+column*0.1)*x_scale
		G.beam(net_parent,Vector3(x,1.53,0),Vector3(x,2.43,0),0.0055,thread_material,0.0055,6)
	for row in range(10):
		var y:float=1.53+row*0.10
		G.beam(net_parent,Vector3(-4.8*x_scale,y,0),Vector3(4.8*x_scale,y,0),0.0055,thread_material,0.0055,6)
	var strands:=SurfaceTool.new()
	strands.begin(Mesh.PRIMITIVE_TRIANGLES)
	for node in net_parent.get_children():
		strands.append_from(node.mesh,0,node.transform)
		node.queue_free()
	G.instance(self,strands.commit(),Vector3.ZERO,thread_material)
	net_parent.queue_free()
	G.box(self,Vector3(0,2.445,0),Vector3(9.68*x_scale,0.070,0.030),line_mat)
	G.beam(self,Vector3(-4.83*x_scale,1.53,0),Vector3(4.83*x_scale,1.53,0),0.009,line_mat,0.009,8)

func ring(radius:float,color:Color,thickness:float) -> MeshInstance3D:
	var mesh:=TorusMesh.new()
	mesh.inner_radius=radius-thickness
	mesh.outer_radius=radius+thickness
	mesh.rings=48
	mesh.ring_segments=8
	var mat:=G.matte(color)
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var n:=G.instance(self,mesh,Vector3.ZERO,mat)
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

func world(p:Vector2,height:float=0.0) -> Vector3:
	return Vector3(p.x*x_scale,height,p.y*z_scale)

func court(p:Vector2) -> Vector2:
	return camera.unproject_position(world(p,0.035))

func ball_screen() -> Vector2:
	return camera.unproject_position(world(game.ball,game.ball_height))

func refresh() -> void:
	if built_map==map_index and built_variant==variant: return
	if built_map==map_index:
		built_variant=variant
		if map_index==1: venue.set_evening(variant==2)
		apply_season_light()
		return
	built_map=map_index
	built_variant=variant
	for child in scenery_root.get_children(): child.queue_free()
	var ocean_mesh:=PlaneMesh.new()
	ocean_mesh.size=Vector2(1200,1200)
	ocean_material=ShaderMaterial.new()
	ocean_material.shader=preload("res://shaders/three_d/ocean.gdshader")
	G.instance(scenery_root,ocean_mesh,Vector3(-80,-5,0),ocean_material)
	if map_index==0:
		G.box(scenery_root,Vector3(3,-2.4,-14*z_scale),Vector3(27,5,10*z_scale),G.surface(Color("b4a58a"),2))
	# A consistent open boundary frames the action on every venue.
	var rail:=G.matte(Color("e9dfc9") if map_index!=1 else Color("9cae9d"))
	for side in [-1,1]:
		for j in range(13): G.beam(scenery_root,Vector3(side*7.0,0.1,(-11+j*1.7)*z_scale),Vector3(side*7.0,1.08,(-11+j*1.7)*z_scale),0.052,rail,0.052,10)
		G.beam(scenery_root,Vector3(side*7.0,0.92,-11*z_scale),Vector3(side*7.0,0.92,10*z_scale),0.055,rail,0.055,10)
	match map_index:
		1:
			venue=preload("res://scripts/three_d/harbor.gd").new()
			venue.evening=variant==2
		2: venue=preload("res://scripts/three_d/gardens.gd").new()
		_: venue=preload("res://scripts/three_d/coast.gd").new()
	venue.scale.z=z_scale
	scenery_root.add_child(venue)
	apply_season_light()

func apply_season_light() -> void:
	# Nine inexpensive atmospheres share each venue's geometry and fair visibility.
	var settings:=[
		[Vector3(-16,24,-13),"ffe1ad",1.28,"bdc6c7",.56,"b3d6e0","4797c9","faf5e8",0.0],
		[Vector3(-8,32,-15),"f3ead1",1.18,"b8cbd0",.61,"b5d5de","579fcb","f4f4e9",.14],
		[Vector3(-23,16,-10),"ffd196",1.32,"c4bdc0",.59,"e2c8b4","729ebb","fff0d1",.12],
		[Vector3(-18,26,-8),"ffe2b4",1.24,"b6c8c9",.59,"b3d6dc","5198be","faf3e1",.05],
		[Vector3(12,29,-16),"e4e9dc",1.12,"b0c6cd",.64,"bdd5da","639bb7","e8ede6",.25],
		[Vector3(-24,13,-18),"ffc18e",1.13,"b0b7ce",.74,"dabeb6","777f9f","f8d8ba",.13],
		[Vector3(-17,26,-14),"eee5b6",1.27,"bfccb9",.59,"c7dacd","71aab4","f3f1d9",.10],
		[Vector3(-10,30,-16),"e5e5d0",.91,"b9c7c9",.76,"b4c8c9","809da6","d5dbd4",.50],
		[Vector3(-22,18,-12),"ffd49b",1.30,"c3c2b7",.64,"e3ceb0","85a7af","fff0d2",.06]
	]
	var selected:Array=settings[clampi(map_index*3+variant,0,8)]
	sun.position=selected[0]
	sun.look_at(Vector3.ZERO)
	sun.light_color=Color(selected[1])
	sun.light_energy=selected[2]
	environment.ambient_light_color=Color(selected[3])
	environment.ambient_light_energy=selected[4]
	environment.fog_light_color=Color(selected[5])
	sky_material.set_shader_parameter("horizon_color",Color(selected[5]))
	sky_material.set_shader_parameter("zenith_color",Color(selected[6]))
	sky_material.set_shader_parameter("cloud_color",Color(selected[7]))
	sky_material.set_shader_parameter("overcast",selected[8])
	ocean_material.set_shader_parameter("warmth",.26 if variant==2 else 0.0)

func _process(delta:float) -> void:
	if game.players.size()!=6: return
	var playing:bool=game.screen=="match"
	var deepest:=5.8
	var deep_x:=0.0
	for p in game.players:
		if p.team==0:
			for location in [p.pos,p.target]:
				if location.y>deepest:
					deepest=location.y
					deep_x=location.x*x_scale
	var retreat:=clampf((deepest-6.0)/1.5,0,1)
	if not inspection_camera:
		# Lower, tighter framing gives the athletes presence. Anticipate the deep
		# receiver with a gentle pan so a sideline dive stays inside the frame.
		var destination:=Vector3(lerpf(1.2,.4+clampf(deep_x*.20,-.75,.75),retreat),lerpf(3.4,3.5,retreat),lerpf(11.7,13.2,retreat))
		var easing:=minf(1,delta*(4.0 if camera.position.z<destination.z else 1.5))
		camera.position=camera.position.lerp(destination,easing)
		camera.fov=42
		camera.look_at(Vector3(0,lerpf(1.63,1.6,retreat),-.2))
	var ball_pos:=world(game.ball,game.ball_height)
	for i in range(6):
		var p:Dictionary=game.players[i].duplicate()
		p.velocity*=game.COURT_SCALE
		var facing:=ball_pos
		var contact_ball:=ball_pos
		if p.anim=="receive" and ((game.phase=="receive" and game.receiving==p.team) or game.phase=="point"):
			var q:float=lerpf(0.67,0.95,float(game.season)/8.0) if p.team==1 else 0.68
			if p.team==0 and game.timing_press>=0 and absf(game.flight_duration-game.timing_press)<=0.13+game.upgrades.count("window")*0.05: q=1.0
			var reach:float=game.dig_reach(p.team,q)
			var to_ball:Vector2=game.ball-p.pos
			if to_ball.length()>reach:
				# A missed dig stops short of the same reach boundary used by scoring.
				# This only limits the rendered attempt; it never changes a result.
				contact_ball=world(p.pos+to_ball.limit_length(maxf(0.1,reach-0.28)),game.ball_height)
				p["miss_attempt"]=true
		if p.anim=="spike":
			facing=world(game.target_for(p.team,game.aim_lane if p.team==0 else game.rival_lane,game.shot if p.team==0 else game.rival_shot,game.aim_deep if p.team==0 else true))
		elif p.anim=="set": facing=world(game.players[game.pick_attacker()].target)
		elif p.anim=="block":
			contact_ball=world(p.get("block_target",game.ball),p.get("block_height",game.ball_height))
			facing=contact_ball
		elif p.anim=="receive" and game.phase!="receive": facing=world(game.flight_start)
		actors[i].update_pose(p,world(p.pos),contact_ball,0.0 if game.pause else delta,playing,facing,ball_pos)
	ball_effects.update_ball(ball_pos,game.ball_spin,0.0 if game.pause else delta,playing,game.phase in ["receive","set","attack"],game.reduced_motion,camera)
	selected_ring.visible=playing
	selected_ring.position=world(game.players[game.active].pos,0.043)
	aim_ring.visible=playing
	aim_ring.position=world(game.target_for(0,game.aim_lane,game.shot,game.aim_deep),0.041)
	floor_ring.visible=playing
	floor_ring.position=world(game.ball,0.039)

	scouting_ring.visible=playing and game.receiving==1 and game.phase in ["set","attack"] and game.upgrades.has("read")
	scouting_outline.visible=scouting_ring.visible
	if scouting_ring.visible:
		scouting_ring.position=world(game.target_for(1,game.rival_lane,game.rival_shot),0.048)
		scouting_outline.position=scouting_ring.position
