extends Node2D
## Match director: finite movement, deterministic contacts, championship and saves.
const Scenery = preload("res://scripts/scenery.gd")
const Athlete = preload("res://scripts/athlete.gd")
const Sound = preload("res://scripts/sound.gd")
const Interface = preload("res://scripts/interface.gd")
var SAVE_PATH := "user://progress.json"
const MAPS := ["MAREA HILLS", "LANTERN HARBOR", "CITRUS GARDENS"]
const SEASONS := ["First light", "Sea glass", "Golden hour", "Fair winds", "High tide", "Harbor lights", "Green canopy", "Summer thunder", "Endless summer"]
const RIVALS := ["Sandpipers", "Sunbreak", "Marea Club", "Harbor Foxes", "Crosscurrent", "Lighthouse Six", "Garden Owls", "Citrus Storm", "Summer Aces"]
const SCOUTS := ["Patient receivers. Open corners reward a change of aim.", "Quick wings; their front court opens when they retreat.", "A committed middle block. Try a high roll past it.", "They defend deep. A short tip makes them travel.", "They remember short shots. Pull them forward, then attack deep.", "Strong net coverage; use height and the outside lanes.", "They spot empty space early. Keep all three teammates involved.", "They disguise short shots. Recovery matters as much as power.", "Complete, adaptive rivals. Read the block and vary your finish."]
const UPGRADE_POOL := [
	{"id":"reach","title":"Sand instincts","desc":"Receivers reach 0.18 m farther. Helps save balls at the edge of a dive.","tag":"DEFENSE"},
	{"id":"tempo","title":"First step","desc":"Your team reacts 0.08 s sooner to an incoming attack.","tag":"RECOVERY"},
	{"id":"window","title":"Quiet confidence","desc":"The excellent contact window grows by 0.05 s. Automatic contacts stay safe.","tag":"TIMING"},
	{"id":"power","title":"Heavy hand","desc":"Power attacks travel 8% faster. A waiting block still stops them.","tag":"ATTACK"},
	{"id":"tip","title":"Soft touch","desc":"Tips land 0.7 m closer to the net, pulling deep defenders forward.","tag":"PLACEMENT"},
	{"id":"roll","title":"High horizon","desc":"Roll shots travel 8% faster and clear every committed block.","tag":"ATTACK"},
	{"id":"speed","title":"Together, faster","desc":"All three teammates move 0.22 m/s faster, up to the shared 4.6 m/s cap.","tag":"TEAMWORK"},
	{"id":"set","title":"Perfect connection","desc":"Automatic set quality gains 8 percentage points. Timing can still improve it.","tag":"TEAMWORK"},
	{"id":"read","title":"Court vision","desc":"Show the rival's target during their set. Aim at that lane to react 0.13 s sooner on defense.","tag":"SCOUTING"}
]
var scenery: Node2D
var scenery_viewport: SubViewport
var sound: Node
var ui: Control
var painter := Athlete.new()
var screen := "intro"
var season := 0
var unlocked := 1
var crowns: Array = []
var round_index := 0
var score := [0,0]
var upgrades: Array[String] = []
var offers: Array = []
var squad := 0
var players: Array[Dictionary] = []
var time := 0.0
var simulation_accumulator := 0.0
var phase := "idle"
var phase_time := 0.0
var serve_team := 0
var receiving := 0
var toucher := 0
var setter := 1
var attacker := 2
var active := 0
var attack_choice := 0
var aim_lane := 1
var aim_deep := true
var shot := 0 # 0 roll, 1 power, 2 tip
var flight_start := Vector2.ZERO
var flight_end := Vector2.ZERO
var flight_start_height := 1.0
var flight_end_height := 1.0
var flight_arc := 2.5
var flight_duration := 1.5
var flight_elapsed := 0.0
var ball := Vector2.ZERO
var ball_height := 1.0
var ball_spin := 0.0
var ball_trail: Array[Vector2] = []
var contact_quality := 0.68
var set_quality := 0.68
var receive_quality := 0.68
var lane_history: Array[int] = []
var short_history: Array[bool] = []
var rival_cover_short := false
var timing_press := -99.0
var timing_result := ""
var rally_contacts := 0
var rally_count := 0
var match_time := 0.0
var run_time := 0.0
var feedback := ""
var feedback_timer := 0.0
var point_reason := ""
var pause := false
var practice := false
var practice_touched := false
var rival_lane := 1
var rival_shot := 0
var last_lane := -1
var repeat_lane := 0
var enemy_blocker := -1
var blocker_lane := 1
var block_checked := false
var flight_is_attack := false
var flight_source := "attack"
var attack_team := 0
var reaction_remaining := 0.0
var particles: Array[Dictionary] = []
var shake := 0.0
var reduced_motion := false
var save_error := ""
var ledger: Array = []
var best_rally := 0
var current_match_contacts := 0
var debug_visible := false
var toast := ""
var toast_time := 0.0

func _ready() -> void:
	scenery_viewport=SubViewport.new()
	scenery_viewport.size=Vector2i(1440,900)
	scenery_viewport.disable_3d=true
	scenery_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(scenery_viewport)
	scenery=Scenery.new()
	scenery_viewport.add_child(scenery)
	var background:=Sprite2D.new()
	background.centered=false
	background.texture=scenery_viewport.get_texture()
	background.show_behind_parent=true
	add_child(background)
	sound=Sound.new()
	add_child(sound)
	var post:=ColorRect.new()
	post.size=Vector2(1440,900)
	post.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var painted:=ShaderMaterial.new()
	painted.shader=preload("res://shaders/paint.gdshader")
	painted.set_shader_parameter("brush_radius",1.5)
	post.material=painted
	add_child(post)
	ui=Interface.new()
	ui.game=self
	add_child(ui)
	var review_port:=0
	var review_dir:="user://review-captures"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-port="): review_port=int(arg.get_slice("=",1))
		if arg.begins_with("--review-profile="): SAVE_PATH="user://review-"+arg.get_slice("=",1).validate_filename()+".json"
		if arg.begins_with("--capture-dir="): review_dir=arg.get_slice("=",1)
	load_progress()
	reset_players()
	ui.rebuild()
	if review_port>0:
		var bridge:=preload("res://scripts/review_bridge.gd").new()
		bridge.game=self
		add_child(bridge)
		bridge.start(review_port,review_dir)

func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f:=FileAccess.open(SAVE_PATH,FileAccess.READ)
	if f == null:
		save_error="Progress could not be read. Your existing save was kept."
		return
	var d=JSON.parse_string(f.get_as_text())
	if d is Dictionary and d.get("version",0)==1:
		unlocked=clampi(int(d.get("unlocked",1)),1,9)
		crowns.clear()
		for crown in d.get("crowns",[]):
			var value:=int(crown)
			if value>=1 and value<=9 and not crowns.has(value): crowns.append(value)
		reduced_motion=bool(d.get("reduced_motion",false))
		sound.muted=bool(d.get("muted",false))
		AudioServer.set_bus_mute(0,sound.muted)
	else: save_error="Save format could not be read. Existing file preserved."

func save_progress() -> void:
	var f:=FileAccess.open(SAVE_PATH+".tmp",FileAccess.WRITE)
	if f==null:
		save_error="Could not save progress. Check storage permissions."
		return
	f.store_string(JSON.stringify({"version":1,"unlocked":unlocked,"crowns":crowns,"reduced_motion":reduced_motion,"muted":sound.muted},"\t"))
	f.close()
	var err:=DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH+".tmp"),ProjectSettings.globalize_path(SAVE_PATH))
	if err!=OK: save_error="Could not replace the progress save."

func reset_players() -> void:
	players.clear()
	for team in range(2):
		for i in range(3):
			var p:=Vector2([-2.9,0.0,2.9][i],(4.8 if i!=1 else 3.1)*(1 if team==0 else -1))
			players.append({"team":team,"id":i,"pos":p,"target":p,"velocity":Vector2.ZERO,"motion":0.0,"recovery":0.0,"anim":"ready","action":0.0})

func start_run(index:int, training:bool=false) -> void:
	season=clampi(index,0,8)
	if not training and season>=unlocked: return
	practice=training
	practice_touched=false
	round_index=0
	upgrades.clear()
	ledger.clear()
	run_time=0
	best_rally=0
	last_lane=-1
	repeat_lane=0
	lane_history.clear()
	short_history.clear()
	rival_cover_short=false
	screen="match"
	scenery.map_index=season/3
	scenery.variant=season%3
	refresh_scenery()
	start_match()

func start_match() -> void:
	score=[0,0]
	match_time=0
	current_match_contacts=0
	rally_count=0
	reset_players()
	screen="match"
	begin_point(0)
	ui.rebuild()

func begin_point(server:int) -> void:
	serve_team=server
	receiving=1-server
	phase="serve"
	phase_time=0
	timing_press=-99
	ball=Vector2(-2.8,7.4*(1 if server==0 else -1))
	ball_height=1.2
	active=0 if server==0 else 1
	players[server*3].target=ball
	for i in range(6):
		players[i].anim="ready"
		players[i].recovery=0.0
		players[i].target=Vector2([-2.9,0.0,2.9][i%3],(4.8 if i%3!=1 else 2.6)*(1 if i<3 else -1))
	players[server*3].target=ball
	feedback="YOUR SERVE" if server==0 else "RIVAL SERVE"
	feedback_timer=1.5
	rally_contacts=0
	ball_trail.clear()

func _process(delta:float) -> void:
	simulation_accumulator+=delta
	# Fixed small steps preserve reactions, reach and contact outcomes at any render rate.
	while simulation_accumulator>=1.0/120.0:
		simulation_accumulator-=1.0/120.0
		tick(1.0/120.0)
	queue_redraw()
	ui.queue_redraw()

func tick(delta:float) -> void:
	time+=delta
	if toast_time>0: toast_time-=delta
	if not pause:
		feedback_timer=maxf(0,feedback_timer-delta)
		shake=maxf(0,shake-delta*28)
		for p in players:
			p.action=maxf(0,p.action-delta*1.6)
			p.contact_blend=maxf(0.0,p.get("contact_blend",0.0)-delta*5.0)
			if p.action==0: p.anim="ready"
		if screen=="match":
			match_time+=delta
			run_time+=delta
			phase_time+=delta
			move_players(delta)
			if phase=="serve":
				ball=players[serve_team*3].pos
				ball_height=lerpf(1.25,2.6,smoothstep(1.55,2.0,phase_time))
				if phase_time>1.55:
					players[serve_team*3].anim="spike"
					players[serve_team*3].action=0.5+(2.0-phase_time)/0.9
					players[serve_team*3].contact_target=project_ball()
					players[serve_team*3].contact_blend=smoothstep(1.75,2.0,phase_time)
				if phase_time>=2.0: serve()
			elif phase in ["receive","set","attack"]:
				flight_elapsed+=delta
				var t:=clampf(flight_elapsed/flight_duration,0,1)
				ball=flight_start.lerp(flight_end,t)
				ball_height=lerpf(flight_start_height,flight_end_height,t)+sin(t*PI)*flight_arc
				var remaining:=flight_duration-flight_elapsed
				if remaining<0.45:
					var actor:=toucher if phase=="receive" else (setter if phase=="set" else attacker)
					players[actor].anim="receive" if phase=="receive" else ("set" if phase=="set" else "spike")
					players[actor].action=0.5+maxf(0,remaining)/0.9
					players[actor].contact_target=project_ball()
					players[actor].contact_blend=1.0-smoothstep(0.0,0.20,remaining)
				ball_spin+=delta*(5.0 if flight_is_attack else 2.0)
				if flight_is_attack and enemy_blocker>=0 and int(get_meta("flight_kind",0))==1:
					var cross_time:=absf(flight_start.y)/maxf(absf(flight_start.y)+absf(flight_end.y),0.1)*flight_duration
					var until_net:=cross_time-flight_elapsed
					if until_net>0 and until_net<0.20:
						players[enemy_blocker].anim="block"
						players[enemy_blocker].action=0.5+until_net*2.5
				if flight_is_attack and not block_checked and ((attack_team==0 and ball.y<=0) or (attack_team==1 and ball.y>=0)):
					block_checked=true
					check_block()
				if flight_elapsed>=flight_duration: resolve_contact()
			elif phase=="point" and phase_time>2.0:
				if match_over(): finish_match()
				else: begin_point(serve_team)
			var projected:=project_ball()
			ball_trail.push_front(projected)
			if ball_trail.size()>9: ball_trail.pop_back()
		for p in particles:
			p.life-=delta
			p.pos+=p.vel*delta
			p.vel.y+=190*delta
		particles=particles.filter(func(p): return p.life>0)

func move_players(delta:float) -> void:
	var prior_reaction:=reaction_remaining
	reaction_remaining=maxf(0,reaction_remaining-delta)
	for i in range(6):
		var p:Dictionary=players[i]
		var speed:=4.15
		if p.team==0:
			speed+=0.22*upgrades.count("speed")
			if squad==1: speed+=0.2
			if squad==2 and i%3==2: speed+=0.25
		speed=minf(speed,4.6)
		var wait_time:float=maxf(prior_reaction if phase=="receive" and p.team==receiving else 0.0,p.recovery)
		var move_delta:=maxf(0.0,delta-wait_time)
		p.recovery=maxf(0,p.recovery-delta)
		var old:Vector2=p.pos
		p.pos=p.pos.move_toward(p.target,speed*move_delta)
		p.gaze=(ball-p.pos).normalized()
		p.velocity=(p.pos-old)/maxf(delta,0.001)
		p.motion=p.velocity.length()

func serve() -> void:
	players[serve_team*3].anim="spike"
	players[serve_team*3].action=0.5
	players[serve_team*3].recovery=0.48
	var lane:=aim_lane if serve_team==0 else (rally_count+season)%3
	var end:=Vector2([-3.2,0.0,3.2][lane],4.9*(1 if receiving==0 else -1))
	launch(ball,end,1.85,2.0,"receive",2.6,0.8)
	flight_is_attack=false
	prepare_receive()
	sound.contact(0.3)

func launch(start:Vector2,end:Vector2,duration:float,arc:float,next_phase:String,start_height:float=1.0,end_height:float=1.0) -> void:
	flight_start=start
	flight_end=end
	flight_duration=duration
	flight_elapsed=0
	flight_arc=arc
	flight_start_height=start_height
	flight_end_height=end_height
	phase=next_phase
	phase_time=0
	timing_press=-99
	block_checked=false
	flight_is_attack=false
	flight_source="attack"
	ball_trail.clear()

func prepare_receive() -> void:
	var offset:=receiving*3
	var best:=1000.0
	toucher=offset
	for i in range(offset,offset+3):
		var dist:float=players[i].pos.distance_to(flight_end)
		if dist<best: best=dist; toucher=i
	for i in range(offset,offset+3):
		if i==toucher: players[i].target=flight_end
		else: players[i].target=Vector2([-2.8,0.0,2.8][i%3],3.6*(1 if receiving==0 else -1))
	reaction_remaining=(0.23 if receiving==0 else lerpf(0.42,0.16,float(season)/8.0))
	if receiving==0: reaction_remaining=maxf(0.08,reaction_remaining-upgrades.count("tempo")*0.08)
	if receiving==0:
		if upgrades.has("read") and aim_lane==rival_lane: reaction_remaining=maxf(0.05,reaction_remaining-0.13)
		active=toucher
	# An early scouting cue makes the next attack readable.
	if receiving==1:
		rival_lane=choose_rival_lane()
		rival_shot=choose_rival_shot()

func choose_rival_lane() -> int:
	if season<2: return (rally_count+current_match_contacts/3+season)%3
	var best_lane:=0
	var most_space:=-1.0
	for lane in range(3):
		var target:=Vector2([-3.7,0.0,3.7][lane],6.6)
		var distance:=100.0
		for i in range(3): distance=minf(distance,players[i].pos.distance_to(target))
		if distance>most_space: most_space=distance; best_lane=lane
	return best_lane

func choose_rival_shot() -> int:
	if season==0: return 0 if current_match_contacts%5!=0 else 1
	if season==1: return 1 if current_match_contacts%3==0 else 0
	var average_depth:float=(players[0].pos.y+players[1].pos.y+players[2].pos.y)/3.0
	if season>=3 and average_depth>4.1: return 2
	if season>=6 and absi(aim_lane-rival_lane)==0: return 0
	return 1 if current_match_contacts%3!=1 else 2

func quality() -> float:
	if receiving==1: return lerpf(0.67,0.95,float(season)/8.0)
	var remaining:=flight_duration-timing_press
	var window:=0.13+upgrades.count("window")*0.05
	if timing_press<0:
		timing_result="AUTO • steady"
		return 0.68
	if absf(remaining)<=window:
		timing_result="EXCELLENT"
		return 1.0
	if absf(remaining)<=0.36:
		timing_result="GOOD CONTACT"
		return 0.85
	timing_result="EARLY • steady assist"
	return 0.66

func resolve_contact() -> void:
	if phase=="receive":
		# Everyone can make a last-ditch save; no invisible receiver lockout.
		var best_dist:=100.0
		for i in range(receiving*3,receiving*3+3):
			var d:float=players[i].pos.distance_to(flight_end)
			if d<best_dist: best_dist=d; toucher=i
		var dig_quality:=quality()
		var reach:=1.05+(0.18*upgrades.count("reach") if receiving==0 else 0.0)
		if receiving==0 and squad==0: reach+=0.12
		if dig_quality>=0.95: reach+=0.15
		if best_dist>reach:
			award_point(1-receiving,"BLOCK • no cover underneath" if flight_source=="block" else "OPEN COURT • beyond the dive")
			return
		receive_quality=dig_quality
		contact_quality=receive_quality
		animate_contact(toucher,"receive",contact_quality)
		setter=receiving*3+1
		if setter==toucher: setter=receiving*3+((toucher%3+1)%3)
		var set_pos:=Vector2(-0.7 if setter%3==0 else 0.7,2.1*(1 if receiving==0 else -1))
		players[setter].target=set_pos
		players[toucher].target=Vector2(players[toucher].pos.x,4.8*(1 if receiving==0 else -1))
		var pass_time:=maxf(1.15,players[setter].pos.distance_to(set_pos)/4.15+players[setter].recovery+0.08)
		launch(ball,set_pos,pass_time,1.5,"set",ball_height,2.6)
		if receiving==0: active=setter
	elif phase=="set":
		set_quality=quality()
		if receiving==0: set_quality=minf(1.0,set_quality+upgrades.count("set")*0.08)
		animate_contact(setter,"set",set_quality)
		attacker=pick_attacker()
		var attack_pos:=Vector2([-3.0,0.0,3.0][attacker%3],1.55*(1 if receiving==0 else -1))
		players[attacker].target=attack_pos
		var approach_time:=maxf(1.18,players[attacker].pos.distance_to(attack_pos)/4.15+players[attacker].recovery+0.08)
		launch(ball,attack_pos,approach_time,1.45,"attack",2.6,2.6)
		if receiving==0: active=attacker
		prepare_block()
	elif phase=="attack":
		contact_quality=quality()
		animate_contact(attacker,"spike",contact_quality)
		perform_attack()

func pick_attacker() -> int:
	var choices:Array[int]=[]
	for i in range(receiving*3,receiving*3+3):
		if i!=setter: choices.append(i)
	return choices[attack_choice%2] if receiving==0 else choices[(season+current_match_contacts/3)%2]

func prepare_block() -> void:
	var defending:=1-receiving
	# Rivals increasingly read recent choices; every commitment exposes another lane.
	blocker_lane=aim_lane if defending==0 else (season+round_index)%3
	if defending==1 and season>=2 and last_lane>=0: blocker_lane=last_lane
	if defending==1 and season>=5 and lane_history.size()>=3:
		var counts:=[0,0,0]
		for lane in lane_history: counts[lane]+=1
		blocker_lane=counts.find(counts.max())
	enemy_blocker=defending*3+1
	var x:float=[-2.35,0.0,2.35][blocker_lane]
	players[enemy_blocker].target=Vector2(x,0.75*(1 if defending==0 else -1))
	var bias:=0.0
	var depth:=4.6
	var spread:=1.85
	if defending==1:
		depth=[4.0,4.3,4.5,5.8,5.0,5.5,4.8,5.3,5.0][season]
		spread=[1.65,2.1,1.8,2.0,1.9,1.85,2.15,2.0,2.1][season]
		if season>=4: bias=(blocker_lane-1)*0.95
		if season>=7: bias+=(players[attacker].pos.x/3.0)*0.3
		# Read previous landings, never the player's uncommitted current input.
		rival_cover_short=season>=4 and short_history.count(true)>=2
		if rival_cover_short:
			depth=2.35
			spread=2.8
			bias*=0.25
	else:
		bias=(aim_lane-1)*0.6
	for i in range(defending*3,defending*3+3):
		if i!=enemy_blocker:
			players[i].target=Vector2((-spread if i%3==0 else spread)+bias,depth*(1 if defending==0 else -1))

func target_for(team:int,lane:int,kind:int,deep:bool=true) -> Vector2:
	var y:=7.5 if deep else 4.1
	if kind==2: y=1.6-(0.7*upgrades.count("tip") if team==0 else 0.0)
	return Vector2([-3.8,0.0,3.8][lane],maxf(y,0.8)*(-1 if team==0 else 1))

func perform_attack() -> void:
	var team:=receiving
	var kind:=shot if team==0 else rival_shot
	var lane:=aim_lane if team==0 else rival_lane
	var target:=target_for(team,lane,kind,aim_deep if team==0 else true)
	var q:float=contact_quality*0.50+set_quality*0.30+receive_quality*0.20
	var duration:float=[1.28,0.76,0.91][kind]
	duration*=lerpf(1.18,0.86,q)
	if team==0:
		if kind==1: duration*=pow(0.92,upgrades.count("power"))
		if kind==0: duration*=pow(0.92,upgrades.count("roll"))
		if squad==2 and attacker%3==2: duration*=0.96
		short_history.append(absf(target.y)<4.2)
		if short_history.size()>4: short_history.pop_front()
		lane_history.append(lane)
		if lane_history.size()>6: lane_history.pop_front()
		if last_lane==lane: repeat_lane+=1
		else: repeat_lane=0
		last_lane=lane
	# A clean approach matters: a late hitter makes a safe, slower roll.
	if players[attacker].pos.distance_to(ball)>1.3:
		kind=0
		duration=maxf(duration,1.9)
		feedback="LATE APPROACH • safe roll"
		feedback_timer=1.2
	var arc:float=[2.3,0.55,2.0][kind]
	attack_team=team
	receiving=1-team
	launch(ball,target,duration,arc,"receive",2.6,0.75)
	flight_is_attack=true
	# Store actual shot used, including a safe approach fallback.
	set_meta("flight_kind",kind)
	prepare_receive()
	# Blocker must commit to the net instead of also chasing a deep ball.
	if enemy_blocker>=0 and enemy_blocker!=toucher:
		players[enemy_blocker].target=Vector2([-2.35,0.0,2.35][blocker_lane],0.75*(1 if receiving==0 else -1))

func check_block() -> void:
	if int(get_meta("flight_kind",0))!=1 or enemy_blocker<0: return
	var blocker:Dictionary=players[enemy_blocker]
	if absf(blocker.pos.y)>1.65 or absf(blocker.pos.x-ball.x)>0.8: return
	# Height and hands are shared physical limits for both sides.
	if ball_height>3.3: return
	players[enemy_blocker].anim="block"
	players[enemy_blocker].action=0.5
	players[enemy_blocker].recovery=0.40
	sound.contact(0.9)
	burst(project_ball(),Color("e6f4df"),16)
	feedback="ROOFED! • cover the rebound"
	feedback_timer=1.4
	var defending:=receiving
	receiving=attack_team
	var rebound:=Vector2(clampf(ball.x+0.75,-4.1,4.1),0.35*(1 if receiving==0 else -1))
	launch(ball,rebound,0.34,0.05,"receive",2.6,0.5)
	flight_source="block"
	flight_is_attack=false
	prepare_receive()
	set_meta("last_block_team",defending)

func animate_contact(index:int,animation:String,q:float) -> void:
	players[index].anim=animation
	players[index].action=0.5
	players[index].recovery=0.48 if animation=="spike" else (0.20 if animation=="set" else 0.10)
	rally_contacts+=1
	current_match_contacts+=1
	best_rally=maxi(best_rally,rally_contacts)
	sound.contact(q if animation=="spike" else q*0.45)
	burst(project_ball(),Color("ffe39a") if q>0.95 else Color("fff0d1"),14 if q>0.95 else 7)
	if not reduced_motion: shake=3.5 if animation=="spike" else 1.0
	if receiving==0:
		feedback=timing_result
		feedback_timer=0.9
		if timing_press>=0: practice_touched=true

func award_point(team:int,reason:String) -> void:
	score[team]+=1
	serve_team=team
	phase="point"
	phase_time=0
	point_reason=reason
	feedback="SOL POINT" if team==0 else "RIVAL POINT"
	feedback_timer=2.0
	rally_count+=1
	ball_height=0
	sound.point(team==0)
	for i in range(team*3,team*3+3):
		players[i].anim="celebrate"
		players[i].action=1.0
	burst(project_ball(),Color("f3cb71"),24)
	ledger.append({"season":season+1,"round":round_index+1,"score":score.duplicate(),"reason":reason,"contacts":rally_contacts,"time":snappedf(match_time,0.1)})

func match_over() -> bool:
	return (maxi(score[0],score[1])>=5 and absi(score[0]-score[1])>=2) or maxi(score[0],score[1])>=9

func finish_match() -> void:
	if practice:
		screen="practice_done"
	elif score[0]>score[1]:
		if round_index==2:
			screen="champion"
			if not crowns.has(season+1): crowns.append(season+1)
			unlocked=maxi(unlocked,mini(9,season+2))
			save_progress()
		else:
			screen="upgrade"
			offers.clear()
			# Rotating deterministic draft: always three different functional choices.
			var start: int=(season*2+round_index*3+squad)%UPGRADE_POOL.size()
			for i in range(3): offers.append(UPGRADE_POOL[(start+i*4)%UPGRADE_POOL.size()])
	else:
		screen="defeat"
		upgrades.clear()
	write_run_record()
	ui.rebuild()

func take_upgrade(id:String) -> void:
	upgrades.append(id)
	round_index+=1
	start_match()

func write_run_record() -> void:
	var f:=FileAccess.open(SAVE_PATH.get_basename()+"-last-run.json",FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"season":season+1,"round":round_index+1,"result":screen,"upgrades":upgrades,"rallies":ledger,"seconds":run_time,"best_rally":best_rally},"\t"))

func burst(p:Vector2,col:Color,count:int) -> void:
	for i in range(count):
		var direction:=Vector2.from_angle(float(i)*TAU/count)
		particles.append({"pos":p,"vel":direction*randf_range(40,180),"life":randf_range(0.2,0.65),"color":col})

func _unhandled_key_input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key:int=event.keycode
	if key==KEY_F12:
		capture()
		return
	if key==KEY_F3:
		debug_visible=not debug_visible
		return
	if key==KEY_M:
		sound.toggle()
		save_progress()
		return
	if key==KEY_ESCAPE and screen=="match":
		pause=not pause
		ui.rebuild()
		return
	if screen!="match" or pause: return
	if key in [KEY_LEFT,KEY_A]: aim_lane=maxi(0,aim_lane-1)
	if key in [KEY_RIGHT,KEY_D]: aim_lane=mini(2,aim_lane+1)
	if key in [KEY_UP,KEY_DOWN]: aim_deep=key==KEY_UP
	if key==KEY_Q: shot=0
	if key==KEY_W: shot=1
	if key==KEY_E: shot=2
	if key==KEY_TAB:
		attack_choice=(attack_choice+1)%2
		if receiving==0 and phase=="attack":
			# A route is committed once the set leaves the setter's hands.
			toast="Attacker queued for your next set"
			toast_time=1.6
	if key==KEY_SPACE:
		if phase=="serve" and serve_team==0: phase_time=maxf(phase_time,1.55)
		elif receiving==0 and phase in ["receive","set","attack"]:
			timing_press=flight_elapsed
			sound.tone(660,0.05,0.035)
	get_viewport().set_input_as_handled()

func capture() -> void:
	await RenderingServer.frame_post_draw
	var path:="user://spike-season-%d.png"%Time.get_unix_time_from_system()
	get_viewport().get_texture().get_image().save_png(path)
	toast="Screenshot saved to user data"
	toast_time=2
	print("SCREENSHOT "+ProjectSettings.globalize_path(path))

func project_ball() -> Vector2:
	return scenery.court(ball)-Vector2(0,ball_height*(75+(ball.y+8)*1.2))

func _draw() -> void:
	if players.is_empty(): return
	var camera_offset:=Vector2(sin(time*91),cos(time*77))*shake if not reduced_motion else Vector2.ZERO
	draw_set_transform(camera_offset)
	# Projected shadows anchor all six athletes and the ball to the clay.
	for i in range(6):
		var p:Vector2=scenery.court(players[i].pos)
		var shadow_scale:float=0.91+(players[i].pos.y+8)*0.032
		painter.draw_shadow(self,p,shadow_scale,players[i],time,Color("c6af80") if season/3==1 else Color("cfa276"))
		draw_set_transform(camera_offset)
	if screen=="match":
		var selected_pos:Vector2=scenery.court(players[active].pos)
		draw_set_transform(selected_pos+camera_offset,0,Vector2(1,0.34))
		draw_arc(Vector2.ZERO,31,0,TAU,48,Color("ffe18a"),4,true)
		draw_arc(Vector2.ZERO,35,0,TAU,48,Color(1,0.91,0.59,0.3),2,true)
		draw_set_transform(camera_offset)
		# Dashed target is the chosen landing zone, not a promise of a point.
		var aim:Vector2=scenery.court(target_for(0,aim_lane,shot,aim_deep))
		draw_set_transform(aim+camera_offset,0,Vector2(1,0.36))
		for i in range(8): draw_arc(Vector2.ZERO,23,i*TAU/8,i*TAU/8+0.42,6,Color("fff2bf"),2,true)
		draw_set_transform(camera_offset)
		draw_string(ThemeDB.fallback_font,aim+Vector2(-14,21),"AIM",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("fff4d6"))
		if phase in ["receive","set","attack"]:
			var landing:Vector2=scenery.court(flight_end)
			draw_set_transform(landing+camera_offset,0,Vector2(1,0.35))
			draw_arc(Vector2.ZERO,16,0,TAU,36,Color(1,0.98,0.82,0.8),2,true)
			draw_set_transform(camera_offset)
		if receiving==1 and phase in ["set","attack"] and upgrades.has("read"):
			var danger:Vector2=scenery.court(target_for(1,rival_lane,rival_shot))
			draw_arc(danger,24,0,TAU,32,Color("d77857"),3,true)
	var order:Array[int]=[0,1,2,3,4,5]
	order.sort_custom(func(a,b): return players[a].pos.y<players[b].pos.y)
	for i in order:
		if players[i].pos.y<=0: draw_athlete(i)
	draw_net()
	for i in order:
		if players[i].pos.y>0: draw_athlete(i)
	if screen=="match":
		var floor_pos:Vector2=scenery.court(ball)
		draw_set_transform(floor_pos+camera_offset,0,Vector2(1,0.32))
		draw_circle(Vector2.ZERO,maxf(4,12-ball_height),Color(0.15,0.24,0.23,0.32))
		draw_set_transform(camera_offset)
		for i in range(ball_trail.size()-1,0,-1):
			draw_line(ball_trail[i],ball_trail[i-1],Color(1,0.94,0.71,0.22*(1-float(i)/9)),maxf(2,12-i),true)
		draw_volleyball(project_ball(),12+(ball.y+8)*0.14)
	for p in particles:
		var c:Color=p.color
		c.a=minf(1,p.life*2)
		draw_circle(p.pos,2.5,c)
	draw_set_transform(Vector2.ZERO)

func draw_athlete(i:int) -> void:
	var p:Vector2=players[i].pos
	painter.draw_player(self,scenery.court(p),0.91+(p.y+8)*0.032,players[i],time,i==active and screen=="match")

func draw_net() -> void:
	var a:Vector2=scenery.court(Vector2(-4.65,0))
	var b:Vector2=scenery.court(Vector2(4.65,0))
	var h:=183.0
	for i in range(45):
		var x:=lerpf(a.x,b.x,float(i)/44)
		draw_line(Vector2(x,a.y-h+3),Vector2(x,a.y-102),Color(0.15,0.28,0.28,0.54),0.9,true)
	for j in range(10): draw_line(Vector2(a.x,a.y-h+j*9),Vector2(b.x,b.y-h+j*9),Color(0.13,0.27,0.28,0.55),0.9,true)
	draw_line(a-Vector2(0,h),b-Vector2(0,h),Color("fff2d2"),6,true)
	draw_line(a-Vector2(0,102),b-Vector2(0,102),Color("ded5ae"),3,true)
	for p in [a,b]:
		draw_line(p+Vector2(0,5),p-Vector2(0,210),Color("355e69"),10,true)
		draw_line(p+Vector2(-2,3),p-Vector2(2,65),Color("407683"),15,true)
		draw_line(p-Vector2(0,185),p-Vector2(0,225),Color("f5e7c8"),3,true)
		for j in range(3): draw_line(p-Vector2(0,191+j*12),p-Vector2(0,197+j*12),Color("ca7860"),3,true)

func draw_volleyball(p:Vector2,r:float) -> void:
	draw_circle(p+Vector2(2,3),r+1,Color(0.1,0.23,0.26,0.2))
	draw_circle(p,r+1.5,Color("294a51"))
	draw_circle(p,r,Color("fff1cc"))
	for i in range(3):
		var ang:=ball_spin+float(i)*TAU/3.0
		var points:=PackedVector2Array([p])
		for j in range(10): points.append(p+Vector2.from_angle(ang+j*0.095)*r)
		draw_colored_polygon(points,Color("dfb249") if i==0 else Color("406477"))
		draw_arc(p,r*0.72,ang,ang+1.0,12,Color("365361"),0.7,true)
	draw_arc(p-Vector2(2,3),r*0.7,3.4,4.5,12,Color(1,1,0.91,0.8),2,true)

func refresh_scenery() -> void:
	scenery.queue_redraw()
	scenery_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
