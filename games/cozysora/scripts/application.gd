extends Node
## Persistent navigation and settings own one disposable gameplay session at a time.
const UI = preload("res://scripts/ui_theme.gd")
const REGISTRY = preload("res://maps/registry.tres")
enum Screen {SELECTOR, LOADING, PLAYING, PAUSED, RETURNING, ERROR}
var screen := Screen.SELECTOR
var session: Node3D
var map: CozyMap
var player: CozyPlayer
var landing: CozyLanding
var hud: CozyInterface
var touch: CozyTouchControls
var canvas: CanvasLayer
var transition: Control
var transition_title: Label
var transition_message: Label
var progress: ProgressBar
var error_back: Button
var settings: Control
var settings_back: Button
var settings_column: VBoxContainer
var settings_visible := false
var touch_enabled := DisplayServer.is_touchscreen_available()
var volume := 1.0
var muted := false
var active_destination: CozyMapDefinition
var _capture := ""
var _capture_dir := ""
var _capture_views: Array = []
var _capture_frames := 0
var _profile := false
var _profile_clock := 0.0
var _shot := false
var _quitting := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	CozyPlayer.configure_input()
	_load_settings()
	get_viewport().size_changed.connect(_resize_settings)
	var automatic_id: StringName = &""
	for arg in OS.get_cmdline_user_args():
		if arg=="--profile":_profile=true
		if arg=="--touch":touch_enabled=true
		if arg=="--shot" or arg.begins_with("--view=") or arg.begins_with("--capture-dir="):_shot=true
		if arg.begins_with("--map="):automatic_id=StringName(arg.trim_prefix("--map="))
		if arg.begins_with("--capture="):_capture=arg.trim_prefix("--capture=")
		if arg.begins_with("--capture-dir="):_capture_dir=arg.trim_prefix("--capture-dir=")
	canvas=CanvasLayer.new()
	canvas.layer=20
	add_child(canvas)
	landing=CozyLanding.new()
	canvas.add_child(landing)
	var invalid:String=REGISTRY.validation_error()
	if invalid.is_empty():landing.setup(REGISTRY.maps)
	landing.play_requested.connect(_enter_map)
	landing.settings_requested.connect(_open_settings)
	hud=CozyInterface.new()
	canvas.add_child(hud)
	hud.hide()
	hud.pause_requested.connect(func():if player!=null:player.set_menu(true))
	hud.resume_requested.connect(func():if player!=null:player.set_menu(false))
	hud.destinations_requested.connect(_return_to_selector)
	hud.settings_requested.connect(_open_settings)
	hud.character_requested.connect(func(mode:String):if player!=null:player.set_mode(mode))
	touch=CozyTouchControls.new()
	canvas.add_child(touch)
	touch.hide()
	_build_transition()
	if not invalid.is_empty():_show_error(invalid);return
	if _shot and automatic_id.is_empty():automatic_id=REGISTRY.maps[0].id
	if not automatic_id.is_empty():_enter_map.call_deferred(automatic_id)
	else:_report_session("selector")

func _enter_map(id:StringName) -> void:
	if screen!=Screen.SELECTOR or settings_visible:return
	var destination:CozyMapDefinition=REGISTRY.find_map(id)
	if destination==null:_show_error("That destination is unavailable.");return
	screen=Screen.LOADING
	active_destination=destination
	landing.set_busy(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await _cover("On our way to "+destination.title,"Packing a little summer…")
	landing.hide()
	var started:=Time.get_ticks_msec()
	var request:=ResourceLoader.load_threaded_request(destination.scene)
	if request!=OK:_show_error("We couldn't open this destination. Please try again.");return
	while ResourceLoader.load_threaded_get_status(destination.scene)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(destination.scene)!=ResourceLoader.THREAD_LOAD_LOADED:
		_show_error("We couldn't open this destination. Please try again.");return
	var loaded:Resource=ResourceLoader.load_threaded_get(destination.scene)
	if not loaded is PackedScene:
		_show_error("This destination scene is not a playable scene.");return
	var instance:Node=(loaded as PackedScene).instantiate()
	if not instance is CozyMap:
		instance.free()
		_show_error("This destination couldn't be prepared.");return
	session=Node3D.new()
	session.name="GameplaySession"
	session.process_mode=Node.PROCESS_MODE_DISABLED
	add_child(session)
	session.hide()
	map=instance
	session.add_child(map)
	map.load_progress.connect(_loading_progress)
	await map.build()
	player=CozyPlayer.new()
	session.add_child(player)
	player.shot_mode=_shot
	player.mouse_capture_enabled=not touch_enabled
	player.setup(map,destination.spawn())
	player.menu_changed.connect(_menu_changed)
	player.mode_changed.connect(_character_changed)
	touch.player=player
	hud.configure(destination.title)
	_character_changed(player.mode)
	progress.value=100
	transition_message.text="Your summer is ready."
	session.show()
	await get_tree().physics_frame
	await get_tree().process_frame
	# Recheck camera collision after newly built collision shapes enter physics space.
	if not player.fixed_view:player._place_camera(.016,true)
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_capture_views=map.scenic_views.keys()
		_capture=_capture_dir.path_join("start.png")
	await _uncover()
	screen=Screen.PLAYING
	session.process_mode=Node.PROCESS_MODE_INHERIT
	hud.visible=not _shot
	hud.set_paused(false)
	if not _shot:player.set_menu(false)
	touch.visible=touch_enabled and not _shot
	_capture_frames=0
	print("Cozy Sora MAP_READY id=",id," build_ms=",Time.get_ticks_msec()-started)
	_report_session("playing")

func _menu_changed(open:bool) -> void:
	if screen not in [Screen.PLAYING,Screen.PAUSED]:return
	screen=Screen.PAUSED if open else Screen.PLAYING
	session.process_mode=Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
	if player.audio!=null:player.audio.stream_paused=open
	map.set_paused(open)
	hud.set_paused(open)
	touch.visible=touch_enabled and not open
	_report_session("paused" if open else "playing")

func _character_changed(mode:String) -> void:
	hud.set_character(mode,touch_enabled)
	touch.queue_redraw()

func _return_to_selector() -> void:
	if settings_visible:return
	if screen not in [Screen.PAUSED,Screen.PLAYING,Screen.ERROR]:return
	screen=Screen.RETURNING
	if session!=null:
		session.process_mode=Node.PROCESS_MODE_DISABLED
		if player!=null and player.audio!=null:player.audio.stream_paused=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	touch.hide()
	hud.hide()
	await _cover("Cozy Sora","Returning to destinations…")
	_free_session()
	await get_tree().process_frame
	await get_tree().physics_frame
	landing.show()
	landing.set_busy(false)
	await _uncover()
	screen=Screen.SELECTOR
	landing.focus_default()
	_report_session("selector")

func _free_session() -> void:
	touch.player=null
	player=null
	map=null
	active_destination=null
	if is_instance_valid(session):session.queue_free()
	session=null
	RenderingServer.global_shader_parameter_set("cat_position",Vector3(0,-100,0))

func _unhandled_input(event:InputEvent) -> void:
	if settings_visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cozy_pause"):
			_close_settings()
			get_viewport().set_input_as_handled()
	elif screen==Screen.PAUSED and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("cozy_pause")):
		player.set_menu(false)
		get_viewport().set_input_as_handled()

func _process(delta:float) -> void:
	if is_instance_valid(player):RenderingServer.global_shader_parameter_set("cat_position",player.global_position)
	if _profile:
		_profile_clock+=delta
		if _profile_clock>5:
			_profile_clock=0
			print("Cozy Sora RUNTIME screen=",Screen.keys()[screen]," fps=",Engine.get_frames_per_second()," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000," viewport=",get_viewport().get_visible_rect().size," audio_db=",AudioServer.get_bus_peak_volume_left_db(0,0))
			if is_instance_valid(player):print("Cozy Sora PLAYER mode=",player.mode," position=",player.position," grounded=",player.grounded," perched=",player.perched)
	if not _capture.is_empty() and screen in [Screen.SELECTOR,Screen.PLAYING] and not _quitting:
		_capture_frames+=1
		if _capture_frames==45:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_capture)
			print("Cozy Sora CAPTURE ",_capture)
			if not _capture_views.is_empty():
				var view:String=_capture_views.pop_front()
				player.set_view(view)
				_capture=_capture_dir.path_join(view+".png")
				_capture_frames=0
			elif "--quit-after-capture" in OS.get_cmdline_user_args():
				_quitting=true
				get_tree().quit()
			else:_capture=""

func _report_session(label:String) -> void:
	if not _profile:return
	var counts:Dictionary={"players":0,"cameras":0,"audio":0}
	_count_nodes(get_tree().root,counts)
	print("Cozy Sora SESSION ",label," active=",int(is_instance_valid(session))," players=",counts.players," cameras=",counts.cameras," audio=",counts.audio," orphans=",Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _count_nodes(node:Node,counts:Dictionary) -> void:
	if node is CozyPlayer:counts.players+=1
	if node is Camera3D:counts.cameras+=1
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:counts.audio+=1
	for child in node.get_children():_count_nodes(child,counts)

func _build_transition() -> void:
	transition=Control.new()
	transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition.theme=UI.make_theme()
	canvas.add_child(transition)
	var shade:=ColorRect.new()
	shade.color=Color("edf0df")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition.add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition.add_child(center)
	var margin:=MarginContainer.new()
	margin.add_theme_constant_override("margin_left",24)
	margin.add_theme_constant_override("margin_right",24)
	center.add_child(margin)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",20)
	margin.add_child(column)
	transition_title=Label.new()
	transition_title.add_theme_font_override("font",UI.title_font())
	transition_title.add_theme_font_size_override("font_size",30)
	transition_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	transition_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(transition_title)
	transition_message=Label.new()
	transition_message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	transition_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(transition_message)
	progress=ProgressBar.new()
	progress.show_percentage=false
	progress.custom_minimum_size.y=6
	progress.add_theme_stylebox_override("background",UI.panel(Color("d4dfcd"),3))
	progress.add_theme_stylebox_override("fill",UI.panel(Color("4c7464"),3))
	column.add_child(progress)
	error_back=Button.new()
	error_back.text="Back to destinations"
	error_back.custom_minimum_size.y=52
	error_back.pressed.connect(_return_to_selector)
	column.add_child(error_back)
	get_viewport().size_changed.connect(func():column.custom_minimum_size.x=minf(480,get_viewport().get_visible_rect().size.x-48))
	column.custom_minimum_size.x=minf(480,get_viewport().get_visible_rect().size.x-48)
	transition.hide()

func _cover(title:String,message:String) -> void:
	transition_title.text=title
	transition_message.text=message
	progress.value=0
	progress.show()
	error_back.hide()
	transition.modulate.a=0
	transition.show()
	var fade:=create_tween()
	fade.tween_property(transition,"modulate:a",1.0,.22)
	await fade.finished

func _uncover() -> void:
	var fade:=create_tween()
	fade.tween_property(transition,"modulate:a",0.0,.32)
	await fade.finished
	transition.hide()

func _loading_progress(message:String,fraction:float) -> void:
	transition_message.text=message
	progress.value=fraction*100

func _show_error(message:String) -> void:
	screen=Screen.ERROR
	_free_session()
	transition.show()
	transition.modulate.a=1
	transition_title.text="A little detour"
	transition_message.text=message
	progress.hide()
	error_back.show()
	error_back.grab_focus.call_deferred()

func _load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")==OK:
		volume=clampf(config.get_value("audio","volume",1.0),0,1)
		muted=bool(config.get_value("audio","muted",false))
		touch_enabled=bool(config.get_value("input","touch",touch_enabled))
	_apply_audio()

func _save_settings() -> void:
	var config:=ConfigFile.new()
	config.set_value("audio","volume",volume)
	config.set_value("audio","muted",muted)
	config.set_value("input","touch",touch_enabled)
	config.save("user://settings.cfg")
	_apply_audio()

func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.001,volume)))
	AudioServer.set_bus_mute(0,muted)

func _open_settings() -> void:
	if settings_visible or screen not in [Screen.SELECTOR,Screen.PAUSED]:return
	settings_visible=true
	landing.hide()
	hud.hide()
	settings=Control.new()
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.theme=UI.make_theme()
	canvas.add_child(settings)
	var shade:=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color("e7edde") if screen==Screen.SELECTOR else Color(.03,.1,.1,.65)
	settings.add_child(shade)
	var scroll:=ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	settings.add_child(scroll)
	var center:=CenterContainer.new()
	center.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	center.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel:=PanelContainer.new()
	var style:=UI.panel(UI.PAPER,20)
	for side in ["left","top","right","bottom"]:style.set("content_margin_"+side,24)
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	var column:=VBoxContainer.new()
	settings_column=column
	_resize_settings()
	column.add_theme_constant_override("separation",16)
	panel.add_child(column)
	var heading:=Label.new()
	heading.text="Make yourself at home"
	heading.add_theme_font_override("font",UI.title_font())
	heading.add_theme_font_size_override("font_size",25)
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	var audio_label:=Label.new()
	audio_label.text="Sound · "+str(roundi(volume*100))+"%"
	column.add_child(audio_label)
	var slider:=HSlider.new()
	slider.max_value=1
	slider.step=.05
	slider.value=volume
	slider.custom_minimum_size.y=48
	slider.value_changed.connect(func(value:float):volume=value;audio_label.text="Sound · "+str(roundi(value*100))+"%";_save_settings())
	column.add_child(slider)
	var mute:=CheckButton.new()
	mute.text="Mute sound"
	mute.button_pressed=muted
	mute.custom_minimum_size.y=48
	UI.secondary(mute)
	mute.toggled.connect(func(value:bool):muted=value;_save_settings())
	column.add_child(mute)
	var touch_option:=CheckButton.new()
	touch_option.text="Touch controls"
	touch_option.button_pressed=touch_enabled
	touch_option.custom_minimum_size.y=48
	UI.secondary(touch_option)
	touch_option.toggled.connect(func(value:bool):
		touch_enabled=value
		if player!=null:player.mouse_capture_enabled=not value;_character_changed(player.mode)
		_save_settings())
	column.add_child(touch_option)
	settings_back=Button.new()
	settings_back.text="Done"
	settings_back.custom_minimum_size.y=52
	settings_back.pressed.connect(_close_settings)
	column.add_child(settings_back)
	var focus_controls:Array[Control]=[slider,mute,touch_option,settings_back]
	for i in focus_controls.size():
		var current:Control=focus_controls[i]
		current.focus_next=current.get_path_to(focus_controls[(i+1)%focus_controls.size()])
		current.focus_previous=current.get_path_to(focus_controls[posmod(i-1,focus_controls.size())])
		current.focus_neighbor_bottom=current.focus_next
		current.focus_neighbor_top=current.focus_previous
	slider.add_theme_stylebox_override("focus",UI.make_theme().get_stylebox("focus","Button"))
	settings_back.grab_focus()

func _close_settings() -> void:
	if not settings_visible:return
	settings_visible=false
	settings.queue_free()
	settings=null
	settings_column=null
	if screen==Screen.SELECTOR:landing.show();landing.focus_default()
	elif screen==Screen.PAUSED:hud.show();hud.resume_button.grab_focus()

func _resize_settings() -> void:
	if is_instance_valid(settings_column):settings_column.custom_minimum_size.x=minf(360,maxf(220,get_viewport().get_visible_rect().size.x-88))
