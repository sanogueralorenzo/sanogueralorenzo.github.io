class_name OverrushAudioDirector
extends Node

const SAMPLE_RATE := 22050
const MUSIC_DURATION := 4.0
const EFFECT_POOL_SIZE := 12

const EFFECT_DURATIONS := {
	&"dash": 0.28,
	&"hurt": 0.32,
	&"hit": 0.07,
	&"enemy_defeat": 0.16,
	&"pickup": 0.14,
	&"repair": 0.34,
	&"warning": 0.35,
	&"level_up": 0.75,
	&"phase": 0.8,
	&"victory": 1.6,
	&"defeat": 1.2,
}

var master_level := 0.8
var music_level := 0.55

var _library: Dictionary = {}
var _effect_players: Array[AudioStreamPlayer] = []
var _music_bed: AudioStreamPlayer
var _music_drive: AudioStreamPlayer
var _effect_cursor := 0
var _defeat_sequence := 0
var _pickup_sequence := 0
var _repair_sequence := 0
var _warning_cooldown := 0.0
var _hit_cooldown := 0.0
var _phase_drive_db := -24.0
var _music_duck_db := 0.0
var _initialized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_players()
	if DisplayServer.get_name() == "headless":
		return
	_library = build_sound_library()
	_music_bed.stream = _library.music_bed
	_music_drive.stream = _library.music_drive
	_initialized = true
	_apply_levels()
	_music_bed.play()
	_music_drive.play()


func _process(delta: float) -> void:
	_warning_cooldown = maxf(0.0, _warning_cooldown - delta)
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)


func set_levels(new_master_level: float, new_music_level: float) -> void:
	master_level = clampf(new_master_level, 0.0, 1.0)
	music_level = clampf(new_music_level, 0.0, 1.0)
	_apply_levels()


func set_phase(phase_id: StringName) -> void:
	match phase_id:
		&"pressure":
			_phase_drive_db = -17.0
		&"redline":
			_phase_drive_db = -12.0
		&"overrun":
			_phase_drive_db = -7.0
		&"apex":
			_phase_drive_db = -3.0
		_:
			_phase_drive_db = -24.0
	_apply_levels()


func play_dash(active: bool) -> void:
	if active:
		_play_effect(&"dash", -2.0, 1.0)


func play_hurt(_amount: float = 0.0) -> void:
	_play_effect(&"hurt", 0.0, 1.0)


func play_enemy_hit(is_apex: bool) -> void:
	if _hit_cooldown > 0.0:
		return
	_hit_cooldown = 0.045
	_play_effect(&"hit", -5.0 if is_apex else -9.0, 0.74 if is_apex else 1.0)


func play_enemy_defeat(is_elite: bool, is_apex: bool) -> void:
	if is_apex:
		return
	var pitch_steps: Array[float] = [0.92, 1.0, 1.08, 1.15]
	var pitch := pitch_steps[_defeat_sequence % pitch_steps.size()]
	_defeat_sequence += 1
	_play_effect(&"enemy_defeat", 1.0 if is_elite else -5.0, pitch * (0.82 if is_elite else 1.0))


func play_pickup(value: int) -> void:
	var pitch_steps: Array[float] = [1.0, 1.06, 1.12]
	var pitch := pitch_steps[_pickup_sequence % pitch_steps.size()]
	_pickup_sequence += 1
	_play_effect(&"pickup", -7.0 + minf(float(maxi(value, 1)), 7.0) * 0.35, pitch)


func play_repair(value: float) -> void:
	var pitch_steps: Array[float] = [0.96, 1.04, 1.12]
	var pitch := pitch_steps[_repair_sequence % pitch_steps.size()]
	_repair_sequence += 1
	_play_effect(&"repair", -2.0 + minf(maxf(value, 1.0), 30.0) * 0.04, pitch)


func play_attack_warning(attack_kind: StringName, is_elite: bool, is_apex: bool) -> void:
	if _warning_cooldown > 0.0:
		return
	_warning_cooldown = 0.1
	var pitch := 1.08
	if "pulse" in str(attack_kind):
		pitch = 0.72
	elif attack_kind in [&"rift_blast", &"apex_rift"]:
		pitch = 1.28
	elif attack_kind in [&"foundry_bloom", &"apex_bloom"]:
		pitch = 0.88
	if is_apex:
		pitch *= 0.78
	_play_effect(&"warning", 1.0 if is_elite or is_apex else -3.0, pitch)


func play_level_up() -> void:
	_play_effect(&"level_up", 0.0, 1.0)


func play_phase_event() -> void:
	_play_effect(&"phase", -1.0, 1.0)


func play_victory() -> void:
	_music_duck_db = -8.0
	_apply_levels()
	_play_effect(&"victory", 1.0, 1.0)


func play_defeat() -> void:
	_music_duck_db = -12.0
	_apply_levels()
	_play_effect(&"defeat", 1.0, 1.0)


func build_sound_library() -> Dictionary:
	var library := {
		"music_bed": _create_music_bed(),
		"music_drive": _create_music_drive(),
	}
	for effect_id in EFFECT_DURATIONS:
		library[effect_id] = _create_effect(effect_id, float(EFFECT_DURATIONS[effect_id]))
	return library


func _create_players() -> void:
	_music_bed = AudioStreamPlayer.new()
	_music_bed.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_bed)
	_music_drive = AudioStreamPlayer.new()
	_music_drive.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_drive)
	for _index in range(EFFECT_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_effect_players.append(player)


func _play_effect(effect_id: StringName, volume_offset_db: float, pitch: float) -> void:
	if not _initialized or master_level <= 0.0 or not _library.has(effect_id):
		return
	var player := _effect_players[_effect_cursor]
	_effect_cursor = (_effect_cursor + 1) % _effect_players.size()
	player.stop()
	player.stream = _library[effect_id]
	player.volume_db = _linear_level_to_db(master_level) + volume_offset_db
	player.pitch_scale = clampf(pitch, 0.5, 1.8)
	player.play()


func _apply_levels() -> void:
	if not is_instance_valid(_music_bed) or not is_instance_valid(_music_drive):
		return
	var combined_music := master_level * music_level
	_music_bed.volume_db = _linear_level_to_db(combined_music) - 9.0 + _music_duck_db
	_music_drive.volume_db = _linear_level_to_db(combined_music) + _phase_drive_db + _music_duck_db


func _linear_level_to_db(level: float) -> float:
	return -80.0 if level <= 0.0001 else linear_to_db(level)


func _create_music_bed() -> AudioStreamWAV:
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


func _create_music_drive() -> AudioStreamWAV:
	var frame_count := roundi(MUSIC_DURATION * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	var notes: Array[float] = [55.0, 55.0, 65.4, 73.5, 55.0, 82.5, 73.5, 65.4, 55.0, 49.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4F56455252555348
	var filtered_noise := 0.0
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var beat_index := int(time / 0.4) % notes.size()
		var beat_time := fposmod(time, 0.4)
		var beat_phase := beat_time / 0.4
		var bass_envelope := exp(-4.8 * beat_phase)
		var bass := sin(TAU * notes[beat_index] * beat_time) * bass_envelope * 0.48
		var kick_phase := 78.0 * beat_time - 42.0 * beat_time * beat_time
		var kick := sin(TAU * kick_phase) * exp(-18.0 * beat_time) * 0.62
		var hat_time := fposmod(time, 0.2)
		filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.34)
		var hat := filtered_noise * exp(-38.0 * hat_time) * 0.18
		var pulse := clampf(bass + kick + hat, -0.92, 0.92)
		_encode_stereo_frame(data, frame, pulse * 0.96, pulse)
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
		&"dash":
			var dash_phase := 120.0 * time + 520.0 * time * time
			var dash_envelope := pow(sin(PI * progress), 0.65) * (1.0 - progress * 0.35)
			return clampf((sin(TAU * dash_phase) * 0.48 + noise * 0.42) * dash_envelope, -0.92, 0.92)
		&"hurt":
			return clampf((sin(TAU * (92.0 * time - 28.0 * time * time)) * 0.7 + noise * 0.3) * exp(-8.0 * time), -0.92, 0.92)
		&"hit":
			return (sin(TAU * 285.0 * time) * 0.55 + noise * 0.32) * exp(-42.0 * time)
		&"enemy_defeat":
			return sin(TAU * (410.0 * time - 620.0 * time * time)) * exp(-17.0 * time) * 0.78
		&"pickup":
			return (sin(TAU * 660.0 * time) * 0.52 + sin(TAU * 990.0 * time) * 0.28) * exp(-14.0 * time)
		&"repair":
			return _sample_arpeggio(time, progress, [329.6, 493.9, 659.3], 0.105, 0.68)
		&"warning":
			var warning_pulse := 0.5 + 0.5 * sin(TAU * 9.0 * time)
			return (sin(TAU * 118.0 * time) * 0.62 + sin(TAU * 236.0 * time) * 0.18) * warning_pulse * (1.0 - progress * 0.25)
		&"level_up":
			return _sample_arpeggio(time, progress, [440.0, 554.4, 659.3, 880.0], 0.15, 0.72)
		&"phase":
			return _sample_arpeggio(time, progress, [110.0, 164.8, 220.0, 329.6], 0.18, 0.68) + sin(TAU * 55.0 * time) * exp(-3.0 * time) * 0.2
		&"victory":
			return _sample_arpeggio(time, progress, [220.0, 277.2, 329.6, 440.0, 554.4, 659.3], 0.22, 0.78)
		&"defeat":
			var fall_phase := 180.0 * time - 58.0 * time * time
			return (sin(TAU * fall_phase) * 0.65 + noise * 0.18) * pow(1.0 - progress, 1.4)
		_:
			return 0.0


func _sample_arpeggio(time: float, progress: float, notes: Array, step_duration: float, level: float) -> float:
	var note_index := mini(int(time / step_duration), notes.size() - 1)
	var note_time := fposmod(time, step_duration)
	var envelope := exp(-5.0 * note_time / step_duration) * pow(1.0 - progress, 0.25)
	var frequency := float(notes[note_index])
	return (sin(TAU * frequency * note_time) * 0.72 + sin(TAU * frequency * 2.0 * note_time) * 0.18) * envelope * level


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
