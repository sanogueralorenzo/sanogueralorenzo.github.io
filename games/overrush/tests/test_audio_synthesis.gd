extends SceneTree

const AudioDirectorModel = preload("res://scripts/audio_director.gd")

var _failures: Array[String] = []


func _init() -> void:
	var audio: OverrushAudioDirector = AudioDirectorModel.new()
	var started_at := Time.get_ticks_usec()
	var library := audio.build_sound_library()
	var build_milliseconds := float(Time.get_ticks_usec() - started_at) / 1000.0
	_validate_library(library)
	_expect(build_milliseconds < 1500.0, "The complete procedural audio palette should synthesize in under 1.5 seconds, measured %.2f ms." % build_milliseconds)
	library.clear()
	audio.free()
	if _failures.is_empty():
		print("Audio synthesis validation passed — one ambient layer and 5 freeride effects built in %.2f ms." % build_milliseconds)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _validate_library(library: Dictionary) -> void:
	var expected_effects: Array[StringName] = [
		&"air_boost",
		&"jump",
		&"landing_clean",
		&"landing_solid",
		&"landing_rough",
	]
	_expect(library.size() == expected_effects.size() + 1, "The sound library should contain only the ambient bed and core movement feedback.")
	_expect(library.has(&"music"), "Missing synthesized ambient music layer.")
	if library.has(&"music"):
		_validate_stream(library.music as AudioStreamWAV, AudioDirectorModel.MUSIC_DURATION, true, "music")
	for effect_id in expected_effects:
		_expect(library.has(effect_id), "Missing synthesized feedback cue %s." % effect_id)
		if not library.has(effect_id):
			continue
		var stream := library[effect_id] as AudioStreamWAV
		_validate_stream(stream, float(AudioDirectorModel.EFFECT_DURATIONS[effect_id]), false, str(effect_id))


func _validate_stream(stream: AudioStreamWAV, expected_duration: float, looped: bool, stream_name: String) -> void:
	_expect(stream != null, "%s should be an AudioStreamWAV." % stream_name)
	if stream == null:
		return
	_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.stereo, "%s should use reusable stereo 16-bit PCM." % stream_name)
	_expect(stream.mix_rate == AudioDirectorModel.SAMPLE_RATE, "%s should use the shared synthesis sample rate." % stream_name)
	var expected_bytes := roundi(expected_duration * AudioDirectorModel.SAMPLE_RATE) * 4
	_expect(abs(stream.data.size() - expected_bytes) <= 4, "%s should have its authored duration." % stream_name)
	_expect((stream.loop_mode != AudioStreamWAV.LOOP_DISABLED) == looped, "%s loop behavior should match its role." % stream_name)
	var peak := 0
	var clipped_samples := 0
	for byte_offset in range(0, stream.data.size() - 1, 2):
		var magnitude := absi(stream.data.decode_s16(byte_offset))
		peak = maxi(peak, magnitude)
		if magnitude >= 32767:
			clipped_samples += 1
	_expect(peak > 900, "%s should contain a clearly audible waveform instead of silence." % stream_name)
	_expect(clipped_samples == 0, "%s should preserve headroom instead of hard-clipping synthesized samples." % stream_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
