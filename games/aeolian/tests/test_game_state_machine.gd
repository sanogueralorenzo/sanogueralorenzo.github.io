extends RefCounted


static func run(suite: RefCounted) -> void:
	print("GameStateMachine")
	suite.run_test("valid flow reaches descent", func() -> void:
		var machine := GameStateMachine.new()
		suite.assert_true(machine.transition(GameStateMachine.State.TITLE))
		suite.assert_true(machine.transition(GameStateMachine.State.RUN_LOADING))
		suite.assert_true(machine.transition(GameStateMachine.State.RUN_INTRO))
		suite.assert_true(machine.transition(GameStateMachine.State.DESCENT))
		suite.assert_equal(machine.current, GameStateMachine.State.DESCENT)
	)
	suite.run_test("invalid transition preserves state", func() -> void:
		var machine := GameStateMachine.new()
		suite.assert_false(machine.transition(GameStateMachine.State.DESCENT))
		suite.assert_equal(machine.current, GameStateMachine.State.BOOT)
	)
	suite.run_test("pause and resume are explicit", func() -> void:
		var machine := GameStateMachine.new()
		machine.transition(GameStateMachine.State.TITLE)
		machine.transition(GameStateMachine.State.RUN_LOADING)
		machine.transition(GameStateMachine.State.RUN_INTRO)
		machine.transition(GameStateMachine.State.DESCENT)
		suite.assert_true(machine.transition(GameStateMachine.State.PAUSED))
		suite.assert_true(machine.transition(GameStateMachine.State.DESCENT))
	)
	suite.run_test("signal handlers cannot reenter transition", func() -> void:
		var machine := GameStateMachine.new()
		var nested_result := [true]
		var callback := func(_previous: GameStateMachine.State, _current: GameStateMachine.State) -> void:
			nested_result[0] = machine.transition(GameStateMachine.State.RUN_LOADING)
		machine.state_changed.connect(callback)
		suite.assert_true(machine.transition(GameStateMachine.State.TITLE))
		suite.assert_false(nested_result[0])
		suite.assert_equal(machine.current, GameStateMachine.State.TITLE)
		machine.state_changed.disconnect(callback)
	)
