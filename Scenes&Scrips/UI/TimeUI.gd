extends Control

@onready var lbl_time: Label = $Panel/VBoxContainer/TimeLabel
@onready var lbl_day: Label  = $Panel/VBoxContainer/DayLabel
@onready var lbl_week: Label = $Panel/VBoxContainer/WeekLabel

func _ready() -> void:
	_refresh_all()
	TimeManager.ten_minute_tick.connect(_refresh_time_and_week)
	TimeManager.day_changed.connect(_refresh_day_and_week)

func _refresh_all() -> void:
	_refresh_time_and_week()
	_refresh_day_and_week()

func _refresh_time_and_week() -> void:
	lbl_time.text = "%s" % TimeManager.get_time_string_hhmm()
	lbl_week.text = "%s (Day %d)" % [
		TimeManager.get_weekday_name(),
		TimeManager.get_weekday_index()
	]

func _refresh_day_and_week() -> void:
	lbl_day.text = "%d" % TimeManager.get_day_index()
	lbl_week.text = "%s (Day %d)" % [
		TimeManager.get_weekday_name(),
		TimeManager.get_weekday_index()
	]
	
