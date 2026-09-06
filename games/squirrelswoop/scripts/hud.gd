class_name SwoopHUD
extends CanvasLayer

signal launch_requested
signal resume_requested
signal retry_requested(same_seed: bool)
signal settings_changed
signal summit_requested
signal quit_requested

var game: Node
var root: Control
var hud: Control
var menu: Control
var distance_label: Label
var score_label: Label
var route_label: Label
var speed_label: Label
var feedback: Label
var trim_label: Label
var help_label: Label
var diagnostics: Label
var screen := "summit"
var serif: SystemFont
var sans: SystemFont
var feedback_left := 0.0
var feedback_priority := 0
var margin := Color(0.94,0.93,0.84)

func _ready() -> void:
 serif=SystemFont.new()
 serif.font_names=PackedStringArray(["Georgia","Noto Serif","DejaVu Serif"])
 sans=SystemFont.new()
 sans.font_names=PackedStringArray(["Helvetica Neue","Noto Sans","DejaVu Sans"])
 root=Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter=Control.MOUSE_FILTER_IGNORE
 add_child(root)
 hud=Control.new()
 hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
 root.add_child(hud)
 distance_label=label(hud,"",Vector2(42,28),35)
 score_label=label(hud,"",Vector2(-290,28),35)
 anchor(score_label,Control.PRESET_TOP_RIGHT,Vector2(-290,28))
 score_label.size.x=248
 score_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
 route_label=label(hud,"",Vector2(44,106),14)
 speed_label=label(hud,"",Vector2(-275,-87),29)
 anchor(speed_label,Control.PRESET_BOTTOM_RIGHT,Vector2(-275,-87))
 speed_label.size.x=232
 speed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
 trim_label=label(hud,"",Vector2(44,-74),14)
 anchor(trim_label,Control.PRESET_BOTTOM_LEFT,Vector2(44,-74))
 help_label=label(hud,"A / D  BANK      W / S  PITCH      SHIFT  DIVE      ESC  PAUSE",Vector2(-325,-45),13)
 anchor(help_label,Control.PRESET_CENTER_BOTTOM,Vector2(-325,-45))
 help_label.size.x=650
 help_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 feedback=label(hud,"",Vector2(-250,-80),23)
 anchor(feedback,Control.PRESET_CENTER,Vector2(-250,110))
 feedback.size.x=500
 feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 diagnostics=label(hud,"",Vector2(44,145),13)
 diagnostics.visible=false
 menu=Control.new()
 menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.add_child(menu)

func anchor(control: Control, preset: int, offset: Vector2) -> void:
 control.set_anchors_preset(preset)
 control.offset_left=offset.x
 control.offset_top=offset.y
 control.offset_right=offset.x+control.size.x
 control.offset_bottom=offset.y+control.size.y

func label(parent: Node, text: String, pos: Vector2, font_size: int, literary := false) -> Label:
 var node := Label.new()
 node.text=text
 node.position=pos
 node.add_theme_font_override("font",serif if literary else sans)
 node.add_theme_font_size_override("font_size",font_size)
 node.add_theme_color_override("font_color",margin)
 node.add_theme_color_override("font_shadow_color",Color(0.02,0.04,0.025,0.32))
 node.add_theme_constant_override("shadow_offset_y",1)
 node.mouse_filter=Control.MOUSE_FILTER_IGNORE
 parent.add_child(node)
 return node

func button(parent: Node, text: String, pos: Vector2, size_b: Vector2, callback: Callable, primary := false) -> Button:
 var b := Button.new()
 b.text=text
 b.focus_mode=Control.FOCUS_ALL
 b.position=pos
 b.size=size_b
 b.add_theme_font_override("font",sans)
 b.add_theme_font_size_override("font_size",16)
 var style := StyleBoxFlat.new()
 style.bg_color=Color(0.89,0.88,0.73,0.98) if primary else Color(0.06,0.11,0.09,0.88)
 style.border_color=Color(0.76,0.80,0.67,0.38)
 style.set_border_width_all(1)
 style.set_corner_radius_all(5)
 style.content_margin_left=18
 style.content_margin_right=18
 b.add_theme_stylebox_override("normal",style)
 var hover := style.duplicate()
 hover.bg_color=Color(0.97,0.94,0.78) if primary else Color(0.19,0.27,0.20,0.95)
 b.add_theme_stylebox_override("hover",hover)
 b.add_theme_stylebox_override("focus",hover)
 b.add_theme_stylebox_override("pressed",hover)
 b.add_theme_color_override("font_color",Color(0.09,0.14,0.10) if primary else margin)
 b.add_theme_color_override("font_hover_color",Color(0.09,0.14,0.10) if primary else margin)
 b.add_theme_color_override("font_focus_color",Color(0.09,0.14,0.10) if primary else margin)
 b.pressed.connect(callback)
 parent.add_child(b)
 return b

func clear_menu() -> void:
 for c in menu.get_children():
  menu.remove_child(c)
  c.queue_free()
 menu.visible=true

func shade(alpha: float) -> void:
 var overlay := ColorRect.new()
 overlay.color=Color(0.015,0.04,0.035,alpha)
 overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 menu.add_child(overlay)

func show_summit() -> void:
 screen="summit"
 clear_menu()
 hud.visible=false
 # Opening typography leaves the landscape and all three descents visible.
 var wash := ColorRect.new()
 wash.color=Color(0.035,0.07,0.058,0.72)
 wash.position=Vector2(30,30)
 wash.size=Vector2(445,345)
 wash.mouse_filter=Control.MOUSE_FILTER_IGNORE
 menu.add_child(wash)
 label(menu,"A SMALL CREATURE. AN ENDLESS MOUNTAIN.",Vector2(58,52),12)
 label(menu,"Squirrel\nSwoop",Vector2(55,76),59,true)
 label(menu,"Find your line. Let the mountain carry you.",Vector2(58,229),16)
 button(menu,"Spread your wings    ↵",Vector2(58,281),Vector2(280,54),func():launch_requested.emit(),true).grab_focus()
 button(menu,"Settings",Vector2(347,281),Vector2(102,54),func():show_settings("summit"))
 var bottom := Control.new()
 anchor(bottom,Control.PRESET_BOTTOM_WIDE,Vector2(0,-179))
 menu.add_child(bottom)
 var card := ColorRect.new()
 card.color=Color(0.025,0.065,0.049,0.82)
 card.size=Vector2(1440,179)
 bottom.add_child(card)
 label(bottom,"←   SUNLIT MEADOW",Vector2(58,21),16)
 label(bottom,"Wide clearings · gentle lines",Vector2(58,53),14)
 label(bottom,"WINDING WATER",Vector2(540,21),16)
 label(bottom,"Follow the stream · find the bends",Vector2(540,53),14)
 label(bottom,"DEEP WOODS   →",Vector2(1024,21),16)
 label(bottom,"Steep drops · narrow passages",Vector2(1024,53),14)
 label(bottom,"A / D or ← / →  bank     W / S or ↑ / ↓  pitch     Hold SHIFT / SPACE  dive; release to recover",Vector2(58,104),15)
 label(bottom,"Choose by flying. Cross the slope freely.   •   Enter to launch   •   Esc to pause",Vector2(58,138),13)
 label(menu,"MOUNTAIN %d  /  BEST %s m"%[game.run_seed,format_number(game.best_distance)],Vector2(510,43),13)

func show_pause() -> void:
 screen="pause"
 clear_menu()
 shade(0.60)
 var panel := Control.new()
 panel.size=Vector2(600,560)
 anchor(panel,Control.PRESET_CENTER,Vector2(-240,-185))
 menu.add_child(panel)
 label(panel,"TAKE A BREATH",Vector2(0,0),13)
 label(panel,"A moment in the trees.",Vector2(0,34),37,true)
 label(panel,"Your mountain is waiting exactly where you left it.",Vector2(0,99),15)
 button(panel,"Return to the glide    Esc",Vector2(0,151),Vector2(465,52),func():resume_requested.emit(),true).grab_focus()
 button(panel,"Settings",Vector2(0,218),Vector2(224,48),func():show_settings("pause"))
 button(panel,"Back to summit",Vector2(241,218),Vector2(224,48),func():summit_requested.emit())
 button(panel,"Quit",Vector2(0,282),Vector2(465,43),func():quit_requested.emit())

func show_settings(back: String) -> void:
 screen="settings"
 clear_menu()
 shade(0.81)
 var panel := Control.new()
 panel.size=Vector2(600,560)
 anchor(panel,Control.PRESET_CENTER,Vector2(-240,-210))
 menu.add_child(panel)
 label(panel,"MAKE YOURSELF AT HOME",Vector2.ZERO,13)
 label(panel,"Flight settings",Vector2(0,30),43,true)
 label(panel,"Sound",Vector2(0,105),16)
 var slider := HSlider.new()
 slider.focus_mode=Control.FOCUS_ALL
 slider.position=Vector2(165,113)
 slider.size=Vector2(300,25)
 slider.min_value=0
 slider.max_value=1
 slider.step=0.05
 slider.value=game.sound_volume
 slider.value_changed.connect(func(value: float):game.sound_volume=value;settings_changed.emit())
 panel.add_child(slider)
 slider.grab_focus()
 var options := ["Gentle ground assistance","Reduced camera motion","Invert pitch"]
 var properties := ["assistance","reduced_motion","invert_pitch"]
 for i in options.size():
  var check := CheckButton.new()
  check.focus_mode=Control.FOCUS_ALL
  check.position=Vector2(0,157+i*49)
  check.size=Vector2(470,43)
  check.text=options[i]
  check.add_theme_font_override("font",sans)
  check.add_theme_font_size_override("font_size",16)
  check.button_pressed=game.get(properties[i])
  var property: String=properties[i]
  check.toggled.connect(func(value: bool):game.set(property,value);settings_changed.emit())
  panel.add_child(check)
 label(panel,"Assistance trades speed for lift near the ground.\nRelease dive early to preserve momentum.",Vector2(0,318),13)
 button(panel,"Done",Vector2(0,380),Vector2(470,51),func():
  if back=="pause": show_pause()
  else: show_summit()
 ,true)

func show_results(cause: String, record: bool) -> void:
 screen="results"
 clear_menu()
 shade(0.55)
 hud.visible=false
 var panel := Control.new()
 panel.size=Vector2(600,560)
 anchor(panel,Control.PRESET_CENTER,Vector2(-300,-280))
 menu.add_child(panel)
 label(panel,"A NEW PERSONAL BEST" if record else "EVERY DESCENT TELLS A STORY",Vector2(0,0),13)
 label(panel,"One more swoop?",Vector2(0,34),53,true)
 label(panel,cause,Vector2(0,112),17)
 label(panel,format_number(game.distance)+" m",Vector2(0,166),49,true)
 label(panel,format_number(game.score)+" points",Vector2(304,177),32,true)
 label(panel,"DISTANCE",Vector2(0,229),12)
 label(panel,"%d CLOSE PASSES  /  FLOW ×%d"%[game.close_passes,game.max_flow],Vector2(305,229),12)
 label(panel,"Mountain %d  ·  %.1f seconds aloft"%[game.run_seed,game.run_time],Vector2(0,273),15)
 label(panel,"BEST  %s m   /   %s points"%[format_number(game.best_distance),format_number(game.best_score)],Vector2(0,307),13)
 button(panel,"Same mountain    R",Vector2(0,359),Vector2(291,55),func():retry_requested.emit(true),true).grab_focus()
 button(panel,"New mountain    N",Vector2(307,359),Vector2(291,55),func():retry_requested.emit(false))
 button(panel,"Back to summit",Vector2(0,430),Vector2(598,44),func():summit_requested.emit())
 label(panel,"Release dive early to spread your membrane and recover.",Vector2(0,502),14)

func play_mode() -> void:
 screen="flight"
 menu.visible=false
 hud.visible=true

func notice(text: String, priority := 0) -> void:
 if feedback_left>0 and priority<feedback_priority: return
 feedback_priority=priority
 feedback.text=text
 feedback_left=1.8

static func format_number(value: float) -> String:
 var raw := str(int(value))
 var result := ""
 for i in raw.length():
  if i>0 and (raw.length()-i)%3==0: result+=","
  result+=raw[i]
 return result

func update(delta: float) -> void:
 feedback_left=maxf(0,feedback_left-delta)
 feedback.modulate.a=minf(feedback_left*2,1)
 distance_label.text="%s m"%format_number(game.distance)
 if game.review_staged: distance_label.text="%s m · STUDY"%format_number(-game.player_pos.z)
 score_label.text="%s  /  ×%d"%[format_number(game.score),game.flow]
 route_label.text=["SUNLIT MEADOW  /  OPEN LINES","WINDING WATER  /  FOLLOW THE BENDS","DEEP WOODS  /  THREAD THE TREES"][game.current_route]
 speed_label.text="%d km/h"%int(game.speed*3.6)
 var states := {"tucked":"BUILDING SPEED · RELEASE TO SPREAD","recovering":"RECOVERING · TRADING SPEED FOR LIFT","pulling_up":"SPREADING · SPENDING MOMENTUM","low_energy":"LOW ENERGY · EASE PITCH","carrying_speed":"CARRYING SPEED","gliding":"GLIDING"}
 trim_label.text="%.1f m  /  %s"%[game.clearance,states.get(game.flight.flight_state,"GLIDING")]
 diagnostics.text="FPS %d  |  %d sections  |  %d generated  |  build %.1f ms\nSeed %d  •  x %.1f / descent %.1f / altitude %.1f\nPitch %.2f  •  vertical %.1f m/s  •  near passes %d"%[Engine.get_frames_per_second(),game.mountain.chunks.size(),game.mountain.generated_count,game.mountain.generation_ms,game.run_seed,game.player_pos.x,game.distance,game.player_pos.y,game.pitch_input,game.vertical_speed,game.close_passes]
