extends Control

signal resume_requested
signal title_requested

@onready var resume_button: Button = %ResumeButton
@onready var title_button: Button = %TitleButton
@onready var notice_label: Label = %NoticeLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(resume_requested.emit)
	title_button.pressed.connect(title_requested.emit)


func show_and_focus() -> void:
	notice_label.text = ""
	show()
	resume_button.grab_focus.call_deferred()


func set_notice(message: String) -> void:
	notice_label.text = message

