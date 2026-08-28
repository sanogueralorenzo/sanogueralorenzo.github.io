class_name OverrushAudioDirector
extends Node

const SAMPLE_RATE := 22050
const MUSIC_DURATION := 4.0
const MOTION_LOOP_DURATION := 2.0
const EFFECT_POOL_SIZE := 6
const MOTION_LOOP_IDS: Array[StringName] = [&"wind", &"sand_surface", &"grass_surface"]

const EFFECT_DURATIONS := {
	&"air_boost": 0.28,
	&"jump": 0.18,
	&"landing_clean": 0.28,
	&"landing_solid": 0.22,
	&"landing_rough": 0.3,
	&"obstacle_impact": 0.42,
}

var master_level := 0.8
var music_level := 0.55
var effects_level := 1.0

var _library: Dictionary = {}
var _effect_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _motion_players: Dictionary = {}
var _effect_cursor := 0
var _initialized := false
var _motion_speed_ratio := 0.0
var _motion_grass_weight := 0.0
var _motion_grounded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_players()
	if DisplayServer.get_name() == "headless":
		return
	_library = build_sound_library()
	_music_player.stream = _library.music
	for loop_id in MOTION_LOOP_IDS:
		var motion_player := _motion_players[loop_id] as AudioStreamPlayer
		motion_player.stream = _library[loop_id]
		motion_player.play()
	_initialized = true
	_apply_levels()
	_music_player.play()


func set_levels(new_master_level: float, new_music_level: float, new_effects_level: float = 1.0) -> void:
	master_level = clampf(new_master_level, 0.0, 1.0)
	music_level = clampf(new_music_level, 0.0, 1.0)
	effects_level = clampf(new_effects_level, 0.0, 1.0)
	_apply_levels()


func set_motion_state(speed_ratio: float, grass_weight: float, grounded: bool) -> void:
	_motion_speed_ratio = clampf(speed_ratio, 0.0, 1.2)
	_motion_grass_weight = clampf(grass_weight, 0.0, 1.0)
	_motion_grounded = grounded
	_apply_motion_levels()


func calculate_motion_mix(speed_ratio: float, grass_weight: float, grounded: bool) -> Dictionary:
	var speed := clampf(speed_ratio, 0.0, 1.2)
	var grass := clampf(grass_weight, 0.0, 1.0)
	var wind_level := smoothstep(0.06, 1.0, speed)
	var surface_level := smoothstep(0.08, 0.88, speed) if grounded else 0.0
	return {
		&"wind": wind_level * 0.68,
		&"sand_surface": surface_level * pow(1.0 - grass, 0.72) * 0.76,
		&"grass_surface": surface_level * pow(grass, 0.72) * 0.72,
		&"pitch": lerpf(0.76, 1.32, clampf(speed, 0.0, 1.0)),
	}


func play_air_boost() -> void:
	_play_effect(&"air_boost", -2.0, 1.0)


func play_jump() -> void:
	_play_effect(&"jump", -5.0, 1.0)


func play_landing(rating: StringName) -> void:
	match rating:
		SandboardMotion.LANDING_CLEAN:
			_play_effect(&"landing_clean", -3.0, 1.0)
		SandboardMotion.LANDING_SOLID:
			_play_effect(&"landing_solid", -4.0, 1.0)
		_:
			_play_effect(&"landing_rough", -2.0, 1.0)


func play_obstacle_impact(impact_speed: float) -> void:
	var impact_ratio := clampf(impact_speed / 60.0, 0.0, 1.0)
	_play_effect(&"obstacle_impact", lerpf(-2.0, -0.5, impact_ratio), lerpf(0.78, 0.96, impact_ratio))


func build_sound_library() -> Dictionary:
	var library := {"music": _create_music()}
	for loop_id in MOTION_LOOP_IDS:
		library[loop_id] = _create_motion_loop(loop_id)
	for effect_id in EFFECT_DURATIONS:
		library[effect_id] = _create_effect(effect_id, float(EFFECT_DURATIONS[effect_id]))
	return library


func _create_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	for loop_id in MOTION_LOOP_IDS:
		var motion_player := AudioStreamPlayer.new()
		motion_player.process_mode = Node.PROCESS_MODE_ALWAYS
		motion_player.volume_db = -80.0
		add_child(motion_player)
		_motion_players[loop_id] = motion_player
	for _index in range(EFFECT_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.set_meta(&"volume_offset_db", 0.0)
		add_child(player)
		_effect_players.append(player)


func _play_effect(effect_id: StringName, volume_offset_db: float, pitch: float) -> void:
	if not _initialized or master_level * effects_level <= 0.0 or not _library.has(effect_id):
		return
	var player := _effect_players[_effect_cursor]
	_effect_cursor = (_effect_cursor + 1) % _effect_players.size()
	player.stop()
	player.stream = _library[effect_id]
	player.set_meta(&"volume_offset_db", volume_offset_db)
	_apply_effect_level(player)
	player.pitch_scale = clampf(pitch, 0.5, 1.8)
	player.play()


func _apply_levels() -> void:
	if not is_instance_valid(_music_player):
		return
	_music_player.volume_db = _linear_level_to_db(master_level * music_level) - 9.0
	for player in _effect_players:
		_apply_effect_level(player)
	_apply_motion_levels()


func _apply_motion_levels() -> void:
	if _motion_players.is_empty():
		return
	var mix := calculate_motion_mix(_motion_speed_ratio, _motion_grass_weight, _motion_grounded)
	for loop_id in MOTION_LOOP_IDS:
		var player := _motion_players[loop_id] as AudioStreamPlayer
		player.volume_db = _linear_level_to_db(master_level * effects_level * float(mix[loop_id]))
		player.pitch_scale = float(mix.pitch)


func _apply_effect_level(player: AudioStreamPlayer) -> void:
	var volume_offset_db := float(player.get_meta(&"volume_offset_db", 0.0))
	player.volume_db = _linear_level_to_db(master_level * effects_level) + volume_offset_db


func _linear_level_to_db(level: float) -> float:
	return -80.0 if level <= 0.0001 else linear_to_db(level)


func _create_music() -> AudioStreamWAV:
	var frame_count := roundi(MUSIC_DURATION * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var slow_wave := sin(TAU * 0.25 * time)
		var chord := (
			sin(TAU * 55.0 * time) * 0.34
			+ sin(TAU * 73.5 * time + 0.7) * 0.22
			+ sin(TAU * 82.5 * time + 1.6) * 0.2
			+ sin(TAU * 110.0 * time + slow_wave * 0.18) * 0.12
		)
		var air := sin(TAU * 440.0 * time + sin(TAU * 0.5 * time) * 1.2) * 0.025
		var left := (chord + air) * (0.92 + slow_wave * 0.04)
		var right := (chord - air) * (0.92 - slow_wave * 0.04)
		_encode_stereo_frame(data, frame, left, right)
	return _make_stream(data, frame_count, true)


func _create_motion_loop(loop_id: StringName) -> AudioStreamWAV:
	var frame_count := roundi(MOTION_LOOP_DURATION * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var left := _sample_motion_loop(loop_id, time, false)
		var right := _sample_motion_loop(loop_id, time, true)
		_encode_stereo_frame(data, frame, left, right)
	return _make_stream(data, frame_count, true)


func _sample_motion_loop(loop_id: StringName, time: float, right_channel: bool) -> float:
	var channel_phase := 0.63 if right_channel else 0.0
	match loop_id:
		&"wind":
			var slow := sin(TAU * 0.5 * time + channel_phase)
			return (
				sin(TAU * 31.5 * time + slow * 1.7 + channel_phase) * 0.12
				+ sin(TAU * 53.0 * time + channel_phase * 1.4) * 0.075
				+ sin(TAU * 87.5 * time + slow * 0.8) * 0.045
			)
		&"sand_surface":
			var grain := sin(TAU * 6.0 * time + channel_phase) * 0.5 + 0.5
			return (
				sin(TAU * 421.0 * time + channel_phase) * 0.09
				+ sin(TAU * 733.5 * time + channel_phase * 1.6) * 0.06
				+ sin(TAU * 1091.0 * time) * 0.035
			) * (0.42 + grain * 0.58)
		&"grass_surface":
			var rustle := sin(TAU * 4.5 * time + channel_phase) * 0.5 + 0.5
			return (
				sin(TAU * 127.0 * time + channel_phase) * 0.08
				+ sin(TAU * 191.5 * time + rustle * 1.1) * 0.065
				+ sin(TAU * 317.0 * time + channel_phase * 0.7) * 0.04
			) * (0.35 + rustle * 0.65)
		_:
			return 0.0


func _create_effect(effect_id: StringName, duration: float) -> AudioStreamWAV:
	var frame_count := maxi(1, roundi(duration * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(effect_id) ^ 0x0A11D10
	var filtered_noise := 0.0
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var progress := clampf(time / duration, 0.0, 1.0)
		filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.28)
		var sample := _sample_effect(effect_id, time, progress, filtered_noise)
		var pan := sin(progress * PI) * 0.06
		_encode_stereo_frame(data, frame, sample * (1.0 - pan), sample * (1.0 + pan))
	return _make_stream(data, frame_count, false)


func _sample_effect(effect_id: StringName, time: float, progress: float, noise: float) -> float:
	match effect_id:
		&"air_boost":
			var phase := 120.0 * time + 520.0 * time * time
			var envelope := pow(sin(PI * progress), 0.65) * (1.0 - progress * 0.35)
			return clampf((sin(TAU * phase) * 0.48 + noise * 0.42) * envelope, -0.92, 0.92)
		&"jump":
			return (sin(TAU * (150.0 * time + 390.0 * time * time)) * 0.42 + noise * 0.24) * pow(1.0 - progress, 0.8)
		&"landing_clean":
			return (sin(TAU * 310.0 * time) * 0.38 + sin(TAU * 465.0 * time) * 0.24 + noise * 0.16) * exp(-9.0 * time)
		&"landing_solid":
			return (sin(TAU * 170.0 * time) * 0.4 + noise * 0.3) * exp(-12.0 * time)
		&"landing_rough":
			return (sin(TAU * (105.0 * time - 18.0 * time * time)) * 0.45 + noise * 0.48) * exp(-8.0 * time)
		&"obstacle_impact":
			var thud := sin(TAU * (72.0 * time - 11.0 * time * time)) * 0.42
			var crack := sin(TAU * 235.0 * time + noise * 1.4) * 0.14
			return (thud + crack + noise * 0.32) * exp(-6.2 * time)
		_:
			return 0.0


func _encode_stereo_frame(data: PackedByteArray, frame: int, left: float, right: float) -> void:
	var byte_offset := frame * 4
	data.encode_s16(byte_offset, clampi(roundi(left * 32767.0), -32768, 32767))
	data.encode_s16(byte_offset + 2, clampi(roundi(right * 32767.0), -32768, 32767))


func _make_stream(data: PackedByteArray, frame_count: int, looped: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frame_count
	return stream
