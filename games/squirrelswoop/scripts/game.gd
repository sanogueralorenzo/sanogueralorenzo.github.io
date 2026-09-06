extends Node3D

const Geometry = preload("res://scripts/geometry.gd")
const Mountain = preload("res://scripts/mountain.gd")
const Squirrel = preload("res://scripts/squirrel.gd")
const HUD = preload("res://scripts/hud.gd")
const Sound = preload("res://scripts/sound.gd")
const FlightModel = preload("res://scripts/flight_model.gd")
const FrameMetrics = preload("res://scripts/frame_metrics.gd")
const SAVE_PATH := "user://swoop.cfg"

var mountain: Mountain
var squirrel: Squirrel
var camera: Camera3D
var ui: HUD
var sound: Sound
var sun: DirectionalLight3D
var motes: CPUParticles3D
var state := "summit"
var save_path := SAVE_PATH
var run_seed := 1
var player_pos := Vector3.ZERO
var speed := 20.0
var vertical_speed := -8.0
var lateral_speed := 0.0
var bank := 0.0
var pitch_input := 0.0
var diving := false
var dive_armed := false
var clearance := 6.0
var distance := 0.0
var score := 0.0
var run_time := 0.0
var clean_time := 0.0
var flow := 1
var max_flow := 1
var close_passes := 0
var current_route := 0
var best_distance := 0.0
var best_score := 0.0
var sound_volume := 0.7
var assistance := true
var reduced_motion := false
var invert_pitch := false
var near_seen: Dictionary={}
var bonus_score := 0.0
var camera_blend := 0.0
var crash_timer := 0.0
var record_run := false
var crash_cause := ""
var debug_visible := false
var review_server: TCPServer
var review_peer: StreamPeerTCP
var review_buffer := ""
var review_steer := 0.0
var review_pitch := 0.0
var review_dive := false
var review_controls := false
var review_staged := false
var elapsed := 0.0
var backdrop: Node3D
var perch: MeshInstance3D
var last_notice := -20.0
var flight := FlightModel.new()
var last_ground_warning := -20.0
var frame_metrics := FrameMetrics.new()
var camera_ground_aim := 0.0

func _ready() -> void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--review-port="): save_path="user://development.cfg"
 load_save()
 create_environment()
 mountain=Mountain.new()
 add_child(mountain)
 squirrel=Squirrel.new()
 add_child(squirrel)
 camera=Camera3D.new()
 camera.near=0.15
 camera.far=620
 camera.fov=70
 add_child(camera)
 camera.make_current()
 sound=Sound.new()
 add_child(sound)
 sound.volume=sound_volume
 ui=HUD.new()
 ui.game=self
 add_child(ui)
 ui.launch_requested.connect(launch)
 ui.resume_requested.connect(resume)
 ui.retry_requested.connect(retry)
 ui.summit_requested.connect(back_to_summit)
 ui.quit_requested.connect(func():save_progress();get_tree().quit())
 ui.settings_changed.connect(func():sound.volume=sound_volume;save_progress())
 create_motes()
 install_paint()
 create_backdrop()
 var args := OS.get_cmdline_user_args()
 for arg in args:
  if arg.begins_with("--review-port="):
   review_server=TCPServer.new()
   var error := review_server.listen(int(arg.get_slice("=",1)),"127.0.0.1")
   if error!=OK: push_warning("Review port unavailable: %s"%error)
 run_seed=randi_range(100000,999999)
 for arg in args:
  if arg.begins_with("--seed="): run_seed=int(arg.get_slice("=",1))
 reset_run()
 ui.show_summit()
 DisplayServer.window_set_title("Squirrel Swoop")

func create_environment() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode=Environment.BG_SKY
 var sky := Sky.new()
 var sky_mat := ShaderMaterial.new()
 sky_mat.shader=preload("res://shaders/sky.gdshader")
 sky.sky_material=sky_mat
 env.sky=sky
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color=Color(0.40,0.53,0.64)
 env.ambient_light_energy=0.34
 env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 env.tonemap_exposure=0.95
 env.fog_enabled=true
 env.fog_light_color=Color(0.26,0.38,0.41)
 env.fog_light_energy=0.68
 env.fog_density=0.0022
 env.fog_sky_affect=0.18
 world.environment=env
 add_child(world)
 sun=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-38,-36,0)
 sun.light_color=Color(1.0,0.86,0.64)
 sun.light_energy=1.28
 sun.shadow_enabled=true
 sun.directional_shadow_max_distance=135
 sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
 sun.shadow_bias=0.20
 sun.shadow_normal_bias=1.80
 sun.directional_shadow_blend_splits=true
 add_child(sun)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees=Vector3(-24,145,0)
 fill.light_color=Color(0.58,0.70,0.83)
 fill.light_energy=0.16
 add_child(fill)

func install_paint() -> void:
 # Adapted locally from Cozy Sora's calm-region brush filter. UI stays crisp.
 var layer := CanvasLayer.new()
 layer.layer=-1
 var rect := ColorRect.new()
 rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var material := ShaderMaterial.new()
 material.shader=preload("res://shaders/paint.gdshader")
 material.set_shader_parameter("brush_radius",0.9)
 rect.material=material
 layer.add_child(rect)
 add_child(layer)

func distant_height(x: float, d: float) -> float:
 return -d*0.52-18.0+sin(x*0.006+d*0.012)*12.0+sin(x*0.021+d*0.01)*7.0

func create_backdrop() -> void:
 # A receding forest floor, not a vertical silhouette wall at the horizon.
 backdrop=Node3D.new()
 add_child(backdrop)
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rng := RandomNumberGenerator.new()
 rng.seed=5206
 for row in 13:
  var d := 290.0+float(row)*24.0
  for column in 40:
   var x := float(column-20)*24.0
   var tint := Color(0.075,0.135,0.145).lerp(Color(0.15,0.22,0.23),float(row)/13.0)
   var a := Vector3(x,distant_height(x,d),-d)
   var b := Vector3(x+24,distant_height(x+24,d),-d)
   var c := Vector3(x,distant_height(x,d+24),-d-24)
   var e := Vector3(x+24,distant_height(x+24,d+24),-d-24)
   Geometry.tri(st,a,c,b,tint)
   Geometry.tri(st,b,c,e,tint)
   if row==12:
    Geometry.tri(st,c,Vector3(c.x,-950,c.z),e,tint)
    Geometry.tri(st,e,Vector3(c.x,-950,c.z),Vector3(e.x,-950,e.z),tint)
   var center := Vector3(x+rng.randf()*20,distant_height(x,d),-d-rng.randf()*20)
   var tall := rng.randf_range(20,43)
   # Broken, overlapping needle tiers remain small in screen space.
   for tier in 5:
    var y := tall*(0.32+float(tier)*0.135)
    var width := (6.4-float(tier)*1.05)*rng.randf_range(.8,1.2)
    for side in 4:
     var angle := float(side)*TAU/4.0
     var next := float(side+1)*TAU/4.0
     var tip := center+Vector3(0,y+tall*.27,0)
     var v1 := center+Vector3(cos(angle)*width,y,sin(angle)*width)
     var v2 := center+Vector3(cos(next)*width,y,sin(next)*width)
     Geometry.tri(st,tip,v1,v2,tint.lightened(float(side%2)*0.025))
 var node := MeshInstance3D.new()
 var mat := Geometry.material(Color.WHITE,true)
 mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 node.mesh=Geometry.finish(st,mat)
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 backdrop.add_child(node)

func create_motes() -> void:
 motes=CPUParticles3D.new()
 motes.amount=90
 motes.lifetime=5.0
 motes.preprocess=3.0
 motes.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
 motes.emission_box_extents=Vector3(19,10,26)
 motes.direction=Vector3(0.4,0.2,0.1)
 motes.initial_velocity_min=0.2
 motes.initial_velocity_max=0.9
 motes.gravity=Vector3(0,-0.08,0)
 motes.scale_amount_min=0.015
 motes.scale_amount_max=0.055
 motes.color=Color(0.95,0.86,0.53,0.65)
 var mesh := SphereMesh.new()
 mesh.radius=0.5
 mesh.height=1.0
 mesh.radial_segments=4
 mesh.rings=2
 var mat := Geometry.material(Color(0.87,0.81,0.48))
 mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 mesh.material=mat
 motes.mesh=mesh
 add_child(motes)

func reset_run() -> void:
 frame_metrics.reset()
 flight.reset()
 last_ground_warning=-20
 mountain.reset(run_seed)
 player_pos=Vector3(mountain.stream_x(0)-34.0,0,0)
 player_pos.y=mountain.height_at(player_pos.x,0)+6.2
 speed=20.0
 vertical_speed=-8.5
 lateral_speed=0
 bank=0
 pitch_input=0
 diving=false
 clearance=6.2
 distance=0
 score=0
 bonus_score=0
 run_time=0
 clean_time=0
 flow=1
 max_flow=1
 close_passes=0
 near_seen.clear()
 camera_blend=0
 last_notice=-20
 review_controls=false
 review_staged=false
 review_steer=0
 review_pitch=0
 review_dive=false
 squirrel.position=player_pos
 squirrel.rotation=Vector3.ZERO
 squirrel.visible=true
 if perch!=null: perch.queue_free()
 perch=MeshInstance3D.new()
 perch.mesh=Geometry.rock()
 perch.position=Vector3(player_pos.x,mountain.height_at(player_pos.x,0),1.05)
 perch.scale=Vector3(3.3,4.65,3.8)
 add_child(perch)
 current_route=mountain.route(player_pos.x,0)
 camera.position=player_pos+Vector3(20,19,30)
 camera.look_at(player_pos+Vector3(25,-27,-85))
 camera.fov=76
 camera_ground_aim=player_pos.y-14.0

func launch() -> void:
 if state!="summit": return
 state="flying"
 dive_armed=false
 ui.play_mode()
 sound.cue("start")
 ui.notice("Spread wide. Find your line.")

func retry(same_seed: bool) -> void:
 if not same_seed: run_seed=randi_range(100000,999999)
 reset_run()
 state="summit"
 launch()

func back_to_summit() -> void:
 save_progress()
 reset_run()
 state="summit"
 ui.show_summit()

func resume() -> void:
 if state!="paused": return
 state="flying"
 dive_armed=false
 ui.play_mode()

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_ENTER:
    if state=="summit" and ui.screen=="summit" and get_viewport().gui_get_focus_owner()==null: launch()
   KEY_ESCAPE:
    if state=="flying": state="paused";ui.show_pause()
    elif state=="paused": resume()
   KEY_R:
    if state=="results": retry(true)
   KEY_N:
    if state=="results": retry(false)
   KEY_F3:
    debug_visible=not debug_visible
    ui.diagnostics.visible=debug_visible
   KEY_F12: capture_frame()
 if event is InputEventJoypadButton and event.pressed:
  if event.button_index==JOY_BUTTON_A and state=="summit" and ui.screen=="summit": launch()
  elif event.button_index==JOY_BUTTON_A and state=="results": retry(true)
  elif event.button_index==JOY_BUTTON_Y and state=="results": retry(false)
  elif event.button_index==JOY_BUTTON_START:
   if state=="flying": state="paused";ui.show_pause()
   elif state=="paused": resume()

func _notification(what: int) -> void:
 if what==NOTIFICATION_APPLICATION_FOCUS_OUT and state=="flying" and review_server==null:
  state="paused"
  ui.show_pause()
 if what==NOTIFICATION_WM_CLOSE_REQUEST: save_progress()

func _process(delta: float) -> void:
 elapsed+=delta
 RenderingServer.global_shader_parameter_set("swoop_player",player_pos)
 if state=="flying": frame_metrics.sample()
 else: frame_metrics.last_tick=0
 if review_server!=null: poll_review()
 # Spread generation across frames; the visible area is always preloaded.
 mountain.stream_next()
 sound.update(delta,speed,diving,state=="flying",bank,flight.recovery_intensity,clearance)
 if state=="flying":
  perch.visible=distance<80
  camera_blend=minf(1.0,camera_blend+delta*0.58)
  update_camera(delta)
  squirrel.update_pose(delta,bank,atan2(vertical_speed,speed)*0.75,1.0 if diving else 0.0)
 elif state=="summit":
  squirrel.update_pose(delta,sin(elapsed*0.8)*0.02,0.05,0.65)
 elif state=="crashing":
  crash_timer-=delta
  squirrel.rotate_z(delta*1.8)
  if crash_timer<=0:
   state="results"
   ui.show_results(crash_cause,record_run)
 backdrop.position=Vector3(player_pos.x*0.8,player_pos.y,player_pos.z)
 motes.position=player_pos+Vector3(0,3,-12)
 ui.update(delta)

func _physics_process(delta: float) -> void:
 if state!="flying": return
 read_controls()
 var old_pos := player_pos
 run_time+=delta
 clean_time+=delta
 flow=mini(4,1+int(clean_time/12.0))
 max_flow=maxi(max_flow,flow)
 var steer := review_steer if review_controls else axis_steer()
 var pitch := pitch_input
 # Potential energy feeds speed; pulling up pays for lift with momentum.
 player_pos=flight.step(delta,player_pos,steer,pitch,diving,assistance,mountain)
 speed=flight.speed
 vertical_speed=flight.vertical_speed
 lateral_speed=flight.lateral_speed
 bank=flight.bank
 distance=-player_pos.z
 score=distance+bonus_score+clean_time*2.0
 var cause := collision_between(old_pos,player_pos)
 if not cause.is_empty():
  defeat(cause)
  return
 squirrel.position=player_pos
 mountain.update_focus(player_pos)
 clearance=player_pos.y-mountain.height_at(player_pos.x,distance)
 var r := mountain.route(player_pos.x,distance)
 if r!=current_route and run_time-last_notice>4.0:
  last_notice=run_time
  ui.notice(["Open sky. Room to breathe.","Let the water lead you.","Deep woods. Look for the light."][r])
 current_route=r
 var terrain_rate := (mountain.height_at(player_pos.x+lateral_speed*0.5,distance+speed*0.5)-mountain.height_at(player_pos.x,distance))/0.5
 var time_to_ground := (clearance-0.4)/maxf(0.1,terrain_rate-vertical_speed)
 if time_to_ground<1.15 and run_time-last_ground_warning>1.2:
  ui.notice("SPREAD YOUR WINGS  /  release dive" if diving else "GROUND AHEAD  /  pull gently",2)
  last_ground_warning=run_time

func axis_steer() -> float:
 var key := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
 if not Input.get_connected_joypads().is_empty():
  var axis := Input.get_joy_axis(Input.get_connected_joypads()[0],JOY_AXIS_LEFT_X)
  if absf(axis)>0.15: key=axis
 return key

func read_controls() -> void:
 if review_controls:
  pitch_input=review_pitch
  diving=review_dive
  return
 pitch_input=float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
 diving=Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SPACE)
 if not Input.get_connected_joypads().is_empty():
  var joy := Input.get_connected_joypads()[0]
  var axis := Input.get_joy_axis(joy,JOY_AXIS_LEFT_Y)
  if absf(axis)>0.15: pitch_input=axis
  diving=diving or Input.get_joy_axis(joy,JOY_AXIS_TRIGGER_RIGHT)>0.25
 if invert_pitch: pitch_input=-pitch_input
 # A held menu-confirm key must be released before it can become a dive.
 if not dive_armed:
  if not diving: dive_armed=true
  diving=false

func update_camera(delta: float) -> void:
 var velocity_lead := Vector3(lateral_speed,vertical_speed,-speed)*0.18 if state=="flying" else Vector3.ZERO
 var follow := player_pos+Vector3(-lateral_speed*0.06,8.2,5.6)+velocity_lead
 var start := player_pos+Vector3(20,19,30)
 var desired := start.lerp(follow,smoothstep(0,1,camera_blend))
 camera.position=camera.position.lerp(desired,1.0-exp(-delta*5.0))
 var ahead := 24.0
 var aim_x := player_pos.x+lateral_speed*0.42
 var terrain_aim := mountain.height_at(aim_x,-player_pos.z+ahead)-6.0
 # Look into the descending ground; damp shelves instead of nodding at each bump.
 terrain_aim=clampf(terrain_aim,player_pos.y-32.0,player_pos.y-19.0)
 camera_ground_aim=lerpf(camera_ground_aim,terrain_aim,1.0-exp(-delta*2.3))
 var look := Vector3(aim_x,camera_ground_aim,player_pos.z-ahead)
 camera.look_at(look)
 if not reduced_motion: camera.rotation.z=-bank*0.025
 var fov_target := 60.0 if reduced_motion else 59.0+(speed-20.0)*0.20
 camera.fov=lerpf(camera.fov,fov_target,1.0-exp(-delta*2.5))

func segment_distance(a: Vector3,b: Vector3,p: Vector3) -> float:
 var ab := b-a
 var t := clampf((p-a).dot(ab)/maxf(ab.length_squared(),0.0001),0,1)
 return p.distance_to(a+ab*t)

func segment_segment_distance(p1: Vector3,q1: Vector3,p2: Vector3,q2: Vector3) -> float:
 # Closest points between finite segments, including parallel and degenerate cases.
 var d1 := q1-p1
 var d2 := q2-p2
 var r := p1-p2
 var a := d1.dot(d1)
 var e := d2.dot(d2)
 var f := d2.dot(r)
 var s := 0.0
 var t := 0.0
 if a<=0.00001: return segment_distance(p2,q2,p1)
 if e<=0.00001: return segment_distance(p1,q1,p2)
 var c := d1.dot(r)
 var b := d1.dot(d2)
 var denom := a*e-b*b
 if absf(denom)>0.00001: s=clampf((b*f-c*e)/denom,0,1)
 t=(b*s+f)/e
 if t<0: t=0;s=clampf(-c/a,0,1)
 elif t>1: t=1;s=clampf((b-c)/a,0,1)
 return (p1+d1*s).distance_to(p2+d2*t)

func collision_between(a: Vector3,b: Vector3) -> String:
 var count := maxi(1,ceili(a.distance_to(b)/0.35))
 for i in range(1,count+1):
  var p := a.lerp(b,float(i)/count)
  if p.y<mountain.height_at(p.x,-p.z)+0.28:
   return "The mountainside caught you. Release dive sooner to regain lift."
 for o in mountain.obstacles_near(b):
  var pos: Vector3=o.pos
  if o.kind!="wood" and (absf(pos.z-b.z)>35 or absf(pos.x-b.x)>12): continue
  var gap := 100.0
  match o.kind:
   "tree":
    var relative_height := clampf(((a.y+b.y)*0.5-pos.y)/float(o.height),0,1)
    var trunk_radius := lerpf(float(o.radius),float(o.radius)*0.087,relative_height)
    gap=segment_segment_distance(a,b,pos,pos+Vector3(0,o.height,0))-trunk_radius
   "branch": gap=segment_segment_distance(a,b,pos,o.end)-o.radius
   "wood":
    # Four tapered intervals keep large buttresses accurate without a wide capsule
    # around thin branch tips. Sweep the player against every interval.
    var end: Vector3=o.end
    var rad_a := float(o.radius)
    var rad_b := float(o.radius_end)
    for part in 4:
     var t0 := float(part)/4.0
     var t1 := float(part+1)/4.0
     var rad := lerpf(rad_a,rad_b,(t0+t1)*0.5)
     gap=minf(gap,segment_segment_distance(a,b,pos.lerp(end,t0),pos.lerp(end,t1))-rad)
   "rock":
    var extents: Vector3=o.extents
    var inverse_rotation: Basis=o.inverse_rotation
    gap=(segment_distance((inverse_rotation*(a-pos))/extents,(inverse_rotation*(b-pos))/extents,Vector3.ZERO)-1.0)*minf(extents.x,minf(extents.y,extents.z))
  if gap<0.29:
   if o.kind=="tree": return "A tree caught your line. Bank early and look beyond the next trunk."
   if o.kind=="branch" or o.kind=="wood": return "A branch caught you. Look for a clear opening between the limbs."
   return "A mossy rock ended this descent. A little more clearance next time."
  var pass_id: String=o.get("pass_id",o.id)
  if gap<1.8 and gap>0.32 and pos.z>b.z and not near_seen.has(pass_id):
   near_seen[pass_id]=distance
   close_passes+=1
   bonus_score+=75.0*flow
   ui.notice("CLOSE PASS  +%d"%(75*flow))
   sound.cue("pass",clampf((pos.x-player_pos.x)/4.0,-1,1))
 if near_seen.size()>150:
  for id in near_seen.keys():
   if distance-float(near_seen[id])>200: near_seen.erase(id)
 return ""

func defeat(cause: String) -> void:
 state="crashing"
 crash_timer=0.65
 crash_cause=cause
 record_run=distance>best_distance or score>best_score
 best_distance=maxf(best_distance,distance)
 best_score=maxf(best_score,score)
 save_progress()
 sound.cue("crash")
 ui.notice("A LITTLE TOO CLOSE")

func save_progress() -> void:
 best_distance=maxf(best_distance,distance)
 best_score=maxf(best_score,score)
 var cfg := ConfigFile.new()
 cfg.set_value("records","distance",maxf(best_distance,distance))
 cfg.set_value("records","score",maxf(best_score,score))
 cfg.set_value("settings","volume",sound_volume)
 cfg.set_value("settings","assistance",assistance)
 cfg.set_value("settings","reduced_motion",reduced_motion)
 cfg.set_value("settings","invert_pitch",invert_pitch)
 cfg.set_value("mountain","last_seed",run_seed)
 var error := cfg.save(save_path)
 if error!=OK: push_warning("Could not save progress: %s"%error)

func load_save() -> void:
 var cfg := ConfigFile.new()
 if cfg.load(save_path)!=OK: return
 best_distance=maxf(0,float(cfg.get_value("records","distance",0.0)))
 best_score=maxf(0,float(cfg.get_value("records","score",0.0)))
 sound_volume=clampf(float(cfg.get_value("settings","volume",0.7)),0,1)
 assistance=bool(cfg.get_value("settings","assistance",true))
 reduced_motion=bool(cfg.get_value("settings","reduced_motion",false))
 invert_pitch=bool(cfg.get_value("settings","invert_pitch",false))

func capture_frame(path := "") -> void:
 await RenderingServer.frame_post_draw
 var output := path
 if output.is_empty(): output="user://swoop-%d.png"%Time.get_unix_time_from_system()
 get_viewport().get_texture().get_image().save_png(output)
 print("Captured ",ProjectSettings.globalize_path(output))

# Opt-in local development console. These are manual play controls, not a test suite.
# Disabled in ordinary launches; never listens beyond loopback.
func poll_review() -> void:
 if review_server.is_connection_available():
  review_peer=review_server.take_connection()
  review_buffer=""
 if review_peer==null: return
 review_peer.poll()
 if review_peer.get_status()!=StreamPeerTCP.STATUS_CONNECTED: return
 if review_peer.get_available_bytes()>0:
  review_buffer+=review_peer.get_utf8_string(review_peer.get_available_bytes())
 while review_buffer.contains("\n"):
  var line := review_buffer.get_slice("\n",0)
  review_buffer=review_buffer.substr(line.length()+1)
  var command = JSON.parse_string(line)
  if command is Dictionary:
   handle_review(command)
   var snapshot := {"state":state,"seed":run_seed,"distance":distance,"score":score,"speed":speed,"clearance":clearance,"position":[player_pos.x,player_pos.y,player_pos.z],"vertical_speed":vertical_speed,"route":current_route,"passes":close_passes,"sections":mountain.chunks.size(),"generated":mountain.generated_count,"pending":mountain.pending.size(),"fps":Engine.get_frames_per_second(),"best_distance":best_distance,"best_score":best_score,"assistance":assistance,"reduced_motion":reduced_motion,"volume":sound_volume}
   var passage := mountain.passage_centers(-player_pos.z,2)
   snapshot["forest_passages"]=[passage.x,passage.y]
   snapshot["focus"]=str(get_viewport().gui_get_focus_owner())
   snapshot["screen"]=ui.screen
   snapshot["staged"]=review_staged
   snapshot["generation_ms"]=mountain.generation_ms
   snapshot["generation_slice_ms"]=mountain.generation_slice_ms
   snapshot["building"]=mountain.building
   snapshot["cached_vertices"]=mountain.vertex_heights.size()
   snapshot["metrics"]=frame_metrics.snapshot()
   snapshot["recovery_intensity"]=flight.recovery_intensity
   snapshot["flight_state"]=flight.flight_state
   review_peer.put_data((JSON.stringify(snapshot)+"\n").to_utf8_buffer())

func handle_review(c: Dictionary) -> void:
 match str(c.get("action","status")):
  "shadow":
   sun.shadow_enabled=bool(c.get("enabled",true))
   sun.shadow_bias=float(c.get("bias",sun.shadow_bias))
   sun.shadow_normal_bias=float(c.get("normal_bias",sun.shadow_normal_bias))
  "metrics_reset": frame_metrics.reset()
  "launch": launch()
  "input":
   review_controls=true
   review_steer=clampf(float(c.get("steer",0)),-1,1)
   review_pitch=clampf(float(c.get("pitch",0)),-1,1)
   review_dive=bool(c.get("dive",false))
  "pause":
   if state=="flying": state="paused";ui.show_pause()
  "resume": resume()
  "retry": retry(bool(c.get("same",true)))
  "summit": back_to_summit()
  "seed":
   run_seed=int(c.get("value",run_seed))
   back_to_summit()
  "capture": capture_frame(str(c.get("path","")))
  "debug": ui.diagnostics.visible=bool(c.get("visible",true))
  "settings":
   assistance=bool(c.get("assistance",assistance))
   reduced_motion=bool(c.get("reduced_motion",reduced_motion))
   invert_pitch=bool(c.get("invert_pitch",invert_pitch))
   sound_volume=float(c.get("volume",sound_volume))
   sound.volume=sound_volume
   save_progress()
  "inspect":
   # Move only the review camera for visual inspection; normal play uses no teleportation.
   if state!="flying":
    state="paused"
    review_staged=true
    var d := float(c.get("distance",100))
    var x := float(c.get("x",mountain.stream_x(d)+50))
    player_pos=Vector3(x,mountain.height_at(x,d)+float(c.get("height",5)),-d)
    squirrel.position=player_pos
    mountain.update_focus(player_pos)
    camera_blend=1
    for i in 3: update_camera(1.0)
    perch.visible=false
    squirrel.update_pose(1.0,0,-0.23,0)
    ui.play_mode()
    current_route=mountain.route(x,d)
  "key":
   review_controls=false
   var event := InputEventKey.new()
   event.keycode=int(c.get("code",0))
   event.physical_keycode=event.keycode
   event.key_label=event.keycode
   event.unicode=event.keycode if event.keycode<128 else 0
   event.pressed=bool(c.get("pressed",true))
   Input.parse_input_event(event)
  "quit": save_progress();get_tree().quit()
