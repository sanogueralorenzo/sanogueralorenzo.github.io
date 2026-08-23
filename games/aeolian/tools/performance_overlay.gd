extends CanvasLayer

@onready var panel: Control = %Panel
@onready var readout: Label = %Readout

var _time_until_refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		queue_free()
		return
	panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug") and not event.is_echo():
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_time_until_refresh -= delta
	if _time_until_refresh > 0.0:
		return
	_time_until_refresh = 0.25
	readout.text = "FPS %d\nFrame %.2f ms\nPhysics %.2f ms\nDraw calls %d\nNodes %d\nInput %s" % [
		int(Performance.get_monitor(Performance.TIME_FPS)),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		InputService.device_label(),
	]
