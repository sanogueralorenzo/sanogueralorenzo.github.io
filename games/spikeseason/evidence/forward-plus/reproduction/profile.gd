extends SceneTree
# Measurement-only harness: ordinary unassisted default-input match, no assertions.
var game:Node
var bridge:Node
var started:=false
var measuring:=false
var measurement_start:=0
var venue:=1
var output:="/tmp/spikeseason-forward-review/evidence/profile"
var seconds:=30.0
var uncapped:=false
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--venue="): venue=int(arg.get_slice("=",1))
		if arg.begins_with("--output="): output=arg.get_slice("=",1)
		if arg.begins_with("--seconds="): seconds=float(arg.get_slice("=",1))
		if arg=="--uncapped-review": uncapped=true
	_start.call_deferred()
func _start() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_run(venue-1)
	game.reduced_motion=false
	for child in game.get_children():
		if child.has_method("performance_snapshot"): bridge=child
	if uncapped:
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	started=true
func _process(_delta:float) -> bool:
	if not started: return false
	if not measuring and game.match_time>=15.0:
		bridge.handle({"action":"performance","reset":true,"frames":18000})
		measurement_start=Time.get_ticks_usec()
		measuring=true
		print("MEASURE pid=",OS.get_process_id()," warmup_match_seconds=",game.match_time)
	if measuring and float(Time.get_ticks_usec()-measurement_start)/1000000.0>=seconds:
		var data=bridge.handle({"action":"performance","record":false})
		data["measurement"]={"warmup_match_seconds":15,"wall_seconds":seconds,"uncapped":uncapped,"pid":OS.get_process_id(),"inputs":"unchanged defaults; full motion; ordinary match and camera"}
		var f=FileAccess.open(output+".json",FileAccess.WRITE)
		f.store_string(JSON.stringify(data,"\t"))
		print("MEASURE complete ",output)
		quit()
	return false
