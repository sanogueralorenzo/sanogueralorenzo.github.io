extends SceneTree

const JumpAssist = preload("res://scripts/jump_assist_state.gd")

var _failures: Array[String] = []


func _init() -> void:
	var assist := JumpAssist.new()
	assist.configure(0.13, 0.1)
	assist.tick(0.016, true)
	assist.queue_jump()
	_expect(assist.try_consume(true), "A grounded queued jump should fire immediately.")
	_expect(not assist.try_consume(true), "One press must never trigger multiple jumps.")

	assist.reset()
	assist.tick(0.016, true)
	assist.tick(0.075, false)
	assist.queue_jump()
	_expect(assist.try_consume(false), "A jump within the coyote window should remain responsive after leaving sand.")

	assist.reset()
	assist.tick(0.016, true)
	assist.tick(0.11, false)
	assist.queue_jump()
	_expect(not assist.try_consume(false), "Expired coyote time must not create an airborne jump.")
	assist.tick(0.04, false)
	assist.tick(0.016, true)
	_expect(assist.try_consume(true), "A recent airborne press should buffer through the next valid landing.")

	assist.reset()
	assist.queue_jump()
	assist.tick(0.14, false)
	assist.tick(0.016, true)
	_expect(not assist.try_consume(true), "An expired buffered press must not cause a delayed surprise jump.")

	if _failures.is_empty():
		print("Jump assist passed — single-consume ground, 100 ms coyote, 130 ms landing buffer, and expiration agree.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
