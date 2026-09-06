extends RefCounted
class_name LastCastFishing

## Deterministic fishing: cast placement, deliberate lure rhythm, timed hook,
## then readable fish phases. No unseen rolls decide a strike or an escape.
signal landed(fish: Dictionary)
signal escaped(reason: String)
signal cue(kind: String)

var focus_assist: bool = false
var state: String = "idle"
var title: String = "Read the water"
var instruction: String = "Choose a fishing spot."
var progress: float = 0.0
var tension: float = 0.0
var target_dir: float = 0.0
var fish_dir: float = 0.0
var phase_label: String = ""
var hook_remaining: float = 0.0
var fish: Dictionary = {}
var cast_quality: float = 0.0
## Signature landing requires two observable responses, even with strong gear.
var clean_dashes: int = 0
var required_clean_dashes: int = 0
var dash_read_progress: float = 0.0

var _clock: float = 0.0
var _fight_clock: float = 0.0
var _season: int = 0
var _presentation: int = 0
var _bonuses: Dictionary = {}
var _last_phase: String = ""
var _hook_window: float = 0.0
var _last_reel: bool = false
var _rest_time: float = 0.0
var _lure_cycle: int = -1
var _pulse_charge: float = 0.0
var _pulse_rest: float = 0.0
var _pulse_banked: bool = false
var _dash_read_time: float = 0.0
var _dash_counted: bool = false

static func preview(region: int, season: int, spot: int, tackle: int, presentation: int) -> Dictionary:
	var r: int = clampi(region, 0, 2)
	var s: int = clampi(season, 0, 2)
	var offshore: bool = spot == 2
	var recipes: Array[Vector2i] = [Vector2i(1, 1), Vector2i(0, 0), Vector2i(2, 2)]
	var recipe: Vector2i = recipes[r]
	var matching: bool = tackle == recipe.x and presentation == recipe.y
	var signature: bool = spot > 0 and matching
	var names: Array[String] = ["Sunscale Mullet", "Moonpetal Koi", "Stormglass Sailfish"]
	var shore_populations: Array = [
		["Harbor Bream", "Red Mullet", "Rock Whiting"],
		["Ribbon Perch", "Reed Carp", "Frost Char"],
		["Silver Pollock", "Amberjack", "Winter Cod"],
	]
	var boat_populations: Array = [
		["Coral Snapper", "Sea Bass", "Coldwater Hake"],
		["Lagoon Trevally", "Mangrove Snapper", "Silver Drum"],
		["Bluewater Tuna", "Albacore", "Winter Halibut"],
	]
	var season_name: String = ["Summer", "Autumn", "Winter"][s]
	var behaviors: Array[String] = ["Weaves left and right, then makes a long dash.", "Changes direction after a feint. Watch the actual pull.", "Two short runs follow every warning. Rest through both."]
	var recipes_text: Array[String] = ["Spinner + Twitch", "Float + Drift", "Jig + Deep"]
	var fish_name: String = names[r] if signature else str(boat_populations[r][s] if offshore else shore_populations[r][s])
	var common_behavior: String = "Steady pulls and one clearly warned dash."
	if s > 0:
		common_behavior = "More frequent dashes and shorter calm spells. Every dash gives a full warning."
	if offshore:
		common_behavior += " Offshore fish sustain each dash a little longer."
	var hint: String
	if signature:
		hint = season_name + " signature water • " + recipes_text[r] + ". " + behaviors[r] + " Release + counter-steer two dashes to land."
	elif spot > 0:
		hint = season_name + " quarry: " + fish_name + ". For " + names[r] + ", choose " + recipes_text[r] + "."
	else:
		hint = season_name + " quarry: " + fish_name + ". Any setup works; reel in calm water, release during a dash."
	if s > 0 and not signature:
		hint += " Expect more frequent seasonal dashes."
	var base_value: int = (70 + r * 60) if signature else (40 + r * 20 if spot == 2 else 24 + r * 12)
	var base_weight: int = (3 + r) if signature else (2 if spot == 2 else 1)
	return {
		"id": "signature_%d" % r if signature else "common_%d_%d_%d" % [r, 1 if offshore else 0, s],
		"name": fish_name,
		"value": roundi(float(base_value) * (1.0 + 0.30 * float(s))),
		"weight": base_weight,
		"signature": signature,
		"region": r,
		"season": s,
		"offshore": offshore,
		"behavior": behaviors[r] if signature else common_behavior,
		"hint": hint,
		"desired_tackle": recipe.x,
		"desired_presentation": recipe.y,
		"required_clean_dashes": 2 if signature else 0,
	}

func begin(region: int, season: int, spot: int, tackle: int, presentation: int, bonuses: Dictionary) -> void:
	fish = preview(region, season, spot, tackle, presentation)
	_season = clampi(season, 0, 2)
	_presentation = clampi(presentation, 0, 2)
	_bonuses = bonuses.duplicate()
	_clock = 0.0
	_fight_clock = 0.0
	_rest_time = 0.0
	_lure_cycle = -1
	_pulse_charge = 0.0
	_pulse_rest = 0.0
	_pulse_banked = false
	clean_dashes = 0
	required_clean_dashes = int(fish["required_clean_dashes"])
	dash_read_progress = 0.0
	_dash_read_time = 0.0
	_dash_counted = false
	_last_phase = ""
	_last_reel = false
	progress = 0.0
	tension = 0.16
	target_dir = 0.0
	fish_dir = 0.0
	cast_quality = 0.0
	hook_remaining = 0.0
	state = "casting"
	title = "Cast toward " + str(fish["name"])
	phase_label = "Place your cast"
	instruction = "SPACE when the cast meter is 55–80%. Every cast is fishable."
	cue.emit("cast")

func update(dt: float, reel: bool, steer: float) -> void:
	if state == "idle":
		return
	# Advance normalized phase time instead of rescaling elapsed time. Changing
	# Focus in the pause menu must never jump the lure into another pulse.
	var presentation_scale: float = 0.25 if state == "presentation" and focus_assist and bool(fish["signature"]) else 1.0
	_clock += dt * presentation_scale
	match state:
		"casting":
			progress = pingpong(_clock * 0.66, 1.0)
		"presentation":
			_update_presentation(dt, reel)
		"hook":
			hook_remaining = maxf(0.0, hook_remaining - dt)
			progress = hook_remaining / _hook_window
			if hook_remaining <= 0.0:
				_escape("The strike passed. Press SPACE once when STRIKE appears; only this bait was lost.")
		"fight":
			_update_fight(dt, reel, clampf(steer, -1.0, 1.0))
	_last_reel = reel

func press() -> void:
	if state == "casting":
		# A missed sweet spot changes presentation time, never catch eligibility.
		cast_quality = 1.0 if progress >= 0.55 and progress <= 0.80 else 0.45
		state = "presentation"
		_clock = 0.0
		progress = 0.12 if cast_quality == 1.0 else 0.0
		phase_label = "Perfect cast" if cast_quality == 1.0 else "Cast placed"
		title = "Present the lure"
		instruction = "HOLD SPACE on LURE; RELEASE on REST. Follow the water's rhythm."
		cue.emit("splash")
	elif state == "hook":
		state = "fight"
		_clock = 0.0
		_fight_clock = 0.0
		progress = 0.07
		tension = 0.20
		title = str(fish["name"]) + " • on the line!"
		phase_label = "CALM • reel steadily"
		instruction = "HOLD SPACE to reel. Follow the counter-steer arrow with A / D. Release on DASH."
		cue.emit("hook")

func cancel() -> void:
	state = "idle"
	progress = 0.0
	tension = 0.0
	target_dir = 0.0
	fish_dir = 0.0
	hook_remaining = 0.0
	phase_label = ""
	instruction = "Choose a fishing spot."

func _update_presentation(dt: float, reel: bool) -> void:
	# Drift, twitch and deep all use the same two controls, with different cadence.
	var cycle: float = [1.50, 0.95, 1.90][_presentation]
	var active_fraction: float = [0.68, 0.53, 0.72][_presentation]
	var active: bool = fmod(_clock, cycle) < cycle * active_fraction
	phase_label = "LURE • hold SPACE" if active else "REST • release SPACE"
	instruction = "Let the lure move, then settle. A strike follows a few good pulses."
	if bool(fish["signature"]):
		instruction = "This fish reads your rhythm: HOLD on LURE, RELEASE on REST. Three settled pulses earn a strike."
		var current_cycle: int = int(_clock / cycle)
		if current_cycle != _lure_cycle:
			_lure_cycle = current_cycle
			_pulse_charge = 0.0
			_pulse_rest = 0.0
			_pulse_banked = false
		if active and reel:
			_pulse_charge = minf(0.34, _pulse_charge + dt * 0.9)
		elif not active and not reel and not _pulse_banked:
			_pulse_rest += dt
			if _pulse_rest >= 0.10:
				progress += _pulse_charge
				_pulse_banked = true
		elif not active and reel:
			_pulse_rest = 0.0
	else:
		if active and reel:
			progress += dt * 0.43
		elif not active and reel:
			progress = maxf(0.0, progress - dt * 0.10)
	if progress >= 1.0:
		state = "hook"
		_hook_window = (0.95 if bool(fish["signature"]) else 1.45) - float(_season) * 0.075 + float(_bonuses.get("hook", 0.0))
		if focus_assist: _hook_window += 0.6
		hook_remaining = _hook_window
		progress = 1.0
		title = "STRIKE!"
		phase_label = "Tap SPACE now"
		instruction = "Release, then press SPACE once to set the hook."
		cue.emit("strike")

func _update_fight(dt: float, reel: bool, steer: float) -> void:
	var signature: bool = bool(fish["signature"])
	# Keep the current dash and its read credit continuous when pace changes.
	_fight_clock += dt * (0.5 if focus_assist and signature else 1.0)
	var region: int = int(fish["region"])
	var phase: String = "calm"
	var direction: float = -1.0
	var offshore: bool = bool(fish.get("offshore", false))
	var cycle_length: float = 6.8 if signature else 7.0 - float(_season) * 0.35 + (0.2 if offshore else 0.0)
	var read_clock: float = _fight_clock
	var cycle_index: int = int(read_clock / cycle_length)
	var clock_in_cycle: float = fmod(read_clock, cycle_length)
	direction = -1.0 if cycle_index % 2 == 0 else 1.0
	if signature:
		match region:
			0:
				# A readable weave tests steering before the single long dash.
				if clock_in_cycle >= 1.7 and clock_in_cycle < 3.4:
					direction *= -1.0
				if clock_in_cycle >= 3.5 and clock_in_cycle < 4.6:
					phase = "warning"
				elif clock_in_cycle >= 4.6 and clock_in_cycle < 6.2:
					phase = "surge"
			1:
				# Koi feints are announced a full second before changing its pull.
				if clock_in_cycle >= 3.0 and clock_in_cycle < 4.0:
					phase = "feint"
				elif clock_in_cycle >= 4.0:
					direction *= -1.0
					phase = "surge" if clock_in_cycle < 5.5 else "calm"
			2:
				if clock_in_cycle >= 2.9 and clock_in_cycle < 4.0:
					phase = "warning"
				elif (clock_in_cycle >= 4.0 and clock_in_cycle < 4.9) or (clock_in_cycle >= 5.25 and clock_in_cycle < 6.15):
					phase = "surge"
				elif clock_in_cycle >= 4.9 and clock_in_cycle < 5.25:
					phase = "second"
	else:
		# Seasonal populations rest less; offshore quarry holds its run longer.
		# The 1.1-second warning remains identical so every change is readable.
		var warning_start: float = 4.3 - float(_season) * 0.48 - (0.2 if offshore else 0.0)
		var dash_start: float = warning_start + 1.1
		var dash_end: float = dash_start + 1.2 + float(_season) * 0.12 + (0.2 if offshore else 0.0)
		if clock_in_cycle >= warning_start and clock_in_cycle < dash_start:
			phase = "warning"
		elif clock_in_cycle >= dash_start and clock_in_cycle < dash_end:
			phase = "surge"

	fish_dir = direction
	target_dir = -direction
	var steering_well: bool = steer * target_dir > 0.40
	var steering_wrong: bool = steer * target_dir < -0.40
	var key: String = "A ←" if target_dir < 0.0 else "D →"
	var control: float = clampf(1.0 - float(_bonuses.get("control", 0.0)), 0.35, 1.0)
	var power: float = 1.0 + float(_bonuses.get("power", 0.0))
	var difficulty: float = 1.0 + float(_season) * 0.16
	var surge: bool = phase == "surge"
	if phase != _last_phase:
		if surge:
			_dash_read_time = 0.0
			_dash_counted = false
			dash_read_progress = 0.0
			cue.emit("surge")
		elif phase == "warning" or phase == "feint":
			cue.emit("warning")
		_last_phase = phase
	if signature and surge and not _dash_counted:
		# This visible requirement cannot be bought away by tension upgrades.
		# A brief lapse is recoverable inside the same dash; each dash counts once.
		var read_duration: float = 0.40 + float(_season) * 0.05
		if not reel and steering_well:
			_dash_read_time += dt
		else:
			_dash_read_time = maxf(0.0, _dash_read_time - dt * 0.5)
		dash_read_progress = clampf(_dash_read_time / read_duration, 0.0, 1.0)
		if _dash_read_time >= read_duration:
			_dash_counted = true
			clean_dashes = mini(required_clean_dashes, clean_dashes + 1)
			cue.emit("tick")
	match phase:
		"warning":
			phase_label = "DASH COMING • get ready to release"
		"feint":
			phase_label = "FEINT • direction flips in a moment"
		"surge":
			phase_label = "DASH • RELEASE SPACE"
		"second":
			phase_label = "SECOND DASH COMING • keep resting"
		_:
			phase_label = "CALM • HOLD SPACE to reel"
	var rest_cue: bool = surge or phase == "second"
	instruction = "Counter-steer " + key + ". " + ("Let it run; release SPACE to cool the line." if rest_cue else "Hold SPACE to gain ground. Rest if the line turns red.")
	if signature:
		instruction += "\nDashes read %d / %d: release SPACE + hold the counter arrow during DASH." % [clean_dashes, required_clean_dashes]
	if reel:
		_rest_time = 0.0
		if surge:
			var dash_pressure: float = 0.33 if signature else 0.24
			dash_pressure *= clampf(1.0 - float(_bonuses.get("calm", 0.0)), 0.35, 1.0)
			tension += dt * dash_pressure * control * difficulty * (0.68 if steering_well else 1.0)
			progress += dt * 0.012 * power if steering_well else 0.0
		else:
			# Commons land in about 16–22 seconds; signatures ask for 25–35.
			var gain: float = (0.051 if signature else 0.074) * power
			gain *= 1.0 if steering_well else (0.48 if steering_wrong else 0.78)
			gain /= 1.0 + float(_season) * 0.075
			progress += dt * gain
			tension += dt * (0.034 if signature else 0.016) * control * difficulty
			if steering_well:
				tension -= dt * 0.038
			elif steering_wrong:
				tension += dt * 0.070 * control
	else:
		_rest_time += dt
		tension -= dt * (0.24 if steering_well else 0.18)
		# Resting is always safe. Long rests surrender a little ground, visibly,
		# without an invisible timeout or loss of the fish.
		if _rest_time > 3.0:
			progress = maxf(0.03, progress - dt * 0.012)
	tension = clampf(tension, 0.0, 1.0)
	progress = clampf(progress, 0.0, 1.0)
	if signature and clean_dashes < required_clean_dashes and progress >= 0.92:
		progress = 0.92
		instruction = "Almost landed! Read %d more dash%s: RELEASE SPACE + hold %s during DASH.\nThe next warning gives you another chance." % [required_clean_dashes - clean_dashes, "" if required_clean_dashes - clean_dashes == 1 else "es", key]
	if tension >= 1.0:
		_escape("The line broke at full tension. Release SPACE during DASH; counter-steer the arrow. Only this bait was lost.")
	elif progress >= 1.0:
		state = "idle"
		fish["clean_dashes"] = clean_dashes
		title = "Landed " + str(fish["name"]) + "!"
		phase_label = "Catch secured"
		instruction = "Return to the buyer to bank it, or keep fishing."
		cue.emit("land")
		landed.emit(fish.duplicate())

func _escape(reason: String) -> void:
	state = "idle"
	title = "The fish got away"
	phase_label = "Try another cast"
	instruction = reason
	cue.emit("escape")
	escaped.emit(reason)
