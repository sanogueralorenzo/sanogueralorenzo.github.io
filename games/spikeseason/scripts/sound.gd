extends Node
## Small synthesized instruments; no external samples or dependencies.
var muted := false
var ambience: AudioStreamPlayer
var beat := 0.0
var note_index := 0
var music_enabled := true
var venue:=0
var atmosphere:=0
var ambience_key:=-1

func _ready() -> void:
	ambience = AudioStreamPlayer.new()
	add_child(ambience)
	set_atmosphere(0,0)

func set_atmosphere(map_index:int,variant:int) -> void:
	venue=map_index
	atmosphere=variant
	if ambience_key==map_index*3+variant: return
	ambience_key=map_index*3+variant
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 8 * 2)
	var smooth := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 281
	for i in range(22050 * 8):
		var t := float(i) / 22050.0
		smooth = lerpf(smooth, rng.randf_range(-1, 1), 0.09)
		var v := smooth * (0.06 + 0.045 * sin(t * TAU / 8.0))
		if venue==1:
			# Water against the quay and a soft distant mooring bell.
			v*=.83
			var strike:=fmod(t+float(variant)*.7,4.0)
			v+=(sin(t*TAU*587.33)+sin(t*TAU*953.2)*.25)*exp(-strike*3.3)*.010
		elif venue==2:
			# Filtered leaf rustle and two quiet birds, clear of the contact register.
			v*=.62+float(variant==1)*.38
			var chirp:=fmod(t,2.0)
			if chirp<.24: v+=sin(TAU*(1800*t+90*sin(chirp*18)))*sin(chirp/.24*PI)*.007
		v*=sin(minf(t*30,PI/2))*sin(minf((8-t)*30,PI/2))
		bytes.encode_s16(i * 2, int(v * 32767))
	wave.data = bytes
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_end = 22050 * 8
	ambience.stream = wave
	ambience.play()

func _process(delta: float) -> void:
	beat -= delta
	if beat <= 0 and music_enabled and not muted:
		beat = [.36,.40,.43][venue]
		var notes := [220.0, 0.0, 329.63, 440.0, 0.0, 369.99, 329.63, 0.0, 246.94, 0.0, 369.99, 493.88, 0.0, 440.0, 329.63, 0.0]
		var f: float = notes[note_index % notes.size()]
		note_index += 1
		if f > 0: tone(f * [1.0,.89,1.12][venue], 0.30, 0.025, 0)

func tone(hz: float, duration: float, volume: float = 0.18, kind: int = 0) -> void:
	if muted: return
	var player := AudioStreamPlayer.new()
	add_child(player)
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 22050
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var n := int(duration * 22050)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / 22050.0
		var env := pow(1.0 - float(i) / n, 2.0) * minf(t * 350.0, 1.0)
		var v := sin(TAU * hz * t) * 0.75 + sin(TAU * hz * 2.0 * t) * 0.18
		if kind == 1: v = sin(TAU * (hz * t + 38.0 * (1.0 - exp(-t * 30.0)))) * 0.6 + randf_range(-0.35, 0.35)
		if kind == 2: v = randf_range(-1.0, 1.0) * 0.6 + sin(TAU * hz * t) * 0.3
		data.encode_s16(i * 2, int(clampf(v * env * volume, -1, 1) * 32767))
	wav.data = data
	player.stream = wav
	player.finished.connect(player.queue_free)
	player.play()

func contact(power: float) -> void:
	tone(110.0 + power * 65.0, 0.15, 0.3 + power * 0.1, 1)

func point(won: bool) -> void:
	for i in range(3):
		get_tree().create_timer(float(i) * 0.13).timeout.connect(func(): tone(([523.25, 659.25, 783.99] if won else [329.63, 293.66, 220.0])[i], 0.4, 0.14))

func toggle() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream=null
