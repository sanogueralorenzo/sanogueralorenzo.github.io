extends Node
## Opt-in local runtime review console. No bots, assertions, score/unlock overrides or tests.
## Every play command uses the same match/menu functions as the native controls.
var game: Node
var server:=TCPServer.new()
var peers: Array[Dictionary]=[]
var capture_requested:=false
var capture_name:="runtime"
var capture_dir:="user://review-captures"

func start(port:int,directory:String) -> void:
	capture_dir=directory
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var err:=server.listen(port,"127.0.0.1")
	if err!=OK: push_error("Review console port unavailable")
	else: print("REVIEW listening on 127.0.0.1:%d"%port)

func _process(_delta:float) -> void:
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
		"capture":
			capture_requested=true
			capture_name=str(r.get("name","runtime")).validate_filename()
	return state()

func state() -> Dictionary:
	var ps:Array=[]
	for p in game.players: ps.append({"id":p.id,"team":p.team,"x":snappedf(p.pos.x,0.01),"y":snappedf(p.pos.y,0.01),"target":[p.target.x,p.target.y],"anim":p.anim})
	return {"screen":game.screen,"paused":game.pause,"season":game.season+1,"round":game.round_index+1,"score":game.score,"phase":game.phase,"receiving":game.receiving,"flight_remaining":snappedf(game.flight_duration-game.flight_elapsed,0.01),"aim":game.aim_lane,"shot":game.shot,"block_lane":game.blocker_lane,"rival_lane":game.rival_lane,"rival_shot":game.rival_shot,"rival_cover_short":game.rival_cover_short,"short_history":game.short_history,"contacts":game.rally_contacts,"best_rally":game.best_rally,"match_seconds":snappedf(game.match_time,0.1),"run_seconds":snappedf(game.run_time,0.1),"feedback":game.feedback,"upgrades":game.upgrades,"offers":game.offers,"unlocked":game.unlocked,"crowns":game.crowns,"ledger":game.ledger,"players":ps,"fps":Engine.get_frames_per_second(),"speed":Engine.time_scale,"save_error":game.save_error}

func capture() -> void:
	await RenderingServer.frame_post_draw
	var path:=capture_dir.path_join(capture_name+".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("REVIEW capture "+ProjectSettings.globalize_path(path))
