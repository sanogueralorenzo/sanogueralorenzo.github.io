extends SceneTree
## Real CharacterBody movement through normal gameplay, with repeatable evidence.
var app
var player
var failures: Array[String]=[]
var evidence="/tmp/sunny-bay-evidence"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	while app.screen!=app.Screen.PLAYING:await process_frame
	player=app.player
	player.mouse_capture_enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await create_timer(.5).timeout
	await capture("01-harbor")
	for i in range(1,app.map.LOOP.size()):
		await walk_to(app.map.LOOP[i],"loop-%02d"%i)
		if i in [2,4,5,6,7,9]:await capture("walk-%02d"%i)
	await walk_to(Vector2(-8,8),"pier approach")
	await walk_to(Vector2(-8,-19),"fishing spot")
	await capture("pier")
	print("SUNNY_VERIFY walking failures=",failures)
	quit(0 if failures.is_empty() else 1)
func walk_to(target: Vector2,label: String) -> void:
	var started=Time.get_ticks_msec()
	var start=player.position
	while Vector2(player.position.x,player.position.z).distance_to(target)>.5:
		if player.menu_open:player.set_menu(false)
		var d=target-Vector2(player.position.x,player.position.z)
		player.cam_yaw=atan2(d.x,-d.y)
		player.cam_pitch=.14
		player.touch_move=Vector2(0,-1)
		if Time.get_ticks_msec()-started>30000:
			failures.append(label+" blocked at "+str(player.position))
			break
		await physics_frame
	player.touch_move=Vector2.ZERO
	await create_timer(.4).timeout
	print("SUNNY_VERIFY ",label," from=",start," to=",player.position," grounded=",player.grounded)
func capture(label: String) -> void:
	if player.menu_open:player.set_menu(false)
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
