extends Node3D
## Owns expedition rules, persistence, menus, and presentation. Fishing and traversal are isolated.
const World = preload("res://scripts/world.gd")
const Actor = preload("res://scripts/actor.gd")
const Fishing = preload("res://scripts/fishing.gd")
const FishingHud = preload("res://scripts/fishing_hud.gd")
const REGIONS = ["Sunwake Harbor", "Jade Lagoon", "Stormglass Reach"]
const SEASONS = ["Summer", "Autumn", "Winter"]
const TACKLE = ["Float", "Spinner", "Jig"]
const PRESENTATION = ["Drift", "Twitch", "Deep"]
const SAVE = "user://last_cast.json"
const PERKS = [
	{"name":"Silk leader", "text":"−22% tension gain. Pair with a steady reel.", "key":"control", "amount":0.22},
	{"name":"Quick spool", "text":"+25% landing speed. Powerful with Silk leader.", "key":"power", "amount":0.25},
	{"name":"Patient hook", "text":"+0.45s hook window. Read the strike comfortably.", "key":"hook", "amount":0.45},
	{"name":"Reed charm", "text":"−30% surge force. Keeps quick spools manageable.", "key":"calm", "amount":0.3},
	{"name":"Picnic basket", "text":"+2 catch capacity this expedition.", "key":"capacity", "amount":2.0},
	{"name":"Golden hour", "text":"+75 seconds of daylight this expedition.", "key":"daylight", "amount":75.0},
	{"name":"Bait tin", "text":"+3 fresh bait. Fill an expanded basket, or recover from missed strikes.", "key":"bait", "amount":3.0}]
var world: Node3D
var actor: CharacterBody3D
var fishing: RefCounted
var coins := 0
var boat_owned := false
var rod_level := 0
var basket_level := 0
var unlocked := 0
var mastery := 0
var day := 0
var region := 0
var season := 0
var active := false
var daylight := 240.0
var bait := 8
var catches: Array = []
var perks: Array = []
var collection: Dictionary = {}
var tackle := 0
var presentation := 0
var landed_this_run := 0
var toggle_controls := false
var focus_pace := false
var muted := false
var detailed_guidance := false
var catch_reveal := 0.0
var landed_pending: Dictionary = {}
var reel_latch := false
var steer_latch := 0.0
var pending_perk := false
var pause_when_unfocused := not OS.get_cmdline_user_args().has("--keep-running-unfocused")
var modal := false
var initialized := false
var toast_time := 0.0
var elapsed := 0.0
var save_timer := 0.0
var last_state := ""
var cast_target := Vector3.ZERO
var root_ui: Control
var region_label: Label
var resources_label: Label
var goal_label: Label
var context_label: Label
var toast_label: Label
var fishing_hud: Control
var overlay: ColorRect
var modal_panel: PanelContainer
var modal_box: VBoxContainer
var map: Control
var audio: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var audio_time := 0.0
var noise_smooth := 0.0
var sounds: Array = []
var signal_rings: Array = []

func _ready() -> void:
	var renderer := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	print("LAST_CAST_RENDERER method=%s driver=%s device=%s" % [renderer, driver, RenderingServer.get_video_adapter_name()])
	if renderer != "forward_plus" or RenderingServer.get_rendering_device() == null:
		push_error("Last Cast requires Forward+. Remove renderer overrides and use a RenderingDevice-capable desktop GPU.")
		get_tree().quit(1)
		return
	_load()
	world = World.new(); add_child(world); world.build(region, season)
	actor = Actor.new(); add_child(actor); actor.setup(); actor.toggle_controls = toggle_controls
	_home()
	Engine.time_scale = .10 if focus_pace else 1.0
	fishing = Fishing.new()
	fishing.landed.connect(_landed); fishing.escaped.connect(_escaped); fishing.cue.connect(_sound)
	_build_ui(); _start_audio(); _make_rings(); AudioServer.set_bus_mute(0,muted)
	initialized = true
	if day == 0: _intro()
	else: _welcome()
	_log("launch", {"pause_when_unfocused":pause_when_unfocused,"continued_expedition":active, "coins":coins, "unlocked":unlocked})

func _input(event: InputEvent) -> void:
	if not initialized or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F12:
		_capture(); return
	if event.keycode == KEY_ESCAPE:
		if modal: _close_modal()
		else: _pause_menu()
		get_viewport().set_input_as_handled(); return
	if modal or catch_reveal > 0: return
	match event.keycode:
		KEY_SPACE:
			if fishing.state in ["casting","hook"]: fishing.press(); reel_latch=false
			elif toggle_controls and fishing.state in ["presentation","fight"]: reel_latch=not reel_latch
		KEY_A, KEY_D:
			if toggle_controls and fishing.state != "idle":
				var direction := -1.0 if event.keycode == KEY_A else 1.0
				steer_latch=0.0 if steer_latch==direction else direction
		KEY_F:
			if fishing.state == "idle": _cast()
		KEY_X:
			if fishing.state != "idle": fishing.cancel(); actor.set_fishing(false); _save()
		KEY_E: _interact()
		KEY_T: if fishing.state == "idle": tackle = (tackle + 1) % 3; _setup_changed()
		KEY_G: if fishing.state == "idle": presentation = (presentation + 1) % 3; _setup_changed()
		KEY_J: _journal()
		KEY_H: _help()
		KEY_R:
			if fishing.state == "idle" and actor.position.z < 9: _return_menu()

func _setup_changed() -> void:
	_sound("tick")
	var quarry := Fishing.preview(region,season,_spot(),tackle,presentation)
	_toast(quarry.hint,7)

func _process(dt: float) -> void:
	if not initialized: return
	elapsed += dt
	_synthesize()
	actor.locked = modal or fishing.state != "idle" or catch_reveal > 0
	actor.fish_fighting = fishing.state == "fight"
	actor.fish_surge = fishing.phase_label.begins_with("DASH •")
	actor.line_tension = fishing.tension
	actor.visual_reeling = fishing.state in ["presentation", "fight"] and (reel_latch if toggle_controls else Input.is_physical_key_pressed(KEY_SPACE))
	actor.fish_exhaustion = fishing.progress if fishing.state == "fight" else 0.0
	fishing.focus_assist = focus_pace
	if not modal:
		if catch_reveal > 0:
			catch_reveal = maxf(0.0, catch_reveal - dt / Engine.time_scale)
			if catch_reveal == 0: _show_landing_menu()
		if active and not modal and catch_reveal == 0:
			daylight = maxf(0, daylight - dt)
			if world.has_method("set_daylight"): world.set_daylight(clampf(daylight/240.0,0,1))
			if daylight <= 0: _fail()
		if fishing.state != "idle":
			fishing.update(dt, reel_latch if toggle_controls else Input.is_physical_key_pressed(KEY_SPACE), steer_latch if toggle_controls else float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)))
			var pull := smoothstep(.15, 1.0, fishing.progress) if fishing.state == "fight" else 0.0
			var reach := actor.position.lerp(cast_target, lerpf(1.0,.42,pull))
			reach.y = .15
			if not actor.sailing:
				reach.z = maxf(reach.z,5.4 if actor.position.x < -4 else 8.4)
				reach.x = minf(reach.x,-14.7 if actor.position.x < -4 else -2.7)
			actor.set_line_target(reach + Vector3(-fishing.fish_dir * lerpf(1.6,.6,pull),0,0), true)
		else: actor.set_line_target(Vector3.ZERO, false)
		toast_time = maxf(0, toast_time - dt)
		save_timer += dt
		if save_timer > 5: save_timer = 0; _save()
	if fishing.state != last_state:
		_log("fishing_state", {"focus_pace":focus_pace,"toggle_controls":toggle_controls,"state":fishing.state, "tension":snappedf(fishing.tension,.01), "progress":snappedf(fishing.progress,.01)})
		last_state = fishing.state
	_update_ui()
	for i in signal_rings.size():
		var ring: MeshInstance3D = signal_rings[i]
		ring.scale = Vector3.ONE * (1.0 + sin(elapsed * 1.5 + i) * .08)
		ring.position.y = .13 + sin(elapsed * 2 + i) * .015

func _home() -> void:
	actor.reset_home()
	if boat_owned:
		actor.position = Vector3(0, 1.03, 6)

func _near_dock() -> bool:
	return absf(actor.position.x) <= 5.0 and actor.position.z <= 11.0

func _spot() -> int:
	if actor.sailing: return 2 if actor.position.z > 15 else 0
	return 1 if actor.position.x > -4 else 0

func _can_fish() -> bool:
	return actor.sailing or (actor.position.z > .2 and (absf(actor.position.x) < 2.0 or absf(actor.position.x + 12) < 2.0))

func _bonuses() -> Dictionary:
	var result := {"control":rod_level * .12, "power":rod_level * .10, "hook":0.0, "calm":0.0}
	for p in perks:
		var perk: Dictionary = PERKS[int(p)]
		result[perk.key] = result.get(perk.key, 0.0) + perk.amount
	return result

func _capacity() -> int:
	return 6 + basket_level * 2 + int(_bonuses().get("capacity",0))

func _value() -> int:
	var total := 0
	for fish in catches: total += int(fish.value)
	return total

func _cast() -> void:
	if pending_perk: _perk_menu(landed_this_run == 0); return
	if not _can_fish(): _toast("Walk onto either pier, or fish from your boat."); return
	if not active: _expedition_menu(); return
	if catches.size() >= _capacity(): _toast("Basket full. Return to the buyer, or release a catch in the journal [J]."); return
	if bait <= 0: _toast("No bait left. Bank your catch at the buyer; each new expedition restocks for free."); return
	bait -= 1
	reel_latch=false;steer_latch=0.0
	cast_target = actor.position + Vector3(0 if actor.sailing else -4,-actor.position.y + .15,6)
	fishing.begin(region,season,_spot(),tackle,presentation,_bonuses())
	actor.set_fish_appearance(fishing.fish)
	actor.set_fishing(true)
	_save(); _log("cast", {"region":region,"season":season,"spot":_spot(),"tackle":tackle,"presentation":presentation,"bait":bait})

func _landed(fish: Dictionary) -> void:
	var catch_data := fish.duplicate(true)
	catch_data["value"] = int(catch_data.value)
	catches.append(catch_data); landed_this_run += 1
	actor.set_fishing(false); pending_perk=landed_this_run % 2 == 0; _save()
	_log("landed", {"focus_pace":focus_pace,"fish":catch_data,"basket":catches.size()})
	landed_pending = catch_data
	catch_reveal = 1.8
	actor.locked = true

func _show_landing_menu() -> void:
	var fish := landed_pending
	if fish.is_empty(): return
	_open_modal("%s landed" % fish.name, "%s  •  %d shells\n%s\n\nBasket %d / %d · %ds of light · %d bait\nCatch is unbanked until you return to the buyer." % [fish.name,fish.value,fish.get("behavior",""),catches.size(),_capacity(),ceili(daylight),bait])
	_button("Keep fishing", func():
		_close_modal()
		if pending_perk: _perk_menu(false))
	_button("Plan my return", func(): _close_modal(); _toast("Harbor buyer: cream awning at the right of the square. [R] near harbor also opens banking."))
	landed_pending = {}

func _escaped(reason: String) -> void:
	actor.set_fishing(false); _toast(reason,6); _save(); _log("escaped",{"reason":reason})

func _interact() -> void:
	if fishing.state != "idle": return
	if actor.sailing:
		if _near_dock():
			var arrival := actor.position
			actor.dock(); _sound("dock"); _log("dock",{"arrival":str(arrival)}); _save()
		else: _toast("Approach either side of the long central pier, then press E to dock.")
		return
	var p := actor.position
	if Vector2(p.x+8,p.z+3).length() < 4: _shop(); return
	if Vector2(p.x-6,p.z+3).length() < 4: _return_menu(); return
	if absf(p.x) < 3 and p.z > 2:
		if boat_owned: actor.board(); _sound("dock"); _log("board",{}); _save()
		else: _toast("Your first boat costs 65 shells. Visit Tackle & Tide; about three shore catches will do.",6)
		return
	_toast("Tackle shop: left awning. Buyer: right awning. Board at the anchor on the long pier.")

func _begin_run() -> void:
	catch_reveal=0.0; landed_pending={}
	active = true; day += 1; daylight = 240; bait = 8; catches.clear(); perks.clear(); landed_this_run = 0; pending_perk=true
	_save(); _log("expedition_begin",{"day":day,"region":region,"season":season})
	_perk_menu(true)

func _perk_menu(initial: bool) -> void:
	_open_modal("Pack a little possibility" if initial else "The tide brings a choice", "Choose one temporary expedition upgrade. Combinations last until you bank or call rescue.\nDaylight pauses while you choose.")
	var picks: Array = [0,1,2] if initial else ([3,4,5,6] if landed_this_run % 4 == 2 else [0,1,2,6])
	for index in picks:
		var p: Dictionary = PERKS[index]
		_button(p.name + "\n" + p.text, func():
			pending_perk=false; perks.append(index)
			if p.key == "daylight": daylight += p.amount
			if p.key == "bait": bait += int(p.amount)
			_log("upgrade",{"name":p.name,"perks":perks.duplicate(),"bonuses":_bonuses()}); _save(); _close_modal(); _toast("%s packed. [F] to cast. [T] tackle · [G] presentation." % p.name,5))

func _expedition_menu() -> void:
	_open_modal("Where the light takes you", "A 4-minute expedition. 8 bait. %d catch slots.\nBank at the harbor buyer before sunset. Rescue loses unbanked fish, never your shells, equipment, boat, or unlocks.\n\nChoose a coast, then pack one temporary upgrade." % _capacity())
	for i in 3:
		var detail: String = ["Gentle silver shoals · Sunscale Mullet", "Reed ambushes · Moonpetal Koi", "Double dashes · Stormglass Sailfish"][i]
		_button(("✓ " if i == region else "") + REGIONS[i] + "  —  " + (detail if i <= unlocked else "Bank the previous coast’s signature to unlock"), func():
			region=i; world.build(region,season); _home(); _make_rings(); _expedition_menu(), i > unlocked)
	_button("Season: %s  ·  %s" % [SEASONS[season],["forgiving currents","new quarry · quicker dashes · +30% values","new quarry · hardest currents · +60% values"][season]],func(): season=(season+1)%3; world.build(region,season); _make_rings(); _expedition_menu())
	_button("Begin expedition", _begin_run)
	_button("Back to harbor", _close_modal)

func _return_menu() -> void:
	_open_modal("Fresh catch, safe harbor", "%d fish · %d shells to bank\nBanking ends the expedition and records signature catches. Your next trip begins with fresh bait and daylight." % [catches.size(),_value()])
	if active: _button("Bank catch & end expedition", _bank)
	else: _button("Set out on an expedition", _expedition_menu)
	_button("Back", _close_modal)

func _bank() -> void:
	catch_reveal=0.0; landed_pending={}
	var income := _value()
	coins += income
	var new_region := false
	var stormglass_landed := false
	for fish in catches:
		collection[fish.id] = int(collection.get(fish.id,0)) + 1
		if fish.get("signature",false):
			if int(fish.region) < 2 and unlocked <= int(fish.region): unlocked = int(fish.region)+1; new_region=true
			if int(fish.region) == 2:
				mastery = maxi(mastery, int(fish.season)+1)
				stormglass_landed = true
	_log("bank",{"income":income,"fish":catches.duplicate(true),"unlocked":unlocked,"mastery":mastery})
	active=false; pending_perk=false; catches.clear(); perks.clear(); _home(); world.set_daylight(1.0); _save(); _sound("land")
	var chapter_note := "Visit Tackle & Tide for equipment, or set out on another tide."
	if stormglass_landed:
		chapter_note = "Stormglass winter mastered. Explore the other coasts and complete your notebook." if mastery >= 3 else "Stormglass signature landed. Coast progression complete! Try a harder season or fill your notebook."
	_open_modal("Home before the lanterns", "+%d shells banked.  Purse: %d\n%s\n%s" % [income,coins,"A new coast is open on the expedition chart." if new_region else "Equipment and catch records saved.",chapter_note])
	_button("Another expedition", _expedition_menu)
	_button("Walk the harbor", _close_modal)

func _fail() -> void:
	catch_reveal=0.0; landed_pending={}
	fishing.cancel(); actor.set_fishing(false)
	var lost := catches.size(); var value := _value()
	active=false; pending_perk=false; catches.clear(); perks.clear(); _home(); world.set_daylight(1.0); _save(); _log("rescue",{"lost_fish":lost,"lost_value":value,"coins_preserved":coins,"boat_preserved":boat_owned})
	_open_modal("The harbor light finds you", "Rescue brought you home. %d unbanked fish (%d shells) returned to the sea.\n\nYour %d shells, purchased equipment, boat, and unlocked coasts are safe.\nNext expedition: full daylight and 8 free bait." % [lost,value,coins])
	_button("Try a fresh expedition", _expedition_menu)
	_button("Rest in harbor", _close_modal)

func _shop() -> void:
	_open_modal("Tackle & Tide", "%d shells in your purse\nAll three basic tackle types are yours from the start. [T] cycles tackle; [G] cycles presentation. Permanent purchases survive every expedition." % coins)
	_button("Harbor skiff  ·  65 shells" if not boat_owned else "✓ Harbor skiff owned",func(): coins-=65; boat_owned=true; _save(); _log("purchase",{"item":"boat"}); _shop(), boat_owned or coins<65)
	_button("Balanced rod  ·  %d / 2  ·  %d shells\n+12%% line control and +10%% landing speed per level" % [rod_level,55+rod_level*30],func():coins-=55+rod_level*30;rod_level+=1;_save();_log("purchase",{"item":"rod","level":rod_level});_shop(),rod_level>=2 or coins<55+rod_level*30)
	_button("Woven creel  ·  %d / 2  ·  %d shells\n+2 permanent catch slots per level" % [basket_level,40+basket_level*25],func():coins-=40+basket_level*25;basket_level+=1;_save();_shop(),basket_level>=2 or coins<40+basket_level*25)
	_button("Back to the sunshine",_close_modal)

func _intro() -> void:
	_open_modal("Last Cast", "ONE MORE FISH BEFORE THE LIGHT FADES\n\nWelcome to Sunwake. Your old rod, three tackle types, and a pocket of bait are all you need.\n\nStart at the little shore pier. Read the shoal, cast, and bring a few fish to the buyer. Three good catches can buy your first boat. The shore will always hold valuable fish of its own.")
	_button("Show me how to fish",_help)
	_button("Step into the harbor",func():_close_modal();_toast("[F] begins your first expedition. [H] is your field guide whenever you need it.",8))

func _welcome() -> void:
	_open_modal("Last Cast", "THE SEA REMEMBERS\n\nDay %d · %d shells · %s\n%s" % [day,coins,REGIONS[unlocked],"Your expedition resumes at the harbor with remaining daylight, supplies, and catch. An interrupted cast is released; its bait stays spent." if active else "Your equipment and catch records are ready for another tide."])
	_button("Continue",_close_modal)
	_button("Field guide",_help)

func _help() -> void:
	_open_modal("A field guide to one more fish", "WASD  Move / steer boat     Shift  Run     Right-drag  Look     Wheel  Zoom\nE  Shop / buyer / board / dock     R  Bank near harbor     Esc  Pause\n\n1  READ: small dimples and fish shadows mark feeding water. The long pier and outer water hold signature fish. [J] lists their recipes.\n2  CHOOSE: [T] Float / Spinner / Jig. [G] Drift / Twitch / Deep.\n3  CAST: [F], then [Space] at 55–80% on the casting meter. Follow the presentation cue; [Space] hooks when the strike appears.\n4  FIGHT: hold Space to reel in calm water. Release during surges. Use A / D to follow the COUNTER direction. Keep tension below full. Releasing safely cools the line. Signatures need TWO dashes with release + correct counter-steering; the tally is shown.\n\nYou lose only one bait on an escaped fish. Bank before daylight ends to keep your catch. Menus pause daylight. [J] shows your basket and records.\nACCESSIBILITY: Esc offers toggle controls and a slower Focus pace.")
	_button("Ready for the water",_close_modal)

func _journal() -> void:
	_open_modal("The salt-stained notebook", "BASKET  %d / %d  ·  %d shells unbanked\n%s\n\nEXPEDITION UPGRADES\n%s\n\nSIGNATURE RECIPES\nSunwake: Spinner + Twitch at the long pier\nJade: Float + Drift at the long pier\nStormglass: Jig + Deep at the long pier\nThe outer water also holds each coast’s signature. Bank it to unlock the next coast.\n\nBANKED SPECIES: %d   ·   HIGHEST STORMGLASS SEASON MASTERED: %d / 3" % [catches.size(),_capacity(),_value(),_basket_text(),_perk_text(),collection.size(),mastery])
	if not catches.is_empty(): _button("Release lowest-value catch (no shells)",func():
		var lowest:=0
		for i in catches.size():
			if catches[i].value < catches[lowest].value: lowest=i
		catches.remove_at(lowest);_save();_journal())
	_button("Close notebook",_close_modal)

func _basket_text() -> String:
	var lines: PackedStringArray=[]
	for fish in catches: lines.append("%s · %d" % [fish.name,fish.value])
	return "  /  ".join(lines) if not lines.is_empty() else "Nothing yet. The water is full of possibility."

func _perk_text() -> String:
	var lines: PackedStringArray=[]
	for i in perks: lines.append(PERKS[int(i)].name)
	return " + ".join(lines) if not lines.is_empty() else "Choose an upgrade at the beginning of each expedition."

func _pause_menu() -> void:
	_open_modal("A moment on the coast", "Daylight is paused. Progress saves automatically. Toggle controls remove the need to hold keys. Focus pace slows the expedition to 10%, extends hook windows and signature cues, and keeps every skill requirement and reward.")
	_button("Resume",_close_modal)
	_button("Field guide",_help)
	_button("Catch notebook",_journal)
	_button("Held controls: %s" % ("TOGGLE — tap again to release" if toggle_controls else "HOLD — standard controls"),func():toggle_controls=not toggle_controls;actor.toggle_controls=toggle_controls;actor.clear_controls();reel_latch=false;steer_latch=0;_save();_pause_menu())
	_button("Fishing pace: %s" % ("FOCUS — slow, extended cues" if focus_pace else "NORMAL"),func():focus_pace=not focus_pace;Engine.time_scale=.10 if focus_pace else 1.0;_save();_pause_menu())
	_button("On-screen guidance: %s" % ("DETAILED" if detailed_guidance else "COMPACT"),func():detailed_guidance=not detailed_guidance;_save();_pause_menu())
	_button("Sound: %s" % ("MUTED" if muted else "ON"),func():muted=not muted;AudioServer.set_bus_mute(0,muted);_save();_pause_menu())
	if active: _button("Call rescue — lose unbanked catch",func():
		_open_modal("Leave the catch behind?", "Rescue ends this expedition. All %d unbanked fish will be lost; purchased equipment, shells, and unlocks remain." % catches.size())
		_button("Call rescue",_fail);_button("Keep the expedition",_close_modal))
	_button("Save & quit",func():_save();get_tree().quit())

func _save() -> void:
	var data := {"version":1,"detailed_guidance":detailed_guidance,"toggle_controls":toggle_controls,"focus_pace":focus_pace,"muted":muted,"pending_perk":pending_perk,"coins":coins,"boat":boat_owned,"rod":rod_level,"basket":basket_level,"unlocked":unlocked,"mastery":mastery,"day":day,"region":region,"season":season,"active":active,"daylight":daylight,"bait":bait,"catches":catches,"perks":perks,"collection":collection,"tackle":tackle,"presentation":presentation,"landed":landed_this_run}
	var file := FileAccess.open(SAVE+".tmp",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data));file.close()
		DirAccess.rename_absolute(SAVE+".tmp",SAVE)

func _load() -> void:
	if not FileAccess.file_exists(SAVE):return
	var file:=FileAccess.open(SAVE,FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text()) if file else null
	if not data is Dictionary:return
	detailed_guidance=bool(data.get("detailed_guidance",false))
	toggle_controls=bool(data.get("toggle_controls",false));focus_pace=bool(data.get("focus_pace",false));muted=bool(data.get("muted",false));pending_perk=bool(data.get("pending_perk",false))
	coins=int(data.get("coins",0));boat_owned=bool(data.get("boat",false));rod_level=clampi(int(data.get("rod",0)),0,2);basket_level=clampi(int(data.get("basket",0)),0,2)
	unlocked=clampi(int(data.get("unlocked",0)),0,2);mastery=int(data.get("mastery",0));day=int(data.get("day",0));region=clampi(int(data.get("region",0)),0,unlocked);season=clampi(int(data.get("season",0)),0,2)
	active=bool(data.get("active",false));daylight=float(data.get("daylight",240));bait=int(data.get("bait",8));catches=data.get("catches",[]);perks=data.get("perks",[]);collection=data.get("collection",{});tackle=int(data.get("tackle",0));presentation=int(data.get("presentation",0));landed_this_run=int(data.get("landed",0))

func _log(event: String,data:Dictionary) -> void:
	var path := "user://voyage_log.jsonl"
	var file := FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file: file.seek_end();file.store_line(JSON.stringify({"time":Time.get_datetime_string_from_system(),"event":event,"data":data}))
	print("LAST_CAST ",event," ",JSON.stringify(data))

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var path := "user://last_cast_%d.png" % Time.get_unix_time_from_system()
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ",ProjectSettings.globalize_path(path))
	_log("screenshot",{"file":path,"position":str(actor.position),"sailing":actor.sailing,"boat_speed":snappedf(actor.boat_speed,.01),"boat_heading":snappedf(actor.boat_heading,.01),"state":fishing.state,"fps":Engine.get_frames_per_second(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"frame_cpu_ms":snappedf(Performance.get_monitor(Performance.TIME_PROCESS)*1000,.01),"camera":str(actor.camera.global_position),"phase":fishing.phase_label,"focus_pace":focus_pace,"toggle_controls":toggle_controls})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and initialized: _save()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_when_unfocused and initialized and not modal:
		await get_tree().create_timer(.3,true,false,true).timeout
		if not DisplayServer.window_is_focused() and not modal: _pause_menu()

func _style(bg: Color, border := Color("c5b994"),radius := 14) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=bg;s.border_color=border
	s.set_border_width_all(1);s.set_corner_radius_all(radius)
	s.content_margin_left=22;s.content_margin_right=22;s.content_margin_top=16;s.content_margin_bottom=16
	return s

func _label(text_value:String,size:int=20,color:=Color("213f46")) -> Label:
	var l:=Label.new();l.text=text_value;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color)
	return l

func _panel(parent:Node,at:Vector2,size:Vector2)->PanelContainer:
	var p:=PanelContainer.new();parent.add_child(p);p.position=at;p.custom_minimum_size=size;p.add_theme_stylebox_override("panel",_style(Color("f5eddaeb")))
	return p

func _build_ui()->void:
	var layer:=CanvasLayer.new();add_child(layer)
	root_ui=Control.new();layer.add_child(root_ui);root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root_ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme:=Theme.new()
	theme.default_font_size=19
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Avenir Next","Noto Sans","DejaVu Sans"]);theme.default_font=font
	theme.set_stylebox("normal","Button",_style(Color("f7efdc")))
	theme.set_stylebox("hover","Button",_style(Color("fff9e9"),Color("2a777b")))
	theme.set_stylebox("pressed","Button",_style(Color("d3e2cc"),Color("286169")))
	theme.set_stylebox("focus","Button",_style(Color("ffffff00"),Color("2a777b")))
	theme.set_stylebox("disabled","Button",_style(Color("d7d6c9"),Color("bdbdaa")))
	for s in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:theme.set_color(s,"Button",Color("244951"))
	theme.set_color("font_disabled_color","Button",Color("7b837b"))
	root_ui.theme=theme
	var top_left:=_panel(root_ui,Vector2(26,24),Vector2(270,84))
	region_label=_label("",20);top_left.add_child(region_label)
	var top_right:=_panel(root_ui,Vector2(1150,24),Vector2(262,84))
	resources_label=_label("",20);top_right.add_child(resources_label)
	var goal_panel:=_panel(root_ui,Vector2(26,121),Vector2(330,58))
	goal_label=_label("",15);goal_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;goal_label.custom_minimum_size.x=286;goal_panel.add_child(goal_label)
	var bottom:=_panel(root_ui,Vector2(430,814),Vector2(580,60))
	context_label=_label("",16);context_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;context_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;context_label.custom_minimum_size.x=536;bottom.add_child(context_label)
	toast_label=_label("",21,Color("fff7dd"));root_ui.add_child(toast_label);toast_label.position=Vector2(180,750);toast_label.size=Vector2(1120,68);toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;toast_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_shadow_color",Color("142e36"));toast_label.add_theme_constant_override("shadow_outline_size",7)
	var credit:=_label("LAST CAST  /  [H] Field guide  ·  [J] Notebook",14,Color("fff5dd"));root_ui.add_child(credit);credit.position=Vector2(28,866)
	fishing_hud=FishingHud.new();root_ui.add_child(fishing_hud);fishing_hud.font=font
	overlay=ColorRect.new();root_ui.add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.color=Color(.04,.14,.17,.43);overlay.visible=false
	modal_panel=_panel(overlay,Vector2(345,100),Vector2(750,0))
	modal_box=VBoxContainer.new();modal_box.add_theme_constant_override("separation",12);modal_panel.add_child(modal_box)
	# Compass chart is drawn from actual player position and harbor coordinates.
	map=Control.new();root_ui.add_child(map);map.position=Vector2(28,710);map.scale=Vector2.ONE*.82;map.size=Vector2(168,168);map.mouse_filter=Control.MOUSE_FILTER_IGNORE;map.draw.connect(_draw_map)

func _open_modal(title:String,body:String)->void:
	modal=true;overlay.visible=true;actor.locked=true;actor.clear_controls()
	for child in modal_box.get_children():modal_box.remove_child(child);child.queue_free()
	var heading:=_label(title,34)
	var serif:=SystemFont.new();serif.font_names=PackedStringArray(["Georgia","Noto Serif","DejaVu Serif"]);heading.add_theme_font_override("font",serif)
	modal_box.add_child(heading)
	var text_label:=_label(body,18);text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text_label.custom_minimum_size.x=700;modal_box.add_child(text_label)
	modal_panel.size=Vector2(750,0)
	_fit_modal.call_deferred()

func _button(text_value:String,callback:Callable,disabled:=false)->void:
	var b:=Button.new();b.text=text_value;b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.disabled=disabled;b.custom_minimum_size.y=48;b.add_theme_font_size_override("font_size",17);modal_box.add_child(b);b.pressed.connect(callback)
	if modal_box.get_child_count()==3 and not disabled:b.grab_focus()

func _close_modal()->void:
	modal=false;overlay.visible=false;actor.locked=fishing.state!="idle"
	var focused := get_viewport().gui_get_focus_owner()
	if focused: focused.release_focus()

func _toast(text_value:String,duration:=4.0)->void:
	toast_label.text=text_value;toast_time=duration

func _update_ui()->void:
	region_label.text="%s\n%s · Day %02d   %s" % [REGIONS[region],SEASONS[season],maxi(day,1),"%02d:%02d" % [int(daylight)/60,int(daylight)%60] if active else "HARBOR"]
	resources_label.text="◉  %d shells\n▣  %d / %d catch   ·   %d bait" % [coins,catches.size(),_capacity(),bait]
	goal_label.text="FIRST BOAT · %d / 65 shells\nBank at Fresh Catch" % coins if not boat_owned else "NEXT CATCH\n" + ["Sunscale Mullet","Moonpetal Koi","Stormglass Sailfish"][unlocked]
	if boat_owned and mastery>0: goal_label.text="COAST JOURNEY COMPLETE\nStormglass %s" % SEASONS[clampi(mastery-1,0,2)]
	if active and daylight<45: goal_label.text="SUNSET · %ds\nReturn to bank your catch" % ceili(daylight)
	goal_label.get_parent().visible=not modal and (fishing.state=="idle" or (active and daylight<45))
	fishing_hud.visible=not modal and catch_reveal<=0
	fishing_hud.state=fishing.state
	fishing_hud.species=str(fishing.fish.get("name",""))
	fishing_hud.phase=fishing.phase_label
	fishing_hud.progress=fishing.progress
	fishing_hud.tension=fishing.tension
	fishing_hud.counter=fishing.target_dir
	fishing_hud.clean_reads=fishing.clean_dashes
	fishing_hud.required_reads=fishing.required_clean_dashes
	fishing_hud.reel_active=reel_latch if toggle_controls else Input.is_physical_key_pressed(KEY_SPACE)
	fishing_hud.steer_active=steer_latch if toggle_controls else float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
	fishing_hud.toggle_controls=toggle_controls
	fishing_hud.detailed=detailed_guidance
	fishing_hud.instruction=fishing.instruction
	var cue_node: Node3D=actor.hooked_fish if fishing.state=="fight" else actor.bobber
	fishing_hud.show_world_cue=fishing.state in ["hook","fight"] and cue_node.visible and not actor.camera.is_position_behind(cue_node.global_position)
	if fishing_hud.show_world_cue: fishing_hud.fish_screen=actor.camera.unproject_position(cue_node.global_position)
	fishing_hud.queue_redraw()
	context_label.get_parent().visible=fishing.state=="idle" and not modal and catch_reveal<=0
	if fishing.state=="idle":
		var fish:Dictionary=Fishing.preview(region,season,_spot(),tackle,presentation)
		var interaction := ("E Dock" if _near_dock() else "E Return to pier") if actor.sailing else ("E Board" if boat_owned and absf(actor.position.x)<3 and actor.position.z>2 else "E Interact")
		if _can_fish():
			context_label.text="F %s   ·   %s   ·   H Guide\nT %s  /  G %s   ·   %s" % ["Fish" if active else "Begin",interaction,TACKLE[tackle],PRESENTATION[presentation],fish.name]
		else: context_label.text="WASD Walk   ·   Shift Run   ·   E Interact\nTackle & Tide ←    Fresh Catch →"
	toast_label.visible=toast_time>0 and not modal and fishing.state=="idle"
	map.visible=not modal;map.queue_redraw()

func _draw_map()->void:
	var center:=Vector2(84,84)
	map.draw_circle(center,79,Color("234f5bbd"));map.draw_arc(center,80,0,TAU,64,Color("ede0b8"),2,true)
	map.draw_colored_polygon(PackedVector2Array([Vector2(15,34),Vector2(153,34),Vector2(155,73),Vector2(108,73),Vector2(108,99),Vector2(101,99),Vector2(101,73),Vector2(69,73),Vector2(69,88),Vector2(62,88),Vector2(62,73),Vector2(15,73)]),Color("b9bf9d"))
	for point in [Vector2(76,58),Vector2(118,58)]:map.draw_rect(Rect2(point,Vector2(9,7)),Color("f5d08d"))
	var p:=Vector2(84+actor.position.x*1.55,74+actor.position.z*1.55)
	p=center+(p-center).limit_length(74)
	map.draw_circle(p,5,Color("fbc56c"));map.draw_arc(p,7,0,TAU,16,Color("fff3cb"),1.5,true)
	map.draw_string(root_ui.theme.default_font,Vector2(74,26),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f4e5c5"))

func _make_rings()->void:
	for ring in signal_rings:
		if is_instance_valid(ring):ring.queue_free()
	signal_rings.clear()
	for point in [Vector3(-12,.13,9),Vector3(0,.13,12),Vector3(9,.13,24),Vector3(-13,.13,30)]:
		# Broken dimples indicate a feeding shoal without drawing targets over the sea.
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in 2:
			for arc in 3:
				var start := arc * TAU / 3 + r * .7
				var radius := .75 + r * .6
				for segment in 10:
					var a := start + segment * .065
					var b := a + .065
					var v0 := Vector3(cos(a)*radius,0,sin(a)*radius)
					var v1 := Vector3(cos(b)*radius,0,sin(b)*radius)
					var v2 := Vector3(cos(b)*(radius+.022),0,sin(b)*(radius+.022))
					var v3 := Vector3(cos(a)*(radius+.022),0,sin(a)*(radius+.022))
					for vertex in [v0,v2,v1,v0,v3,v2]: mesh.surface_add_vertex(vertex)
		mesh.surface_end()
		var node := MeshInstance3D.new(); node.mesh=mesh; node.position=point
		var mat := StandardMaterial3D.new();mat.albedo_color=Color("a3c8b5");mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;node.material_override=mat
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node);signal_rings.append(node)

func _start_audio()->void:
	audio=AudioStreamPlayer.new();add_child(audio)
	var stream:=AudioStreamGenerator.new();stream.mix_rate=22050;stream.buffer_length=.15;audio.stream=stream;audio.volume_db=-12;audio.play();playback=audio.get_stream_playback()

func _sound(kind:String)->void:
	if actor and actor.has_method("fishing_cue"): actor.fishing_cue(kind)
	sounds.append({"kind":kind,"start":audio_time})

func _synthesize()->void:
	if playback==null:return
	for frame in playback.get_frames_available():
		audio_time+=1.0/22050.0
		var n:=randf_range(-1,1);noise_smooth=lerpf(noise_smooth,n,.025)
		var sample_value:=noise_smooth*(.13+.06*sin(audio_time*.55))
		if actor and actor.visual_reeling:
			var click_age := fmod(audio_time,.115)
			sample_value += sin(click_age*TAU*1750)*exp(-click_age*260)*.065
		if fishing and fishing.state == "fight" and fishing.tension > .55:
			sample_value += sin(audio_time*TAU*(115+18*sin(audio_time*11))) * (fishing.tension-.55)*.085
		# Quiet wind, water and a soft two-note distant gull, all synthesized.
		var gull:=fmod(audio_time,17.0)
		if gull<.5:sample_value+=sin(audio_time*TAU*(950+120*sin(gull*9)))*sin(gull*PI*2)*.018
		for sound in sounds:
			var age:float=audio_time-sound.start
			var frequency:=540.0
			match sound.kind:
				"cast":sample_value+=n*exp(-age*12)*.2;continue
				"strike","hook":frequency=880
				"land":frequency=[523.25,659.25,783.99][mini(2,int(age*5))]
				"escape":frequency=220-age*90
				"surge":frequency=180
				"dock":frequency=330
			sample_value+=sin(age*frequency*TAU)*exp(-age*(3 if sound.kind=="land" else 10))*.13
		playback.push_frame(Vector2(sample_value,sample_value))
	sounds=sounds.filter(func(s:Dictionary)->bool:return audio_time-s.start<1.1)

func _exit_tree() -> void:
	if audio: audio.stop()
	playback = null
	fishing = null

func _fit_modal() -> void:
	if not modal: return
	await get_tree().process_frame
	var height := modal_box.get_combined_minimum_size().y + 32.0
	modal_panel.size=Vector2(750,height)
	modal_panel.position.y=minf(100,maxf(24,(900-height)*.5))
