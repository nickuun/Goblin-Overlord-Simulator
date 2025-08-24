extends Node
# (no class_name; the Autoload name will be the global symbol)

## Signals
signal ten_minute_tick                 # Fires when the HH:MM 10-min block changes
signal hour_tick                       # Fires on each exact hour
signal day_changed(new_day_index:int)  # Fires when we roll into a new day

## Config
const MINUTES_PER_DAY: int = 24 * 60
const START_HOUR: int = 8
const START_MINUTE: int = 0

# Goblin weekday names, Monday = index 0
@export var week_names: Array[String] = [
	"M’ndai", "Tüezdai", "Wednzdai", "Thurzdai", "F’ragedai", "Skraturdai", "Sündrai"
]

## Time flow
#@export var minutes_per_real_second: float = 2.0 #Oxygen Not Included pacing (~11–12 minutes per day)
@export var minutes_per_real_second: float = 20.0 #Oxygen Not Included pacing (~11–12 minutes per day)

var running: bool = true

## State
var _day_index: int = 0
var _minutes_since_midnight: int = START_HOUR * 60 + START_MINUTE  # 0..1439
var _accum_minutes: float = 0.0

# For 10-minute display blocks
var _last_ten_block: int = -1

func _ready() -> void:
	# Ensure first UI update on startup
	_emit_block_signals(true)

func _process(delta: float) -> void:
	if not running:
		return
	_accum_minutes += delta * minutes_per_real_second
	while _accum_minutes >= 1.0:
		_accum_minutes -= 1.0
		_step_one_minute()

func _step_one_minute() -> void:
	_minutes_since_midnight += 1

	# Hour wrap & tick
	if _minutes_since_midnight % 60 == 0:
		hour_tick.emit()

	# Day wrap
	if _minutes_since_midnight >= MINUTES_PER_DAY:
		_minutes_since_midnight -= MINUTES_PER_DAY
		_day_index += 1
		_emit_block_signals(true)  # ensure UI updates at day start
		day_changed.emit(_day_index)
	else:
		_emit_block_signals(false)

func _emit_block_signals(force: bool) -> void:
	var current_block := get_ten_minute_block()
	if force or current_block != _last_ten_block:
		_last_ten_block = current_block
		ten_minute_tick.emit()

## ------------ Public API ------------

func set_running(p_running: bool) -> void:
	running = p_running

func toggle_running() -> void:
	running = not running

func set_minutes_per_real_second(rate: float) -> void:
	minutes_per_real_second = max(rate, 0.0)

func get_day_index() -> int:
	return _day_index

func get_weekday_index() -> int:
	return _day_index % week_names.size()

func get_weekday_name() -> String:
	return week_names[get_weekday_index()]

func get_time_string_hhmm() -> String:
	# Display minutes snapped DOWN to 10-minute blocks
	var hour := int(_minutes_since_midnight / 60)
	var minute_block := int(_minutes_since_midnight / 10) * 10 % 60
	return "%02d:%02d" % [hour, minute_block]

func get_clock_components() -> Dictionary:
	var hour := int(_minutes_since_midnight / 60)
	var minute := _minutes_since_midnight % 60
	var minute_block := int(_minutes_since_midnight / 10) * 10 % 60
	return {
		"hour": hour,
		"minute": minute,
		"minute_block": minute_block,
		"day_index": _day_index,
		"weekday_index": get_weekday_index(),
		"weekday_name": get_weekday_name()
	}

func get_ten_minute_block() -> int:
	# 0..143 (144 blocks per day)
	return int(_minutes_since_midnight / 10)

func set_time(day_index: int, hour: int, minute: int) -> void:
	_day_index = max(day_index, 0)
	_minutes_since_midnight = clamp(hour, 0, 23) * 60 + clamp(minute, 0, 59)
	_emit_block_signals(true)

func advance_minutes(minutes: int) -> void:
	var total := _minutes_since_midnight + minutes
	if total >= 0:
		_day_index += int(total / MINUTES_PER_DAY)
		_minutes_since_midnight = total % MINUTES_PER_DAY
	else:
		var days_back := int((abs(total) + MINUTES_PER_DAY - 1) / MINUTES_PER_DAY)
		_day_index = max(0, _day_index - days_back)
		_minutes_since_midnight = (total % MINUTES_PER_DAY + MINUTES_PER_DAY) % MINUTES_PER_DAY
	_emit_block_signals(true)

func advance_hours(hours: int) -> void:
	advance_minutes(hours * 60)

func advance_days(days: int) -> void:
	_day_index = max(0, _day_index + days)
	_emit_block_signals(true)
