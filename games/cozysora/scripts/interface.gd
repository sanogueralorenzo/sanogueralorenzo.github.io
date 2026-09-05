class_name CozyInterface
extends Control
## Shared gameplay menu. The application owns pause, settings, and navigation.
signal resume_requested
signal pause_requested
signal destinations_requested
signal settings_requested
signal character_requested(mode: String)
const UI = preload("res://scripts/ui_theme.gd")
var panel: PanelContainer
var pause_scroll: ScrollContainer
var shade: ColorRect
var resume_button: Button
var cat_button: Button
var gull_button: Button
var controls: Label
var heading: Label
var menu_button: Button
var dot: ColorRect
var _buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.make_theme()
	menu_button = _button("Menu",func():pause_requested.emit())
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.offset_left=-118
	menu_button.offset_right=-20
	menu_button.offset_top=18
	menu_button.offset_bottom=66
	menu_button.focus_mode=Control.FOCUS_NONE
	add_child(menu_button)
	dot=ColorRect.new()
	dot.color=Color(1,1,1,.55)
	dot.mouse_filter=Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left=-2
	dot.offset_right=2
	dot.offset_top=-2
	dot.offset_bottom=2
	add_child(dot)
	shade=ColorRect.new()
	shade.color=Color(.035,.11,.12,.67)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	pause_scroll=ScrollContainer.new()
	pause_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	pause_scroll.follow_focus=true
	add_child(pause_scroll)
	var center:=CenterContainer.new()
	center.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	center.size_flags_vertical=Control.SIZE_EXPAND_FILL
	pause_scroll.add_child(center)
	var margin:=MarginContainer.new()
	for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	center.add_child(margin)
	panel=PanelContainer.new()
	var style:=UI.panel(UI.PAPER,22)
	for side in ["left","top","right","bottom"]:style.set("content_margin_"+side,28)
	panel.add_theme_stylebox_override("panel",style)
	margin.add_child(panel)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	panel.add_child(column)
	var brand:=Label.new()
	brand.text="Cozy Sora"
	brand.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_override("font",UI.title_font())
	brand.add_theme_font_size_override("font_size",32)
	column.add_child(brand)
	heading=Label.new()
	heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	resume_button=_button("Resume exploring",func():resume_requested.emit())
	column.add_child(resume_button)
	_buttons.append(resume_button)
	var picker:=HBoxContainer.new()
	picker.add_theme_constant_override("separation",10)
	column.add_child(picker)
	cat_button=_button("Cat",func():character_requested.emit("cat"))
	gull_button=_button("Seagull",func():character_requested.emit("gull"))
	for button in [cat_button,gull_button]:
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		picker.add_child(button)
		_buttons.append(button)
	controls=Label.new()
	controls.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size",14)
	controls.add_theme_color_override("font_color",UI.MUTED)
	controls.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(controls)
	var settings:=_button("Settings",func():settings_requested.emit())
	UI.secondary(settings)
	column.add_child(settings)
	_buttons.append(settings)
	var back:=_button("Back to destinations",func():destinations_requested.emit())
	UI.secondary(back)
	column.add_child(back)
	_buttons.append(back)
	for i in _buttons.size():
		_buttons[i].focus_next=_buttons[i].get_path_to(_buttons[(i+1)%_buttons.size()])
		_buttons[i].focus_previous=_buttons[i].get_path_to(_buttons[posmod(i-1,_buttons.size())])
	resized.connect(_resize)
	_resize()
	set_paused(false)

func _button(text:String, action:Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size.y=48
	button.focus_mode=Control.FOCUS_ALL
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

func configure(destination:String) -> void:
	heading.text=destination+" · Paused"

func set_character(mode:String, touch:bool) -> void:
	cat_button.text="✓ Cat" if mode=="cat" else "Cat"
	gull_button.text="✓ Seagull" if mode=="gull" else "Seagull"
	if touch:
		controls.text="Left pad to move · drag on the right to look\nJump / Climb · Drop · Boost · Switch"
	elif not Input.get_connected_joypads().is_empty():
		controls.text="Left stick move · right stick look · A jump / climb\nB descend · LB boost · Y switch · Start menu"
	else:
		controls.text="WASD move · mouse look · Shift sprint\nSpace jump / climb · C descend · Tab switch · Esc menu"

func set_paused(paused:bool) -> void:
	shade.visible=paused
	pause_scroll.visible=paused
	menu_button.visible=not paused
	dot.visible=not paused
	if paused: resume_button.grab_focus.call_deferred()
	else:
		var focus:=get_viewport().gui_get_focus_owner()
		if focus!=null and is_ancestor_of(focus):focus.release_focus()

func _resize() -> void:
	if panel==null:return
	panel.custom_minimum_size.x=minf(490,maxf(280,size.x-40))
