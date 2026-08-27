class_name OverrushAudioDirector
extends Node

const SAMPLE_RATE := 22050
const MUSIC_DURATION := 4.0
const EFFECT_POOL_SIZE := 6

const EFFECT_DURATIONS := {
	&"air_boost": 0.28,
	&"jump": 0.18,
	&"landing_clean": 0.28,
	&"landing_solid": 0.22,
	&"landing_rough": 0.3,
}

var master_level := 0.8
var music_level := 0.55
var effects_level := 1.0

var _library: Dictionary = {}
var _effect_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _effect_cursor := 0
var _initialized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_players()
	if DisplayServer.get_name() == "headless":
		return
	_library = build_sound_library()
	_music_player.stream = _library.music
	_initialized = true
	_apply_levels()
	_music_player.play()


func set_levels(new_master_level: float, new_music_level: float, new_effects_level: float = 1.0) -> void:
	master_level = clampf(new_master_level, 0.0, 1.0)
	music_level = clampf(new_music_level, 0.0, 1.0)
	effects_level = clampf(new_effects_level, 0.0, 1.0)
	_apply_levels()


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


func build_sound_library() -> Dictionary:
	var library := {"music": _create_music()}
	for effect_id in EFFECT_DURATIONS:
		library[effect_id] = _create_effect(effect_id, float(EFFECT_DURATIONS[effect_id]))
	return library


func _create_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
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
