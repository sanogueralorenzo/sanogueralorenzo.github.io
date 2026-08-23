class_name GameStateMachine
extends RefCounted

signal state_changed(previous: State, current: State)
signal transition_rejected(previous: State, requested: State)

enum State {
	BOOT,
	TITLE,
	RUN_LOADING,
	RUN_INTRO,
	DESCENT,
	PAUSED,
	TRANSITION,
	CRASH,
	RESULTS,
}

const ALLOWED_TRANSITIONS := {
	State.BOOT: [State.TITLE],
	State.TITLE: [State.RUN_LOADING],
	State.RUN_LOADING: [State.RUN_INTRO, State.TITLE],
	State.RUN_INTRO: [State.DESCENT, State.TITLE],
	State.DESCENT: [State.PAUSED, State.TRANSITION, State.CRASH, State.RESULTS, State.TITLE],
	State.PAUSED: [State.DESCENT, State.TITLE],
	State.TRANSITION: [State.DESCENT, State.RESULTS, State.TITLE],
	State.CRASH: [State.RESULTS, State.TITLE],
	State.RESULTS: [State.RUN_LOADING, State.TITLE],
}

var current: State = State.BOOT
var _transitioning := false


func can_transition(next: State) -> bool:
	return next in ALLOWED_TRANSITIONS.get(current, [])


func transition(next: State) -> bool:
	if _transitioning or not can_transition(next):
		transition_rejected.emit(current, next)
		return false
	_transitioning = true
	var previous := current
	current = next
	state_changed.emit(previous, current)
	_transitioning = false
	return true


static func label(state: State) -> String:
	return State.keys()[state].to_pascal_case()
