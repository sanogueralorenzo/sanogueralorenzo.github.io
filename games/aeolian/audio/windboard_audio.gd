class_name WindboardAudio
extends Node

const MIX_RATE := 22050
const LOOP_SECONDS := 0.75

@onready var controller := get_parent() as WindboardController
@onready var wind_loop: AudioStreamPlayer = %WindLoop
@onready var surface_loop: AudioStreamPlayer = %SurfaceLoop
@onready var impact_player: AudioStreamPlayer = %ImpactPlayer


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	wind_loop.stream = _make_periodic_loop(24, 7, 0.34, 72391)
	surface_loop.stream = _make_periodic_loop(78, 11, 0.28, 42017)
	impact_player.stream = _make_impact(0.22, 0.58, 99173)
	wind_loop.play()
	surface_loop.play()
	if controller != null:
		controller.landed.connect(_on_landed)
		controller.crashed.connect(_on_crashed)


func _process(_delta: float) -> void:
	if controller == null:
		return
	var speed := controller.motion_model.velocity.length()
	var speed_ratio := clampf(speed / 36.0, 0.0, 1.0)
	var supported := controller.motion_state == WindboardController.MotionState.GROUNDED \
		or controller.motion_state == WindboardController.MotionState.COYOTE
	wind_loop.volume_db = lerpf(-42.0, -12.0, speed_ratio)
	wind_loop.pitch_scale = lerpf(0.72, 1.38, speed_ratio)
	surface_loop.volume_db = lerpf(-46.0, -17.0, speed_ratio) if supported else -60.0
	surface_loop.pitch_scale = lerpf(0.82, 1.32, speed_ratio)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	for player: AudioStreamPlayer in [wind_loop, surface_loop, impact_player]:
		if player != null:
			player.stop()
			player.stream = null


func _make_periodic_loop(
		base_cycles: int,
		component_count: int,
		amplitude: float,
		seed: int
	) -> AudioStreamWAV:
	var frame_count := int(MIX_RATE * LOOP_SECONDS)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var phases: Array[float] = []
	for component in component_count:
		phases.append(rng.randf_range(0.0, TAU))
	for frame in frame_count:
		var progress := float(frame) / float(frame_count)
		var sample := 0.0
		for component in component_count:
			var cycles := base_cycles + component * component + component * 3
			var weight := 1.0 / (1.0 + float(component) * 0.32)
			sample += sin(TAU * float(cycles) * progress + phases[component]) * weight
		sample *= amplitude / float(component_count)
		data.encode_s16(frame * 2, clampi(roundi(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	return stream


func _make_impact(duration: float, amplitude: float, seed: int) -> AudioStreamWAV:
	var frame_count := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for frame in frame_count:
		var progress := float(frame) / float(frame_count)
		var envelope := pow(1.0 - progress, 2.4)
		var body := sin(TAU * 92.0 * float(frame) / float(MIX_RATE)) * 0.38
		var noise := rng.randf_range(-1.0, 1.0) * 0.62
		var sample := (body + noise) * envelope * amplitude
		data.encode_s16(frame * 2, clampi(roundi(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream


func _on_landed(result: Dictionary) -> void:
	var impact_speed := float(result.get("impact_speed_mps", 0.0))
	if impact_speed < 2.0:
		return
	impact_player.volume_db = lerpf(-30.0, -7.0, clampf(impact_speed / 16.0, 0.0, 1.0))
	impact_player.pitch_scale = lerpf(1.18, 0.78, clampf(impact_speed / 20.0, 0.0, 1.0))
	impact_player.play()


func _on_crashed(_cause: StringName, _details: Dictionary) -> void:
	impact_player.volume_db = -5.0
	impact_player.pitch_scale = 0.68
	impact_player.play()
