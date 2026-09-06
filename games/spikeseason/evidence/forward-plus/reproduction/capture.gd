extends SceneTree
# Disposable manual capture session. Drives no input, scoring or assertions.
var game:Node
var frame:=0
var scene_number:=1
var capture_frame:=1
var shader_materials:Array[ShaderMaterial]=[]
var output:="/tmp/spikeseason-forward-review/evidence/matched"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--venue="): scene_number=int(arg.get_slice("=",1))
		if arg.begins_with("--capture-frame="): capture_frame=int(arg.get_slice("=",1))
		if arg.begins_with("--output="): output=arg.get_slice("=",1)
	_start.call_deferred()
func _start() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_run(scene_number-1)
	game.reduced_motion=false
	game.ui.rebuild()
	# Fixed frame scheduling repeats ordinary simulation and authored camera.
	_collect_materials(game)
	RenderingServer.frame_post_draw.connect(_frame_drawn)
func _frame_drawn() -> void:
	frame+=1
	for material in shader_materials: material.set_shader_parameter("capture_time",float(frame)/60.0)
	if frame==capture_frame:
		var bridge=game.get_node_or_null("ReviewBridge")
		root.get_texture().get_image().save_png(output+".png")
		var f=FileAccess.open(output+".json",FileAccess.WRITE)
		f.store_string(JSON.stringify({"frame":frame,"season":scene_number,"camera":game.scenery.camera.transform,"match_time":game.match_time,"phase":game.phase,"ball":game.ball,"ball_height":game.ball_height,"players":game.players,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"window":DisplayServer.window_get_size()},"\t"))
		quit()

func _collect_materials(node:Node) -> void:
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		if not shader_materials.has(node.material_override): shader_materials.append(node.material_override)
	if node is WorldEnvironment and node.environment.sky:
		shader_materials.append(node.environment.sky.sky_material)
	for child in node.get_children(): _collect_materials(child)
