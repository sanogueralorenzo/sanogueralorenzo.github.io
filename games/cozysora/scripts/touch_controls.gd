class_name CozyTouchControls
extends Control
## Shared multi-touch movement, look, and held actions. No map data lives here.
var player: CozyPlayer
var move_finger := -999
var look_finger := -999
var held: Dictionary = {}
var origin := Vector2.ZERO
var stick := Vector2.ZERO
var actions: Dictionary = {}
var font := SystemFont.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	visibility_changed.connect(_reset)
	_layout()

func _layout() -> void:
	var width_factor:=clampf((size.x-320.0)/70.0,0.0,1.0)
	origin=Vector2(lerpf(70,94,width_factor),size.y-96)
	var outer_x:=size.x-lerpf(48,74,width_factor)
	var inner_x:=size.x-lerpf(114,151,width_factor)
	actions={"jump":Vector2(outer_x,size.y-85),"sprint":Vector2(inner_x,size.y-80),"descend":Vector2(inner_x,size.y-151),"switch":Vector2(outer_x,size.y-162)}
	queue_redraw()

func _reset() -> void:
	move_finger=-999
	look_finger=-999
	held.clear()
	stick=Vector2.ZERO
	if is_instance_valid(player):player.clear_input()
	queue_redraw()

func _input(event:InputEvent) -> void:
	if not visible or not is_instance_valid(player) or player.menu_open:return
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION:return
	if event is InputEventScreenTouch:
		_contact(event.index,event.position,event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index,event.position,event.relative)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_contact(-1,event.position,event.pressed)
	elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		_drag(-1,event.position,event.relative)

func _contact(id:int,at:Vector2,pressed:bool) -> void:
	if not pressed:
		if id==move_finger:move_finger=-999;stick=Vector2.ZERO;player.touch_move=Vector2.ZERO
		if id==look_finger:look_finger=-999
		if held.has(id):player.touch_action(held[id],false);held.erase(id)
		queue_redraw()
		return
	if at.y<80:return
	for action:String in actions:
		if at.distance_to(actions[action])<32:
			held[id]=action
			player.touch_action(action,true)
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
	if at.distance_to(origin)<85 and move_finger==-999:
		move_finger=id
		_drag(id,at,Vector2.ZERO)
	elif at.x>size.x*.45 and look_finger==-999:
		look_finger=id
		get_viewport().set_input_as_handled()

func _drag(id:int,at:Vector2,delta:Vector2) -> void:
	if id==move_finger:
		stick=(at-origin).limit_length(48)
		player.touch_move=stick/48
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif id==look_finger:
		player.touch_look(delta)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not visible:return
	draw_circle(origin,64,Color(.05,.15,.16,.48))
	draw_arc(origin,64,0,TAU,64,Color(1,1,.9,.45),2,true)
	draw_circle(origin+stick,25,Color(.95,.96,.85,.65))
	var labels={"jump":"Climb" if is_instance_valid(player) and player.mode=="gull" else "Jump","descend":"Drop","sprint":"Boost","switch":"Switch"}
	for action:String in actions:
		var at:Vector2=actions[action]
		draw_circle(at,30,Color(.12,.3,.3,.88) if action in held.values() else Color(.05,.15,.16,.60))
		draw_arc(at,30,0,TAU,40,Color(1,1,.9,.55),1.5,true)
		var text:String=labels[action]
		var width:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		draw_string(font,at+Vector2(-width*.5,5),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fffdf5"))
