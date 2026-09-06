extends SceneTree
# Manual fixed-rate movie capture: normal game logic, a single chosen starting shot.
var game:Node
var frames:=0
var duration:=900
var venue:=1
var chosen_shot:=0
var chosen_lane:=1
var use_review_taa:=false
var use_review_ssr:=false
var shader_materials:Array[ShaderMaterial]=[]
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--taa-review": use_review_taa=true
		if arg=="--ssr-review": use_review_ssr=true
		if arg.begins_with("--venue="): venue=int(arg.get_slice("=",1))
		if arg.begins_with("--frames="): duration=int(arg.get_slice("=",1))
		if arg.begins_with("--shot="): chosen_shot=int(arg.get_slice("=",1))
		if arg.begins_with("--lane="): chosen_lane=int(arg.get_slice("=",1))
	_start.call_deferred()
func _start() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_run(venue-1)
	game.reduced_motion=false
	# Equivalent to choosing one lane/shot before the serve; there is no adaptive bot.
	game.shot=chosen_shot
	game.aim_lane=chosen_lane
	game.ui.rebuild()
	_collect_materials(game)
	if use_review_taa: root.use_taa=true; root.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	if use_review_ssr: game.scenery.environment.ssr_enabled=true
	RenderingServer.frame_post_draw.connect(_frame_drawn)
func _frame_drawn() -> void:
	frames+=1
	for material in shader_materials: material.set_shader_parameter("capture_time",float(frames)/60.)
	if frames>=duration: quit()

func _collect_materials(node:Node) -> void:
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		if not shader_materials.has(node.material_override): shader_materials.append(node.material_override)
	if node is WorldEnvironment and node.environment.sky:
		shader_materials.append(node.environment.sky.sky_material)
	for child in node.get_children(): _collect_materials(child)
