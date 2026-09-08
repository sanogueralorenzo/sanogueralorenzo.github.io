extends Control
## Menus use focusable native buttons; the HUD is a compact illustrated scorecard.
var game: Node2D
var font: SystemFont
var display_font: SystemFont
const INK := Color("244751")
const CREAM := Color("fff1d2")
const TEAL := Color("26767b")
const GOLD := Color("efc765")
var focus_first: Button
var right_clear_time:=0.0
var left_clear_time:=0.0
var collapse_right:=false
var collapse_left:=false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=SystemFont.new()
	font.font_names=PackedStringArray(["Avenir Next","DejaVu Sans","Arial"])
	display_font=SystemFont.new()
	display_font.font_names=PackedStringArray(["Georgia","DejaVu Serif"])

func panel(rect:Rect2,color:Color=CREAM,radius:int=18) -> void:
	var style:=StyleBoxFlat.new()
	style.bg_color=color
	style.corner_radius_top_left=radius
	style.corner_radius_top_right=radius
	style.corner_radius_bottom_left=radius
	style.corner_radius_bottom_right=radius
	style.border_color=Color(0.21,0.30,0.29,0.25)
	style.set_border_width_all(1)
	style.shadow_color=Color(0.13,0.25,0.25,0.16)
	style.shadow_size=5
	style.shadow_offset=Vector2(0,3)
	draw_style_box(style,rect)

func text_at(value:String,p:Vector2,size:int=20,color:Color=INK,serif:bool=false) -> void:
	draw_string(display_font if serif else font,p,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func centered(value:String,x:float,y:float,size:int=20,color:Color=INK,serif:bool=false) -> void:
	var f:Font=display_font if serif else font
	text_at(value,Vector2(x-f.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x/2,y),size,color,serif)

func paragraph(value:String,rect:Rect2,size:int=19,color:Color=INK) -> void:
	draw_multiline_string(font,rect.position,value,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x,size,-1,color)

func button(value:String,rect:Rect2,callback:Callable,primary:bool=false,disabled:bool=false) -> Button:
	var b:=Button.new()
	b.text=value
	b.position=rect.position
	b.size=rect.size
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",18)
	b.add_theme_color_override("font_color",CREAM if primary else INK)
	b.add_theme_color_override("font_hover_color",INK)
	b.add_theme_color_override("font_focus_color",CREAM if primary else INK)
	b.add_theme_color_override("font_disabled_color",Color("8e998e"))
	for state in ["normal","hover","pressed","focus","disabled"]:
		var s:=StyleBoxFlat.new()
		s.bg_color=(TEAL if primary else CREAM) if state=="normal" or state=="focus" else (GOLD if state!="disabled" else Color("d5d3bc"))
		s.set_corner_radius_all(12)
		s.set_border_width_all(2 if state=="focus" else 1)
		s.border_color=GOLD if state=="focus" else Color(0.2,0.3,0.28,0.25)
		s.content_margin_left=16
		s.content_margin_right=16
		b.add_theme_stylebox_override(state,s)
	b.disabled=disabled
	b.pressed.connect(func(): game.sound.tone(440,0.08,0.09); callback.call())
	add_child(b)
	if focus_first==null and not disabled: focus_first=b
	return b

func rebuild() -> void:
	for child in get_children(): child.queue_free()
	focus_first=null
	if font==null: _ready()
	match game.screen:
		"intro":
			button("Find your summer  →",Rect2(112,598,330,58),func(): game.screen="howto"; rebuild(),true)
			button("Season selection",Rect2(112,670,330,48),func(): game.screen="seasons"; rebuild())
		"howto":
			button("Warm up on the court",Rect2(299,674,370,57),func(): game.start_run(0,true),true)
			button("Choose a season  →",Rect2(689,674,350,57),func(): game.screen="seasons"; rebuild())
		"seasons":
			for i in range(9):
				var x:=240+(i%3)*331
				var y:=231+(i/3)*147
				var label:="%02d   %s%s"%[i+1,game.SEASONS[i],"  ✓" if game.crowns.has(i+1) else ""]
				button(label,Rect2(x,y,309,72),func(): game.season=i; game.screen="squad"; game.scenery.map_index=i/3; game.scenery.variant=i%3; game.refresh_scenery(); rebuild(),false,i>=game.unlocked)
			button("How to play",Rect2(242,752,240,46),func(): game.screen="howto"; rebuild())
			button("Sound: "+("off" if game.sound.muted else "on"),Rect2(503,752,230,46),func(): game.sound.toggle(); game.save_progress(); rebuild())
			button("Motion: "+("reduced" if game.reduced_motion else "full"),Rect2(756,752,320,46),func(): game.reduced_motion=not game.reduced_motion; game.save_progress(); rebuild())
		"squad":
			for i in range(3):
				button(["Choose Sunkeepers","Choose Shorebirds","Choose Fireflies"][i],Rect2(249+i*331,569,306,53),func(): game.squad=i; game.start_run(game.season),true)
			button("← Seasons",Rect2(248,688,210,47),func(): game.screen="seasons"; rebuild())
		"match":
			if game.pause:
				button("Back to the rally",Rect2(502,411,438,55),func(): game.pause=false; rebuild(),true)
				button("Sound: "+("off" if game.sound.muted else "on"),Rect2(502,480,210,48),func(): game.sound.toggle(); game.save_progress(); rebuild())
				button("Motion: "+("reduced" if game.reduced_motion else "full"),Rect2(730,480,210,48),func(): game.reduced_motion=not game.reduced_motion; game.save_progress(); rebuild())
				button("Leave this run",Rect2(502,547,438,48),func(): game.pause=false; game.upgrades.clear(); game.screen="seasons"; rebuild())
		"upgrade":
			for i in range(3):
				var offer:Dictionary=game.offers[i]
				button("Take "+offer.title,Rect2(249+i*331,586,306,55),func(): game.take_upgrade(offer.id),true)
		"champion","defeat","practice_done":
			button("Choose a season  →",Rect2(510,593,420,56),func(): game.screen="seasons"; rebuild(),true)
			button("Play this season again",Rect2(510,665,420,48),func(): game.start_run(game.season))
	if focus_first and (game.screen!="match" or game.pause): focus_first.call_deferred("grab_focus")
	queue_redraw()

func _draw() -> void:
	if game==null or font==null: return
	match game.screen:
		"intro": draw_intro()
		"howto": draw_howto()
		"seasons": draw_seasons()
		"squad": draw_squad()
		"match": draw_hud()
		"upgrade": draw_upgrades()
		"champion","defeat","practice_done": draw_result()
	if game.pause and game.screen=="match":
		draw_rect(Rect2(-80,0,1600,900),Color(0.08,0.22,0.25,0.58))
		panel(Rect2(462,264,518,372))
		centered("Take a breath.",720,332,39,INK,true)
		centered("The rally will be here when you return.",720,371,18)
	if not game.save_error.is_empty():
		panel(Rect2(270,12,900,45),Color("f2d29c"))
		centered(game.save_error,720,42,17)
	if game.toast_time>0:
		panel(Rect2(533,735,374,40),Color("fff3d7"),10)
		centered(game.toast,720,762,15)

func draw_intro() -> void:
	panel(Rect2(74,100,458,663),Color(1,0.953,0.831,0.96),28)
	text_at("A SUMMER VOLLEYBALL ROGUELIKE",Vector2(112,151),14,TEAL)
	text_at("Spike",Vector2(106,251),84,INK,true)
	text_at("Season",Vector2(106,332),84,INK,true)
	draw_line(Vector2(113,364),Vector2(225,364),GOLD,5,true)
	paragraph("Three friends. Nine summers.\nOne more ball worth chasing.",Rect2(112,410,340,100),21)
	paragraph("Read the court, find your rhythm, and take your team from a seaside warm-up to the summer championship.",Rect2(112,512,340,100),17)
	panel(Rect2(1016,34,382,68),CREAM)
	text_at("MAREA HILLS",Vector2(1040,63),17)
	text_at("Coastal court   /   24°C   /   light breeze",Vector2(1040,87),13)
	text_at("MADE OF SUNLIGHT & SECOND CHANCES",Vector2(75,858),14,CREAM)

func draw_howto() -> void:
	dim()
	panel(Rect2(240,114,960,666))
	text_at("WELCOME TO SOL",Vector2(289,161),15,TEAL)
	text_at("You choose. Your team moves.",Vector2(289,218),42,INK,true)
	var rows:=[
		["01","Find the open court","← → aim left, middle, or right. ↑ deep / ↓ short. A dashed circle previews your target."],
		["02","Choose your finish","Q roll clears blocks. W power beats late defenders. E tip pulls deep defenders to the net."],
		["03","Meet the ball","SPACE serves and times each contact. Press as the timing bar reaches the line. No press? Your team makes a steady automatic contact."],
		["04","Play together","TAB chooses the next attacker before the set. The gold ring follows the teammate meeting the ball. Every choice stays selected."]]
	for i in range(4):
		var y:=275+i*89
		text_at(rows[i][0],Vector2(290,y+8),26,TEAL,true)
		text_at(rows[i][1],Vector2(354,y),20)
		paragraph(rows[i][2],Rect2(354,y+29,773,60),17)
	text_at("Three matches • First to 5, win by 2, cap 9 • Upgrades last one run • ESC pauses",Vector2(289,641),16,TEAL)

func dim() -> void:
	draw_rect(Rect2(-80,0,1600,900),Color(0.08,0.23,0.26,0.51))

func draw_seasons() -> void:
	dim()
	panel(Rect2(201,91,1040,744))
	text_at("THE SUMMER CIRCUIT",Vector2(240,142),15,TEAL)
	text_at("A new shore. A stronger team.",Vector2(239,197),42,INK,true)
	for i in range(9):
		var x:=240+(i%3)*331
		var y:=231+(i/3)*147
		text_at(["MAREA HILLS","LANTERN HARBOR","CITRUS GARDENS"][i/3],Vector2(x+5,y+99),12,TEAL)
		text_at("Unlocked • replay anytime" if i<game.unlocked else "Win season %d to unlock"%i,Vector2(x+5,y+121),14,INK)
	text_at("Win all three matches to keep your next season. A loss resets only this run's upgrades.",Vector2(240,711),17)

func draw_squad() -> void:
	dim()
	panel(Rect2(201,123,1040,645))
	text_at("SEASON %02d  /  %s"%[game.season+1,game.SEASONS[game.season].to_upper()],Vector2(248,170),15,TEAL)
	text_at("Choose your three.",Vector2(248,225),43,INK,true)
	var titles:=["Sunkeepers","Shorebirds","Fireflies"]
	var descriptions:=["Calm under pressure.\nAll receivers gain 0.12 m reach.\n\nRen • steady captain\nKai • creative setter\nJun • patient finisher", "A team that never stops.\nEveryone runs 0.2 m/s faster.\n\nRen • tireless receiver\nKai • mobile setter\nJun • quick outside hitter", "Build around your finisher.\nJun moves faster and hits 4% faster.\n\nRen • anchor\nKai • playmaker\nJun • explosive ace"]
	for i in range(3):
		var x:=249+i*331
		panel(Rect2(x,262,306,289),Color("f0e4c7"),15)
		text_at(titles[i],Vector2(x+22,306),27,INK,true)
		paragraph(descriptions[i],Rect2(x+22,344,264,194),17)
	paragraph("SCOUT  /  "+game.RIVALS[game.season]+" — "+game.SCOUTS[game.season],Rect2(250,658,917,55),17,TEAL)

func _process(delta:float) -> void:
	if game==null or game.screen!="match" or game.scenery.actors.size()!=6: return
	var right_blocked:=court_overlaps(Rect2(1120,656,370,245))
	var left_blocked:=court_overlaps(Rect2(-58,685,282,159))
	right_clear_time=0 if right_blocked else right_clear_time+delta
	left_clear_time=0 if left_blocked else left_clear_time+delta
	if right_blocked: collapse_right=true
	elif right_clear_time>0.65: collapse_right=false
	if left_blocked: collapse_left=true
	elif left_clear_time>0.65: collapse_left=false

func court_overlaps(rect:Rect2) -> bool:
	# Reserve the actual projected athlete/contact silhouette before drawing a dock.
	var camera:Camera3D=game.scenery.camera
	for actor in game.scenery.actors:
		var foot:Vector2=(camera.unproject_position(actor.global_position)-Vector2(72,0))/0.9
		var top:Vector2=(camera.unproject_position(actor.head.global_position+Vector3.UP*0.25)-Vector2(72,0))/0.9
		var height:=maxf(50,foot.y-top.y)
		if rect.intersects(Rect2(minf(foot.x,top.x)-height*0.27,top.y-12,absf(foot.x-top.x)+height*0.54,height+25)): return true
	var ball:Vector2=(game.project_ball()-Vector2(72,0))/0.9
	return rect.grow(30).has_point(ball)

func draw_hud() -> void:
	# Court action stays open; contextual guidance lives along its outer edge.
	panel(Rect2(-48,22,231,77),CREAM,20)
	text_at(game.MAPS[game.season/3].to_upper(),Vector2(-30,50),17)
	text_at("SEASON %02d / %s"%[game.season+1,"WARM-UP" if game.practice else ["QUARTERFINAL","SEMIFINAL","FINAL"][game.round_index]],Vector2(-30,76),12,TEAL)
	panel(Rect2(500,22,440,66),CREAM,22)
	centered("YOU",553,63,16)
	centered("%02d : %02d"%[game.score[0],game.score[1]],720,68,39)
	centered("RIVALS",885,63,16)
	panel(Rect2(1159,22,317,97 if collapse_right else 75),CREAM,18)
	text_at(game.RIVALS[game.season].to_upper(),Vector2(1174,45),15,INK)
	text_at("First to 5 • win by 2 • cap 9",Vector2(1174,66),11,INK)
	text_at("ESC pause / M sound",Vector2(1174,86),11,INK)
	if collapse_right: text_at("← → "+["LEFT","MIDDLE","RIGHT"][game.aim_lane]+" / ↑ ↓ "+("DEEP" if game.aim_deep else "SHORT"),Vector2(1174,108),12,TEAL)
	if game.feedback_timer>0 and not game.feedback.begins_with("AUTO"):
		var w:=maxf(210,font.get_string_size(game.feedback,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+40)
		panel(Rect2(720-w/2,105,w,39),CREAM,13)
		centered(game.feedback,720,131,18)
	if game.phase=="point":
		panel(Rect2(482,151,476,35),Color("f4dfb5"),11)
		centered(game.point_reason,720,175,15)
	var front_lane:int=0 if game.committed_block_target.x < -1.0 else (2 if game.committed_block_target.x > 1.0 else 1)
	var note:String
	if game.receiving==1 and game.phase in ["set","attack"] and game.upgrades.has("read"):
		note="COURT VISION • "+["ROLL","POWER","TIP"][game.rival_shot]+" to "+["LEFT","MIDDLE","RIGHT"][game.rival_lane]+" / Aim at the orange ring for quicker recovery."
	elif game.rally_contacts>=12 and game.repeat_lane>=2: note="Same lane covered? Try the other side (← →), or TAB for another hitter."
	elif game.receiving==0 and game.phase=="attack" and game.rival_deep_lane>=0: note="Deep cover "+["LEFT","MIDDLE","RIGHT"][game.rival_deep_lane]+" / Short cover "+["RIGHT","MIDDLE","LEFT"][game.rival_deep_lane]+" • Read the gap or TAB for another hitter."
	elif game.receiving==0 and game.phase=="attack": note="Front defender "+["LEFT","MIDDLE","RIGHT"][front_lane]+" / "+("Short court covered. Try a deep corner." if game.rival_cover_short else "Tip toward the other side of the front court.")
	elif game.receiving==1 and game.phase in ["set","attack"]: note="Rival prepares "+["ROLL","POWER","TIP"][game.rival_shot]+" / ← → also chooses your block lane"
	elif game.phase=="serve": note="Pick an open lane / SPACE serves, or let your team start"
	else: note="Pass → set → attack / Your team moves and contacts automatically"
	panel(Rect2(310,843,812,44),Color(1,0.954,0.838,0.94),10)
	centered(note,716,871,16)
	for i in range(3):
		var x:float=-47+i*90
		if collapse_left:
			panel(Rect2(x,855,81,29),GOLD if game.active==i else CREAM,9)
			centered(["REN 7","KAI 3","JUN 11"][i],x+40,875,12)
		else:
			panel(Rect2(x,703,81,133),GOLD if game.active==i else CREAM,12)
			if game.scenery.portraits.size()==3: draw_texture_rect(game.scenery.portraits[i],Rect2(x+5,708,71,103),false)
			centered(["REN 7","KAI 3","JUN 11"][i],x+40,828,11)
	var next_hitter:int=game.pick_attacker() if game.receiving==0 else game.attack_choice*2
	text_at("TAB  next: "+["REN / LEFT","KAI / MIDDLE","JUN / RIGHT"][next_hitter%3],Vector2(-45,847 if collapse_left else 860),12,CREAM)
	if not collapse_left: text_at("AUTO POSITION",Vector2(-45,880),10,CREAM)
	var progress:=0.0
	if game.phase in ["receive","set","attack"] and game.receiving==0: progress=clampf(game.flight_elapsed/game.flight_duration,0,1)
	var window:float=(0.13+0.05*game.upgrades.count("window"))/maxf(game.flight_duration,0.1)
	if collapse_right:
		# Keep the full timing width below the keys while freeing the deep corner.
		for i in range(4):
			var x:float=1132+i*86
			var chosen:bool=game.shot==i if i<3 else game.timing_press>=0
			panel(Rect2(x,847,81,35),TEAL if chosen else CREAM,9)
			centered(["Q ROLL","W POWER","E TIP","SPACE"][i],x+40,871,14,CREAM if chosen else INK)
		var tx:=1138.0
		panel(Rect2(1132,884,344,15),CREAM,5)
		draw_rect(Rect2(tx,888,332,6),Color("d8cdb0"))
		draw_rect(Rect2(tx+332*(1-window),886,332*window,10),GOLD)
		draw_rect(Rect2(tx,888,332*progress,6),TEAL)

	else:
		for i in range(4):
			var x:float=1132+(i%2)*176
			var y:float=732+(i/2)*60
			var chosen:bool=game.shot==i if i<3 else game.timing_press>=0
			panel(Rect2(x,y,168,51),TEAL if chosen else CREAM,14)
			text_at(["Q  ROLL","W  POWER","E  TIP","SPACE  CONTACT"][i],Vector2(x+15,y+33),13 if i==3 else 16,CREAM if chosen else INK)
		panel(Rect2(1132,672,344,49),CREAM,13)
		text_at("← → "+["LEFT","MIDDLE","RIGHT"][game.aim_lane]+"     ↑ ↓ "+("DEEP" if game.aim_deep else "SHORT"),Vector2(1148,693),13)
		text_at("%02d:%02d   /   %d rally contacts"%[int(game.match_time)/60,int(game.match_time)%60,game.rally_contacts],Vector2(1148,711),11,TEAL)
		panel(Rect2(1132,850,344,47),CREAM,10)
		var tx:=1138.0
		draw_style_box(bar_style(Color("d8cdb0")),Rect2(tx,861,332,8))
		draw_rect(Rect2(tx+332*(1-window),859,332*window,12),GOLD)
		draw_rect(Rect2(tx,861,332*progress,8),TEAL)
		text_at("OPTIONAL TIMING",Vector2(tx,888),10,TEAL)
		text_at("NOW",Vector2(tx+305,888),10,TEAL)
	if game.practice and game.match_time<26:
		panel(Rect2(357,794,675,40),CREAM,12)
		centered("Start with ← →. Your team handles movement and contacts.",694,821,15)
	if game.debug_visible:
		panel(Rect2(1050,130,378,220),CREAM)
		var data:="LIVE DIAGNOSTICS\n%s  %.2f / %.2f s\nBall: %.2f, %.2f  h %.2f\nReceiver %d  contact %d\nReach distance %.2f m\nReaction remaining %.2f s\nSet quality %.2f / power %.2f"%[game.phase,game.flight_elapsed,game.flight_duration,game.ball.x,game.ball.y,game.ball_height,game.receiving,game.toucher,game.players[game.toucher].pos.distance_to(game.flight_end),game.reaction_remaining,game.set_quality,game.contact_quality]
		paragraph(data,Rect2(1068,153,338,180),14)

func bar_style(color:Color) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=color
	s.set_corner_radius_all(4)
	return s

func draw_upgrades() -> void:
	dim()
	panel(Rect2(201,130,1040,625))
	text_at("MATCH WON  /  %02d : %02d"%[game.score[0],game.score[1]],Vector2(249,177),15,TEAL)
	text_at("A little stronger. Still together.",Vector2(249,233),41,INK,true)
	paragraph("Choose one upgrade for the rest of this run. Next: "+["SEMIFINAL","CHAMPIONSHIP"][game.round_index],Rect2(249,276,926,40),18)
	for i in range(3):
		var offer:Dictionary=game.offers[i]
		var x:=249+i*331
		panel(Rect2(x,325,306,240),Color("f0e4c7"),16)
		text_at(offer.tag,Vector2(x+23,358),12,TEAL)
		paragraph(offer.title,Rect2(x+23,405,260,70),27)
		paragraph(offer.desc,Rect2(x+23,463,260,104),17)
	text_at("Temporary upgrades reset after defeat or when starting another season.",Vector2(249,694),17,TEAL)

func draw_result() -> void:
	dim()
	panel(Rect2(405,132,630,650))
	var won:bool=game.screen=="champion"
	centered("SUMMER CIRCUIT  /  SEASON %02d"%[game.season+1],720,183,14,TEAL)
	# A procedural laurel badge.
	draw_circle(Vector2(720,271),48,GOLD)
	centered("S" if won else ("→" if game.screen=="practice_done" else "•"),720,290,48,INK,true)
	for side in [-1,1]:
		for i in range(6):
			var p:=Vector2(720+side*(53+sin(i*0.4)*16),307-i*13)
			draw_set_transform(p,side*0.6,Vector2(1,0.4))
			draw_circle(Vector2.ZERO,8,TEAL)
			draw_set_transform(Vector2.ZERO)
	centered("Champions of summer." if won else ("Ready for your season." if game.screen=="practice_done" else "Another summer awaits."),720,380,36,INK,true)
	centered("SOL  %02d : %02d  RIVALS"%[game.score[0],game.score[1]],720,425,24)
	var msg:="Season %02d is unlocked. This season stays yours to replay."%mini(game.season+2,9)
	if won and game.season==8: msg="All nine seasons conquered. Every court is yours to revisit."
	if not won: msg="Your unlocked seasons are safe. A fresh run brings new choices."
	if game.screen=="practice_done": msg="Warm-up complete. The championship is three matches, with an upgrade after each of the first two."
	paragraph(msg,Rect2(463,475,518,88),19)
	centered("%d rallies   •   longest rally %d contacts   •   %d:%02d"%[game.ledger.size(),game.best_rally,int(game.run_time)/60,int(game.run_time)%60],720,559,15,TEAL)
