extends Node
## Opt-in local runtime review console. No bots, assertions, score/unlock overrides or tests.
## Every play command uses the same match/menu functions as the native controls.
var game: Node
var server:=TCPServer.new()
var peers: Array[Dictionary]=[]
var capture_requested:=false
var frame_milliseconds:Array[float]=[]
var previous_frame_usec:=0
var capture_name:="runtime"
var capture_dir:="user://review-captures"

func start(port:int,directory:String) -> void:
	capture_dir=directory
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var err:=server.listen(port,"127.0.0.1")
	if err!=OK: push_error("Review console port unavailable")
	else: print("REVIEW listening on 127.0.0.1:%d"%port)

func _process(_delta:float) -> void:
	var now:=Time.get_ticks_usec()
	if previous_frame_usec>0:
		frame_milliseconds.append(float(now-previous_frame_usec)/1000.0)
		if frame_milliseconds.size()>600: frame_milliseconds.pop_front()
	previous_frame_usec=now
	if server.is_connection_available(): peers.append({"peer":server.take_connection(),"buffer":""})
	for item in peers:
		var peer:StreamPeerTCP=item.peer
		peer.poll()
		if peer.get_status()!=StreamPeerTCP.STATUS_CONNECTED: continue
		var count:=peer.get_available_bytes()
		if count>0: item.buffer+=peer.get_utf8_string(count)
		if "\n" in item.buffer:
			var request=JSON.parse_string(item.buffer.get_slice("\n",0))
			item.buffer=""
			var result:Dictionary=handle(request if request is Dictionary else {})
			peer.put_data((JSON.stringify(result)+"\n").to_utf8_buffer())
			peer.disconnect_from_host()
	peers=peers.filter(func(p): return p.peer.get_status()!=StreamPeerTCP.STATUS_NONE)
	if capture_requested:
		capture_requested=false
		capture.call_deferred()

func handle(r:Dictionary) -> Dictionary:
	match str(r.get("action","state")):
		"input":
			var keys:={"left":KEY_LEFT,"right":KEY_RIGHT,"up":KEY_UP,"down":KEY_DOWN,"roll":KEY_Q,"power":KEY_W,"tip":KEY_E,"attacker":KEY_TAB,"contact":KEY_SPACE,"pause":KEY_ESCAPE}
			if keys.has(r.get("key","")):
				var event:=InputEventKey.new()
				event.keycode=keys[r.key]
				event.pressed=true
				game._unhandled_key_input(event)
		"menu":
			var choice:=str(r.get("choice",""))
			if choice=="seasons" and game.screen!="match": game.screen="seasons"; game.ui.rebuild()
			if choice=="practice" and game.screen!="match": game.start_run(0,true)
			if choice=="play" and game.screen!="match":
				game.squad=clampi(int(r.get("squad",0)),0,2)
				game.start_run(int(r.get("season",1))-1)
			if choice=="upgrade" and game.screen=="upgrade":
				var index:=clampi(int(r.get("index",0)),0,2)
				game.take_upgrade(game.offers[index].id)
			if choice=="leave" and game.screen=="match" and game.pause:
				game.pause=false; game.upgrades.clear(); game.screen="seasons"; game.ui.rebuild()
		"speed":
			Engine.time_scale=clampf(float(r.get("value",1)),0.05,4)
		"camera":
			# Opt-in inspection only; ordinary captures use the authored rally camera.
			game.scenery.inspection_camera=not bool(r.get("reset",false))
			if r.has("position"):
				var p:Array=r.position
				game.scenery.camera.position=Vector3(p[0],p[1],p[2])
			if r.has("look_at"):
				var p:Array=r.look_at
				game.scenery.camera.look_at(Vector3(p[0],p[1],p[2]))
		"capture":
			capture_requested=true
			capture_name=str(r.get("name","runtime")).validate_filename()
	return state()

func state() -> Dictionary:
	var ps:Array=[]
	for p in game.players: ps.append({"id":p.id,"team":p.team,"x":snappedf(p.pos.x,0.01),"y":snappedf(p.pos.y,0.01),"target":[p.target.x,p.target.y],"anim":p.anim,"action":p.action,"contact_blend":p.get("contact_blend",0.0),"contact_error":game.scenery.actors[p.team*3+p.id].contact_error,"contact_anchor":game.scenery.actors[p.team*3+p.id].contact_anchor,"missed_dig":game.scenery.actors[p.team*3+p.id].missed_dig,"hands":game.scenery.actors[p.team*3+p.id].hand_world,"feet_world":game.scenery.actors[p.team*3+p.id].feet_world,"feet_yaw":game.scenery.actors[p.team*3+p.id].feet_yaw,"root_yaw":game.scenery.actors[p.team*3+p.id].rotation.y,"swinging":game.scenery.actors[p.team*3+p.id].swinging,"turn_step":game.scenery.actors[p.team*3+p.id].turn_step})
	return {"performance":performance_snapshot(),"hud_compact_right":game.ui.collapse_right,"hud_compact_left":game.ui.collapse_left,"camera_inspection":game.scenery.inspection_camera,"camera_position":game.scenery.camera.position,"ball_world":game.scenery.volleyball.position,"screen":game.screen,"paused":game.pause,"season":game.season+1,"round":game.round_index+1,"score":game.score,"phase":game.phase,"receiving":game.receiving,"flight_remaining":snappedf(game.flight_duration-game.flight_elapsed,0.01),"aim":game.aim_lane,"shot":game.shot,"block_lane":game.blocker_lane,"rival_lane":game.rival_lane,"rival_shot":game.rival_shot,"rival_deep_lane":game.rival_deep_lane,"landing_history":game.landing_history,"route_history":game.route_history,"rival_cover_short":game.rival_cover_short,"short_history":game.short_history,"contacts":game.rally_contacts,"best_rally":game.best_rally,"match_seconds":snappedf(game.match_time,0.1),"run_seconds":snappedf(game.run_time,0.1),"feedback":game.feedback,"upgrades":game.upgrades,"offers":game.offers,"unlocked":game.unlocked,"crowns":game.crowns,"ledger":game.ledger,"players":ps,"fps":Engine.get_frames_per_second(),"speed":Engine.time_scale,"save_error":game.save_error}

func capture() -> void:
	await RenderingServer.frame_post_draw
	var path:=capture_dir.path_join(capture_name+".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("REVIEW capture "+ProjectSettings.globalize_path(path))

func performance_snapshot() -> Dictionary:
	if frame_milliseconds.is_empty(): return {}
	var sorted:=frame_milliseconds.duplicate()
	sorted.sort()
	var total:=0.0
	for value in sorted: total+=value
	return {"frames":sorted.size(),"seconds":total/1000.0,"mean_ms":total/sorted.size(),"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"worst_ms":sorted[-1],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
