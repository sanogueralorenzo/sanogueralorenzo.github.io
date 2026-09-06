extends Control
## Compact fishing instruments. Detailed instruction is optional; the water stays visible.
var state := "idle"
var species := ""
var phase := ""
var progress := 0.0
var tension := 0.0
var counter := 0.0
var steer_active := 0.0
var clean_reads := 0
var required_reads := 0
var reel_active := false
var toggle_controls := false
var detailed := false
var fish_screen := Vector2.ZERO
var show_world_cue := false
var instruction := ""
var font: Font
var ink := Color("243f43")
var muted := Color("637b78")
var cream := Color("f7f0dded")
var teal := Color("438c83")
var amber := Color("bf873e")
var coral := Color("bc604a")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _text(at: Vector2, text: String, size: int = 16, color: Color = ink) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _meter(at: Vector2, width: float, value: float, color: Color) -> void:
	var rect := Rect2(at, Vector2(width, 6))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("cbd1c3")
	style.set_corner_radius_all(3)
	style.draw(get_canvas_item(), rect)
	if value > 0:
		style.bg_color = color
		style.draw(get_canvas_item(), Rect2(at, Vector2(width * clampf(value, 0, 1), 6)))

func _draw() -> void:
	if state == "idle" or font == null: return
	var action := ""
	var action_color := teal
	var explanation := ""
	match state:
		"casting":
			action = "SPACE   CAST"
			explanation = "Aim for the gold band. Every cast is fishable."
		"presentation":
			var resting := phase.begins_with("REST")
			action = "RELEASE   REST" if resting else "HOLD SPACE   LURE"
			if toggle_controls:
				if resting: action = "TAP SPACE   REST" if reel_active else "REST · LET IT SETTLE"
				else: action = "LURE · KEEP IT MOVING" if reel_active else "TAP SPACE   LURE"
			action_color = muted if resting else teal
			explanation = "Hold on LURE, release on REST. Settle each pulse."
		"hook":
			action = "SPACE   STRIKE!"
			action_color = coral
			explanation = "Press once to set the hook."
		"fight":
			var resting := phase.begins_with("DASH •") or phase.begins_with("SECOND")
			var warning := phase.begins_with("DASH COMING") or phase.begins_with("FEINT")
			action = "SPACE   RELEASE" if resting else ("DASH COMING" if warning else "SPACE   REEL")
			if phase.begins_with("FEINT"): action = "FEINT · WATCH THE TURN"
			if phase.begins_with("SECOND"): action = "SECOND RUN · KEEP RESTING"
			if toggle_controls and not resting and not warning and reel_active: action = "REELING · FOLLOW THE ARROW"
			if resting and not reel_active: action = "REST · FOLLOW THE ARROW"
			action_color = coral if resting else (amber if warning else teal)
			explanation = "Release during runs. Follow the arrow. Zero tension is safe."
	if detailed and not instruction.is_empty():
		explanation = instruction.split("\n")[0]
	var height := 182.0 if state == "fight" else 113.0
	if detailed: height += 62
	var origin := Vector2(1042, 876 - height)
	var card := StyleBoxFlat.new()
	card.bg_color = cream
	card.border_color = Color("bcae88")
	card.set_border_width_all(1)
	card.set_corner_radius_all(13)
	card.draw(get_canvas_item(), Rect2(origin, Vector2(370, height)))
	_text(origin + Vector2(16, 26), species, 19)
	_text(origin + Vector2(16, 52), action, 17, action_color)
	var label := "PLACEMENT" if state == "casting" else ("INTEREST" if state == "presentation" else ("HOOK WINDOW" if state == "hook" else "LANDING"))
	_text(origin + Vector2(16, 74), "%s  %d%%" % [label, roundi(progress * 100)], 12, muted)
	_meter(origin + Vector2(16, 82), 338, progress, action_color if state == "hook" else teal)
	if state == "casting":
		draw_rect(Rect2(origin + Vector2(16 + 338 * .55, 79), Vector2(338 * .25, 12)), Color("dfb76755"))
		for p in [.55, .8]: draw_line(origin + Vector2(16+338*p,78),origin + Vector2(16+338*p,93),amber,1)
	if state == "fight":
		_text(origin + Vector2(16, 108), "TENSION  %d%%" % roundi(tension*100), 12, coral if tension > .7 else muted)
		var matching := steer_active * counter > .4
		_text(origin + Vector2(220,108), ("A  ←" if counter < 0 else "D  →") + ("  ✓ HELD" if matching else "  COUNTER"), 13, teal if matching else ink)
		_meter(origin + Vector2(16, 116), 338, tension, coral if tension > .7 else amber)
		if required_reads > 0:
			_text(origin + Vector2(16,145), "DASH READS", 12, muted)
			for i in required_reads:
				var at := origin + Vector2(111+i*17,140)
				draw_circle(at,5,teal if i < clean_reads else Color("c6cbbd"))
				draw_arc(at,5,0,TAU,20,teal,1,true)
		_text(origin + Vector2(188,145), ("REEL ON" if reel_active else "REEL OFF") if toggle_controls else "H  GUIDE     X  RELEASE", 12, muted)
	else:
		_text(origin + Vector2(16,104), ("LURE ON · SETTLE EACH PULSE" if reel_active else "LURE OFF · SETTLE EACH PULSE") if toggle_controls else "H  GUIDE", 12, muted)
	if state == "fight":
		var caption := "Follow the arrow · release during dashes"
		if required_reads > clean_reads:
			caption = "%d MORE DASH%s: REST + %s" % [required_reads-clean_reads,"ES" if required_reads-clean_reads>1 else "", "A ←" if counter<0 else "D →"]
		if toggle_controls and steer_active == 0:
			caption += " · STEER OFF" if required_reads>clean_reads else " · A/D OFF"
		_text(origin+Vector2(16,168),caption,12,amber if progress>=.9 and required_reads>clean_reads else muted)
	if detailed:
		var y := origin.y + height - 44
		_text(Vector2(origin.x+16,y), _wrapped(explanation)[0],14,muted)
		if _wrapped(explanation).size()>1: _text(Vector2(origin.x+16,y+20),_wrapped(explanation)[1],14,muted)
	# The cue follows the actual fish/float, not a fixed empty area of the water.
	if show_world_cue:
		var cue_at := fish_screen + Vector2(0,-42)
		cue_at.x = clampf(cue_at.x,28,1412)
		cue_at.y = clampf(cue_at.y,100,805)
		if state == "hook":
			draw_circle(cue_at,18,cream)
			_text(cue_at+Vector2(-4,7),"!",23,coral)
		elif state == "fight":
			var side := -1.0 if counter < 0 else 1.0
			var head := cue_at + Vector2(side*15,0)
			draw_line(cue_at-Vector2(side*12,0),head,Color("183e4666"),6,true)
			draw_line(cue_at-Vector2(side*12,0),head,Color("faf0d5"),3,true)
			for vertical in [-1,1]: draw_line(head,head-Vector2(side*7,float(vertical)*6),Color("faf0d5"),3,true)
			if tension>.7: draw_arc(cue_at,24,-PI/2,-PI/2+TAU*tension,32,coral,3,true)

func _wrapped(text: String) -> Array[String]:
	var lines: Array[String] = [""]
	for word in text.split(" "):
		var candidate := lines[-1] + (" " if not lines[-1].is_empty() else "") + word
		if font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x > 338:
			lines.append(word)
		else: lines[-1] = candidate
	return lines
